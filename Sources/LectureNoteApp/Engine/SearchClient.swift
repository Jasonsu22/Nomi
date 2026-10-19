import Foundation

enum SearchClient {
    static func search(vendor: SearchVendor, key: String, baseURL: String, query: String, limit: Int = 5) async throws -> [SearchHit] {
        let request = try makeRequest(vendor: vendor, key: key, baseURL: baseURL, query: query, limit: limit)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration, delegate: SearchSameOriginRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw llmError(failureMessage(vendor: vendor, status: code, data: data, key: key))
        }
        return try hits(vendor: vendor, data: data, limit: limit)
    }

    static func hits(vendor: SearchVendor, data: Data, limit: Int = 5) throws -> [SearchHit] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw llmError(tr("搜索响应无法解析。"))
        }
        let rows: [[String: Any]]
        switch vendor {
        case .tavily, .exa, .searxng:
            rows = object["results"] as? [[String: Any]] ?? []
        }
        return Array(rows.compactMap { hit(vendor: vendor, row: $0) }.prefix(max(0, limit)))
    }

    static func failureMessage(vendor: SearchVendor, status: Int, data: Data, key: String) -> String {
        if vendor == .searxng, status == 403 {
            return tr("这台 SearXNG 没有打开 JSON。在它的设置里把 json 加进 search.formats。")
        }
        let body = redact(shortBody(data), key: key)
        return trf("API 请求失败（HTTP %d）：%@", status, body)
    }

    private static func makeRequest(vendor: SearchVendor, key: String, baseURL: String, query: String, limit: Int) throws -> URLRequest {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        var request: URLRequest
        switch vendor {
        case .tavily:
            request = URLRequest(url: URL(string: "https://api.tavily.com/search")!, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try json(["query": query, "max_results": limit, "search_depth": "basic"])
        case .exa:
            request = URLRequest(url: URL(string: "https://api.exa.ai/search")!, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
            request.httpBody = try json(["query": query, "numResults": limit, "contents": ["highlights": true]])
        case .searxng:
            let base = try SearchURL.normalize(baseURL)
            guard var components = URLComponents(string: base + "/search") else { throw llmError(tr("请填写有效的搜索地址。")) }
            components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "format", value: "json")]
            guard let url = components.url else { throw llmError(tr("请填写有效的搜索地址。")) }
            request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "GET"
            if !trimmedKey.isEmpty { request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization") }
        }
        if request.httpBody != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    private static func hit(vendor: SearchVendor, row: [String: Any]) -> SearchHit? {
        let rawURL = (row["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: rawURL), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        let title = plain(row["title"] as? String ?? "")
        let snippet: String
        switch vendor {
        case .tavily, .searxng:
            snippet = plain(row["content"] as? String ?? "")
        case .exa:
            snippet = plain(exaHighlight(row))
        }
        return SearchHit(title: title, url: rawURL, snippet: clip(snippet))
    }

    private static func exaHighlight(_ row: [String: Any]) -> String {
        if let highlights = row["highlights"] as? [String], let first = highlights.first { return first }
        if let contents = row["contents"] as? [String: Any],
           let highlights = contents["highlights"] as? [String], let first = highlights.first { return first }
        return row["text"] as? String ?? ""
    }

    private static func plain(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>") else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clip(_ text: String) -> String {
        guard text.count > 600 else { return text }
        return String(text.prefix(600))
    }

    private static func shortBody(_ data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = object["message"] as? String { return String(message.prefix(180)) }
            if let error = object["error"] as? String { return String(error.prefix(180)) }
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                return String(message.prefix(180))
            }
            if let detail = object["detail"] as? String { return String(detail.prefix(180)) }
        }
        return String((String(data: data.prefix(180), encoding: .utf8) ?? "").prefix(180))
    }

    private static func redact(_ text: String, key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        return text.replacingOccurrences(of: trimmed, with: "••••")
    }

    private static func json(_ body: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: body)
    }
}

private final class SearchSameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let original = task.originalRequest?.url
        let same = original?.scheme == request.url?.scheme && original?.host == request.url?.host && original?.port == request.url?.port
        completionHandler(same ? request : nil)
    }
}
