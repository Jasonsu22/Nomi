import Foundation

enum RemoteLLMClient {
    static func models(profile: LLMAPIProfile, key: String) async throws -> [String] {
        let profile = try profile.validated(requireModel: false)
        var result: Set<String> = []
        var lastID: String?
        var seenPages: Set<String> = []
        for _ in 0..<50 {
            var request = request(profile: profile, path: "models", key: key)
            request.httpMethod = "GET"
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
        var request = request(profile: profile, path: profile.format == .anthropic ? "messages" : "chat/completions", key: key)
        request.httpMethod = "POST"
        var body: [String: Any] = ["model": profile.modelID, "stream": false]
        if profile.format == .anthropic {
            body["system"] = system
            body["max_tokens"] = 2048
            body["messages"] = [["role": "user", "content": prompt]]
        } else {
            body["messages"] = [["role": "system", "content": system], ["role": "user", "content": prompt]]
            if URL(string: profile.baseURL)?.host == "api.openai.com" {
                body["max_completion_tokens"] = 2048
                body["store"] = false
            } else {
                body["max_tokens"] = 2048
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let object = try await perform(request, key: key)
        let text: String
        if profile.format == .anthropic {
            text = (object["content"] as? [[String: Any]] ?? [])
                .filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        } else {
            let message = (object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
            text = message?["content"] as? String
                ?? (message?["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n")
                ?? message?["refusal"] as? String ?? ""
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw llmError(tr("模型未返回文字，请检查所选模型和接口格式。")) }
        return text
    }

    private static func request(profile: LLMAPIProfile, path: String, key: String) -> URLRequest {
        var request = URLRequest(url: URL(string: profile.baseURL + "/" + path)!, timeoutInterval: 180)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if profile.format == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private static func perform(_ request: URLRequest, key: String) async throws -> [String: Any] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 300
        let session = URLSession(configuration: configuration, delegate: SameOriginRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            var message = (object["error"] as? [String: Any])?["message"] as? String ?? ""
            if !key.isEmpty { message = message.replacingOccurrences(of: key, with: "••••") }
            throw llmError(trf("API 请求失败（HTTP %d）：%@", code, String(message.prefix(400))))
        }
        return object
    }
}

private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let original = task.originalRequest?.url
        let same = original?.scheme == request.url?.scheme && original?.host == request.url?.host && original?.port == request.url?.port
        completionHandler(same ? request : nil)
    }
}
