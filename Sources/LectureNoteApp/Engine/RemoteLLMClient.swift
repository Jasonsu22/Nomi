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

    /// A reply that ended without any text. The details say what the service actually sent.
    struct EmptyReply: LocalizedError, Equatable {
        var status: Int
        var events: Int
        var finishReason: String?
        var retried = false

        var errorDescription: String? {
            var detail = trf("HTTP %d · %d 个事件 · 结束原因：%@", status, events, finishReason ?? "none")
            if retried { detail += " · " + tr("已自动重试一次") }
            return tr("模型未返回文字，请检查所选模型和接口格式。") + " (\(detail))"
        }
    }

    /// A service's error reply, with the status and its own message so a retry can tell what it refused.
    struct HTTPFailure: LocalizedError {
        var status: Int
        var detail: String
        var errorDescription: String? { trf("API 请求失败（HTTP %d）：%@", status, String(detail.prefix(400))) }
    }

    /// A single question without earlier turns or thinking, for summaries, demos and side tasks.
    static func generate(
        profile: LLMAPIProfile,
        key: String,
        system: String,
        prompt: String,
        images: [ModelImage] = [],
        onUpdate: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let request = LLMRequest.single(system: system, prompt: prompt, images: images)
        return try await stream(profile: profile, key: key, request: request) { progress in
            if !progress.answer.isEmpty { onUpdate(progress.answer) }
        }.answer
    }

    /// Sends one request and streams the answer and the thinking.
    /// - An empty reply is sometimes a passing hiccup, so it is sent once more.
    /// - A service without Responses gets Chat Completions.
    /// - A service that refuses thinking, usage reports or the cache key gets the request without them.
    /// The result says which of these happened, so the profile can remember it.
    static func stream(
        profile: LLMAPIProfile,
        key: String,
        request: LLMRequest,
        onProgress: @escaping @MainActor (LLMProgress) -> Void
    ) async throws -> LLMResult {
        var options = LLMRequestBody.Options()
        var mode = profile.effectiveAPIMode
        var responsesRejected = false
        var emptyRetried = false
        let started = Date()
        let first = FirstToken()
        let watched: @MainActor (LLMProgress) -> Void = { progress in
            if first.date == nil { first.date = Date() }
            onProgress(progress)
        }
        var lastError: Error?
        for _ in 0..<5 {
            do {
                var result = try await send(profile: profile, key: key, request: request, mode: mode, options: options, onProgress: watched)
                result.responsesRejected = responsesRejected
                result.thinkingRejected = request.thinking != .off && !options.thinking
                RequestLog.record(.init(profile: profile, request: request, mode: mode, options: options, started: started,
                                        firstToken: first.date, usage: result.usage, failure: nil))
                return result
            } catch let failure as HTTPFailure where mode == .responses && LLMRequestBody.lacksResponses(status: failure.status, message: failure.detail) {
                mode = .chatCompletions
                responsesRejected = true
                lastError = failure
            } catch let failure as HTTPFailure where LLMRequestBody.rejectsOption(status: failure.status, message: failure.detail) && (options.thinking || options.extras) {
                let text = failure.detail.lowercased()
                let aboutThinking = ["reasoning", "thinking", "effort"].contains { text.contains($0) }
                if options.thinking && request.thinking != .off && (aboutThinking || !options.extras) {
                    options.thinking = false
                } else if options.extras {
                    options.extras = false
                } else {
                    options.thinking = false
                }
                lastError = failure
            } catch var empty as EmptyReply {
                guard !emptyRetried else {
                    empty.retried = true
                    lastError = empty
                    break
                }
                emptyRetried = true
                lastError = empty
            } catch {
                lastError = error
                break
            }
            try Task.checkCancellation()
        }
        let error = lastError ?? llmError(tr("模型未返回文字，请检查所选模型和接口格式。"))
        RequestLog.record(.init(profile: profile, request: request, mode: mode, options: options, started: started,
                                firstToken: first.date, usage: LLMUsage(), failure: error.localizedDescription))
        throw error
    }

    private static func send(
        profile: LLMAPIProfile,
        key: String,
        request: LLMRequest,
        mode: LLMAPIMode,
        options: LLMRequestBody.Options,
        onProgress: @escaping @MainActor (LLMProgress) -> Void
    ) async throws -> LLMResult {
        let profile = try profile.validated()
        let made = LLMRequestBody.make(profile: profile, request: request, mode: mode, options: options)
        var urlRequest = self.request(profile: profile, path: made.path, key: key, sendsJSON: true)
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: made.body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: configuration, delegate: SameOriginRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.bytes(for: urlRequest)
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        let type = http?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if !(200..<300).contains(code) || (type.contains("json") && !type.contains("event-stream")) {
            let data = try await data(from: bytes)
            if !(200..<300).contains(code) { throw failure(data, code: code, key: key) }
            return try await complete(data, status: code, key: key, onProgress: onProgress)
        }
        return try await events(bytes, status: code, key: key, waitsForUsage: options.extras, onProgress: onProgress)
    }

    private static func events(_ bytes: URLSession.AsyncBytes, status: Int, key: String, waitsForUsage: Bool, onProgress: @escaping @MainActor (LLMProgress) -> Void) async throws -> LLMResult {
        var iterator = bytes.lines.makeAsyncIterator()
        var pending: String?
        while let line = try await iterator.next() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                var raw = line
                while let more = try await iterator.next() { raw += "\n" + more }
                return try await complete(Data(raw.utf8), status: status, key: key, onProgress: onProgress)
            }
            pending = line
            break
        }
        var accumulator = ChatStream.Accumulator()
        var last = Date.distantPast
        var shown = LLMProgress()
        var pendingLine = pending
        // Chat Completions reports usage in one more event after the finish reason.
        var linesAfterFinish = 0
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
            var done = false
            switch ChatStream.line(line) {
            case .skip:
                continue
            case .done:
                accumulator.finished = true
                done = true
            case .payload(let payload):
                guard let object = ChatStream.object(from: payload) else { continue }
                if let message = accumulator.apply(object) {
                    throw llmError(redacted(message, key: key))
                }
            }
            let progress = LLMProgress(answer: accumulator.display, thinking: accumulator.thinking)
            if progress != shown, !(progress.answer.isEmpty && progress.thinking.isEmpty), Date().timeIntervalSince(last) >= 0.05 {
                last = Date()
                shown = progress
                await MainActor.run { onProgress(progress) }
            }
            if done { break }
            if accumulator.finished {
                linesAfterFinish += 1
                if !waitsForUsage || accumulator.usage.input != nil || linesAfterFinish > 3 { break }
            }
        }
        accumulator.finished = true
        let answer = accumulator.answer
        guard !answer.isEmpty else {
            throw EmptyReply(status: status, events: accumulator.events, finishReason: accumulator.finishReason)
        }
        let final = LLMProgress(answer: answer, thinking: accumulator.thinking)
        if final != shown { await MainActor.run { onProgress(final) } }
        return LLMResult(answer: answer, thinking: accumulator.thinking, usage: accumulator.usage)
    }

    private static func complete(_ data: Data, status: Int, key: String, onProgress: @escaping @MainActor (LLMProgress) -> Void) async throws -> LLMResult {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw failure(data, code: 200, key: key)
        }
        if let failure = serviceFailure(in: object) {
            throw HTTPFailure(status: 200, detail: redacted(failure, key: key))
        }
        var accumulator = ChatStream.Accumulator()
        if let message = accumulator.apply(object) {
            throw llmError(redacted(message, key: key))
        }
        accumulator.finished = true
        let answer = accumulator.answer
        guard !answer.isEmpty else {
            throw EmptyReply(status: status, events: accumulator.events, finishReason: accumulator.finishReason)
        }
        let progress = LLMProgress(answer: answer, thinking: accumulator.thinking)
        await MainActor.run { onProgress(progress) }
        return LLMResult(answer: answer, thinking: accumulator.thinking, usage: accumulator.usage)
    }

    private static func data(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        return data
    }

    private static func failure(_ data: Data, code: Int, key: String) -> Error {
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let message = serviceFailure(in: object) {
            return HTTPFailure(status: code, detail: redacted(message, key: key))
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        return HTTPFailure(status: code, detail: redacted(String(raw.prefix(2000)), key: key))
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

    static func openAIContent(prompt: String, images: [ModelImage], miniMax: Bool) -> Any {
        guard !images.isEmpty else { return prompt }
        var parts: [[String: Any]] = [["type": "text", "text": prompt]]
        for image in images {
            var imageURL: [String: Any] = ["url": "data:\(image.mime);base64,\(image.base64)"]
            if miniMax { imageURL["detail"] = "default" }
            parts.append(["type": "image_url", "image_url": imageURL])
        }
        return parts
    }

    static func anthropicContent(prompt: String, images: [ModelImage]) -> Any {
        guard !images.isEmpty else { return prompt }
        var parts: [[String: Any]] = [["type": "text", "text": prompt]]
        for image in images {
            parts.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": image.mime,
                    "data": image.base64,
                ],
            ])
        }
        return parts
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

/// When the first thinking or answer text arrived. Written on the main actor while streaming, read after.
private final class FirstToken: @unchecked Sendable {
    var date: Date?
}

private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let original = task.originalRequest?.url
        let same = original?.scheme == request.url?.scheme && original?.host == request.url?.host && original?.port == request.url?.port
        completionHandler(same ? request : nil)
    }
}
