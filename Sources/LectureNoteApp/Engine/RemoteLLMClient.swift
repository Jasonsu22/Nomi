import Foundation

enum RemoteLLMClient {
    static func models(profile: LLMAPIProfile, key: String) async throws -> [String] {
        let profile = try profile.validated(requireModel: false)
        var result: Set<String> = []
        var lastID: String?
        var seenPages: Set<String> = []
        for _ in 0..<50 {
            var request = request(profile: profile, path: "models", key: key, sendsJSON: false)
            if profile.format == .anthropic {
                var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                url.queryItems = [URLQueryItem(name: "limit", value: "100")]
                if let lastID { url.queryItems?.append(.init(name: "after_id", value: lastID)) }
                request.url = url.url
            }
            let object = try await perform(request, key: key)
            guard let data = object["data"] as? [[String: Any]] else { throw llmError(tr("服务未返回模型列表，可以手动填写模型 ID。")) }
            result.formUnion(data.compactMap { $0["id"] as? String })
            guard profile.format == .anthropic, object["has_more"] as? Bool == true,
                  let next = object["last_id"] as? String, seenPages.insert(next).inserted else { break }
            lastID = next
        }
        return result.sorted()
    }

    static func generate(
        profile: LLMAPIProfile,
        key: String,
        system: String,
        prompt: String,
        onUpdate: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let profile = try profile.validated()
        var request = request(
            profile: profile,
            path: profile.format == .anthropic ? "messages" : "chat/completions",
            key: key,
            sendsJSON: true
        )
        let body: [String: Any]
        if profile.format == .anthropic {
            body = [
                "model": profile.modelID,
                "system": system,
                "max_tokens": 2048,
                "messages": [["role": "user", "content": prompt]],
                "stream": true,
            ]
        } else {
            var chat: [String: Any] = [
                "model": profile.modelID,
                "messages": [["role": "system", "content": system], ["role": "user", "content": prompt]],
                "stream": true,
            ]
            if host(of: profile) == "api.openai.com" {
                chat["max_completion_tokens"] = 2048
                chat["store"] = false
            } else if isMiniMax(profile) {
                chat["max_completion_tokens"] = 2048
            } else {
                chat["max_tokens"] = 2048
            }
            body = chat
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration, delegate: SameOriginRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.bytes(for: request)
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        let type = http?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if !(200..<300).contains(code) || (type.contains("json") && !type.contains("event-stream")) {
            let data = try await data(from: bytes)
            if !(200..<300).contains(code) { throw failure(data, code: code, key: key) }
            return try await complete(data, key: key, onUpdate: onUpdate)
        }
        return try await events(bytes, key: key, onUpdate: onUpdate)
    }

    private static func events(_ bytes: URLSession.AsyncBytes, key: String, onUpdate: @escaping @MainActor (String) -> Void) async throws -> String {
        var iterator = bytes.lines.makeAsyncIterator()
        var pending: String?
        while let line = try await iterator.next() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                var raw = line
                while let more = try await iterator.next() { raw += "\n" + more }
                return try await complete(Data(raw.utf8), key: key, onUpdate: onUpdate)
            }
            pending = line
            break
        }
        var accumulator = ChatStream.Accumulator()
        var last = Date.distantPast
        var shown = ""
        var pendingLine = pending
        while true {
            let line: String
            if let queued = pendingLine {
                line = queued
                pendingLine = nil
            } else if let next = try await iterator.next() {
                line = next
            } else {
                break
            }
            try Task.checkCancellation()
            switch ChatStream.line(line) {
            case .skip:
                continue
            case .done:
                accumulator.finished = true
            case .payload(let payload):
                guard let object = ChatStream.object(from: payload) else { continue }
                if let message = accumulator.apply(object) {
                    throw llmError(redacted(message, key: key))
                }
            }
            let text = accumulator.display
            if text != shown, !text.isEmpty, Date().timeIntervalSince(last) >= 0.05 {
                last = Date()
                shown = text
                await MainActor.run { onUpdate(text) }
            }
            if accumulator.finished { break }
        }
        accumulator.finished = true
        let answer = accumulator.answer
        guard !answer.isEmpty else { throw llmError(tr("模型未返回文字，请检查所选模型和接口格式。")) }
        if answer != shown { await MainActor.run { onUpdate(answer) } }
        return answer
    }

    private static func complete(_ data: Data, key: String, onUpdate: @escaping @MainActor (String) -> Void) async throws -> String {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw failure(data, code: 200, key: key)
        }
        if let failure = serviceFailure(in: object) {
            throw llmError(redacted(trf("API 请求失败（HTTP %d）：%@", 200, String(failure.prefix(400))), key: key))
        }
        var accumulator = ChatStream.Accumulator()
        if let message = accumulator.apply(object) {
            throw llmError(redacted(message, key: key))
        }
        accumulator.finished = true
        let answer = accumulator.answer
        guard !answer.isEmpty else { throw llmError(tr("模型未返回文字，请检查所选模型和接口格式。")) }
        await MainActor.run { onUpdate(answer) }
        return answer
    }

    private static func data(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        return data
    }

    private static func failure(_ data: Data, code: Int, key: String) -> Error {
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let message = serviceFailure(in: object) {
            return llmError(redacted(trf("API 请求失败（HTTP %d）：%@", code, String(message.prefix(400))), key: key))
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        return llmError(redacted(trf("API 请求失败（HTTP %d）：%@", code, String(raw.prefix(400))), key: key))
    }

    private static func request(profile: LLMAPIProfile, path: String, key: String, sendsJSON: Bool) -> URLRequest {
        let base = profile.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: URL(string: base + "/" + path)!, timeoutInterval: 180)
        request.httpMethod = sendsJSON ? "POST" : "GET"
        if sendsJSON { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if profile.format == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private static func host(of profile: LLMAPIProfile) -> String {
        URL(string: profile.baseURL)?.host?.lowercased() ?? ""
    }

    private static func isMiniMax(_ profile: LLMAPIProfile) -> Bool {
        host(of: profile).contains("minimax")
    }

    private static func perform(_ request: URLRequest, key: String) async throws -> [String: Any] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration, delegate: SameOriginRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw llmError(redacted(trf("API 请求失败（HTTP %d）：%@", code, String(raw.prefix(400))), key: key))
        }
        if let failure = serviceFailure(in: object) {
            throw llmError(redacted(trf("API 请求失败（HTTP %d）：%@", code, String(failure.prefix(400))), key: key))
        }
        guard (200..<300).contains(code) else {
            throw llmError(redacted(trf("API 请求失败（HTTP %d）：%@", code, ""), key: key))
        }
        return object
    }

    private static func serviceFailure(in object: [String: Any]) -> String? {
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = object["error"] as? String, !error.isEmpty { return error }
        if let base = object["base_resp"] as? [String: Any] {
            let status = base["status_code"] as? Int ?? (base["status_code"] as? NSNumber)?.intValue ?? 0
            if status != 0 {
                let message = base["status_msg"] as? String ?? ""
                return message.isEmpty ? "\(status)" : message
            }
        }
        if let message = object["message"] as? String, !message.isEmpty, object["choices"] == nil, object["data"] == nil {
            return message
        }
        return nil
    }

    private static func redacted(_ message: String, key: String) -> String {
        guard !key.isEmpty else { return message }
        return message.replacingOccurrences(of: key, with: "••••")
    }
}

private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let original = task.originalRequest?.url
        let same = original?.scheme == request.url?.scheme && original?.host == request.url?.host && original?.port == request.url?.port
        completionHandler(same ? request : nil)
    }
}
