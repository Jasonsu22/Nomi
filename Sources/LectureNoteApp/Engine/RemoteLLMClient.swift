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

    static func generate(profile: LLMAPIProfile, key: String, system: String, prompt: String) async throws -> String {
        let profile = try profile.validated()
        var request = request(profile: profile, path: profile.format == .anthropic ? "messages" : "chat/completions", key: key, sendsJSON: true)
        var body: [String: Any] = ["model": profile.modelID, "stream": false]
        if profile.format == .anthropic {
            body["system"] = system
            body["max_tokens"] = 2048
            body["messages"] = [["role": "user", "content": prompt]]
        } else {
            body["messages"] = [["role": "system", "content": system], ["role": "user", "content": prompt]]
            if host(of: profile) == "api.openai.com" {
                body["max_completion_tokens"] = 2048
                body["store"] = false
            } else if isMiniMax(profile) {
                body["max_completion_tokens"] = 2048
            } else {
                body["max_tokens"] = 2048
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let object = try await perform(request, key: key)
        let text: String
        if profile.format == .anthropic {
            let blocks = object["content"] as? [[String: Any]] ?? []
            text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
                + webLinks(in: blocks)
        } else {
            let message = (object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
            text = messageText(message)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw llmError(tr("模型未返回文字，请检查所选模型和接口格式。")) }
        return text
    }

    private static func webLinks(in blocks: [[String: Any]]) -> String {
        let links = blocks.flatMap { block in
            (block["citations"] as? [[String: Any]] ?? []).compactMap { cite -> String? in
                guard let url = cite["url"] as? String else { return nil }
                let title = (cite["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? url : "\(title) \(url)"
            }
        }
        guard !links.isEmpty else { return "" }
        return "\n" + links.joined(separator: "\n")
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

    private static func messageText(_ message: [String: Any]?) -> String {
        guard let message else { return "" }
        if let content = message["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }
        if let parts = message["content"] as? [[String: Any]] {
            let joined = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return joined }
        }
        if let reasoning = message["reasoning_content"] as? String,
           !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return reasoning
        }
        return message["refusal"] as? String ?? ""
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
