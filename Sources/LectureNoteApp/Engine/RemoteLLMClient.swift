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

    static func generate(profile: LLMAPIProfile, key: String, system: String, prompt: String, allowsWeb: Bool = false) async throws -> String {
        let profile = try profile.validated()
        if allowsWeb, profile.format != .anthropic, URL(string: profile.baseURL)?.host == "api.openai.com" {
            return try await responses(profile: profile, key: key, system: system, prompt: prompt)
        }
        var request = request(profile: profile, path: profile.format == .anthropic ? "messages" : "chat/completions", key: key)
        request.httpMethod = "POST"
        var body: [String: Any] = ["model": profile.modelID, "stream": false]
        if profile.format == .anthropic {
            body["system"] = system
            body["max_tokens"] = 2048
            body["messages"] = [["role": "user", "content": prompt]]
            if allowsWeb {
                body["tools"] = [["type": "web_search_20250305", "name": "web_search", "max_uses": 3]]
                request.setValue("web-search-2025-03-05", forHTTPHeaderField: "anthropic-beta")
            }
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
            let blocks = object["content"] as? [[String: Any]] ?? []
            text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
                + webLinks(in: blocks)
        } else {
            let message = (object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
            text = message?["content"] as? String
                ?? (message?["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n")
                ?? message?["refusal"] as? String ?? ""
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw llmError(tr("模型未返回文字，请检查所选模型和接口格式。")) }
        return text
    }

    private static func responses(profile: LLMAPIProfile, key: String, system: String, prompt: String) async throws -> String {
        var request = request(profile: profile, path: "responses", key: key)
        request.httpMethod = "POST"
        let body: [String: Any] = [
            "model": profile.modelID,
            "instructions": system,
            "input": prompt,
            "tools": [["type": "web_search"]],
            "max_output_tokens": 2048,
            "store": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let object = try await perform(request, key: key)
        var parts: [String] = []
        for item in object["output"] as? [[String: Any]] ?? [] {
            guard item["type"] as? String == "message" else { continue }
            for block in item["content"] as? [[String: Any]] ?? [] {
                if let text = block["text"] as? String { parts.append(text) }
                parts.append(contentsOf: annotations(in: block))
            }
        }
        let text = parts.joined(separator: "\n")
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

    private static func annotations(in block: [String: Any]) -> [String] {
        (block["annotations"] as? [[String: Any]] ?? []).compactMap { note in
            guard let url = note["url"] as? String else { return nil }
            let title = (note["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? url : "\(title) \(url)"
        }
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
