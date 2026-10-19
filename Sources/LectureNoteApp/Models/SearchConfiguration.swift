import Foundation
import Observation
import Security

enum SearchVendor: String, CaseIterable, Identifiable, Sendable {
    case tavily, exa, searxng

    var id: String { rawValue }
    var title: String {
        switch self {
        case .tavily: "Tavily"
        case .exa: "Exa"
        case .searxng: "SearXNG"
        }
    }
    var logoFile: String { "search-\(rawValue)" }
    var needsBaseURL: Bool { self == .searxng }
    var accountURL: URL {
        switch self {
        case .tavily: URL(string: "https://app.tavily.com/home")!
        case .exa: URL(string: "https://dashboard.exa.ai/api-keys")!
        case .searxng: URL(string: "https://docs.searxng.org/")!
        }
    }
}

struct SearchHit: Equatable, Sendable {
    var title: String
    var url: String
    var snippet: String

    func contextBlock() -> ContextBlock {
        let host = URL(string: url)?.host ?? ""
        let shown = title.isEmpty ? (host.isEmpty ? url : host) : title
        let body = snippet.isEmpty ? url : "\(snippet)\n\(url)"
        return ContextBlock(title: shown, detail: host, body: body, url: url)
    }
}

enum SearchURL {
    static func normalize(_ raw: String) throws -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw llmError(tr("请填写有效的搜索地址。"))
        }
        var cleaned = URLComponents()
        cleaned.scheme = scheme
        cleaned.host = host
        if let port = components.port { cleaned.port = port }
        if !components.path.isEmpty, components.path != "/" { cleaned.path = components.path }
        guard let value = cleaned.string else { throw llmError(tr("请填写有效的搜索地址。")) }
        return value
    }
}

enum SearchKeychain {
    private static let service = "local.nomi.search-api"

    private static func query(_ vendor: SearchVendor) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: vendor.rawValue]
    }

    /// Whether a key is stored. Does not read the secret, so it does not raise the keychain password dialog.
    static func contains(_ vendor: SearchVendor) -> Bool {
        var request = query(vendor)
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func read(_ vendor: SearchVendor) throws -> String {
        var request = query(vendor)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw llmError(tr("无法读取钥匙串中的 API 密钥。"))
        }
        return key
    }

    static func save(_ key: String, vendor: SearchVendor) throws {
        let values = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query(vendor) as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(vendor)
            item[kSecValueData as String] = Data(key.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw llmError(tr("无法保存 API 密钥到钥匙串。")) }
        } else if status != errSecSuccess { throw llmError(tr("无法保存 API 密钥到钥匙串。")) }
    }

    static func delete(_ vendor: SearchVendor) throws {
        let status = SecItemDelete(query(vendor) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw llmError(tr("无法删除钥匙串中的 API 密钥。")) }
    }
}

@MainActor
@Observable
final class SearchConfiguration {
    private(set) var activeID: String?
    private(set) var guideDismissed: Bool
    private(set) var revision = 0
    private var keyCache: [String: String] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        activeID = defaults.string(forKey: Self.activeKey)
        guideDismissed = defaults.bool(forKey: Self.guideKey)
    }

    var activeVendor: SearchVendor? { activeID.flatMap(SearchVendor.init(rawValue:)) }

    var selected: SearchVendor? {
        guard let activeVendor, isReady(activeVendor) else { return nil }
        return activeVendor
    }

    var isActiveReady: Bool { selected != nil }

    var hasReadyProvider: Bool { SearchVendor.allCases.contains(where: isReady) }

    func isReady(_ vendor: SearchVendor) -> Bool {
        _ = revision
        if vendor.needsBaseURL {
            guard let base = defaults.string(forKey: Self.baseKey(vendor.rawValue)) else { return false }
            return (try? SearchURL.normalize(base)) != nil
        }
        return SearchKeychain.contains(vendor)
    }

    func status(for vendor: SearchVendor) -> String {
        guard isReady(vendor) else { return tr("未配置") }
        if vendor.needsBaseURL, storedKey(vendor).isEmpty {
            return defaults.string(forKey: Self.baseKey(vendor.rawValue)) ?? tr("已保存密钥")
        }
        return tr("已保存密钥")
    }

    func endpoint(for vendor: SearchVendor) -> String {
        if vendor.needsBaseURL { return defaults.string(forKey: Self.baseKey(vendor.rawValue)) ?? "" }
        return ""
    }

    func select(_ vendor: SearchVendor) {
        guard isReady(vendor) else { return }
        storeActive(vendor)
        revision += 1
    }

    func dismissGuide() {
        guideDismissed = true
        defaults.set(true, forKey: Self.guideKey)
        revision += 1
    }

    func save(vendor: SearchVendor, key: String, baseURL: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = vendor.needsBaseURL ? try SearchURL.normalize(baseURL) : nil
        if !vendor.needsBaseURL, trimmedKey.isEmpty { throw llmError(tr("请输入 API 密钥。")) }
        if trimmedKey.isEmpty {
            try SearchKeychain.delete(vendor)
            keyCache[vendor.rawValue] = ""
        } else {
            try SearchKeychain.save(trimmedKey, vendor: vendor)
            keyCache[vendor.rawValue] = trimmedKey
        }
        if let normalized { defaults.set(normalized, forKey: Self.baseKey(vendor.rawValue)) }
        if selected == nil { storeActive(vendor) }
        revision += 1
    }

    @discardableResult
    func delete(_ vendor: SearchVendor) throws -> Bool {
        try SearchKeychain.delete(vendor)
        keyCache[vendor.rawValue] = ""
        defaults.removeObject(forKey: Self.baseKey(vendor.rawValue))
        let wasActive = activeID == vendor.rawValue
        if wasActive { storeActive(nil) }
        revision += 1
        return wasActive
    }

    func test(vendor: SearchVendor, key: String, baseURL: String) async throws -> Int {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint: String
        if vendor.needsBaseURL {
            endpoint = try SearchURL.normalize(baseURL)
        } else {
            guard !trimmed.isEmpty else { throw llmError(tr("请输入 API 密钥。")) }
            endpoint = ""
        }
        let hits = try await SearchClient.search(vendor: vendor, key: trimmed, baseURL: endpoint, query: "nomi")
        return hits.count
    }

    func testSaved(_ vendor: SearchVendor) async throws -> Int {
        try await test(vendor: vendor, key: storedKey(vendor), baseURL: endpoint(for: vendor))
    }

    func lookup(_ query: String) async throws -> [SearchHit] {
        guard let vendor = selected else { throw llmError(tr("先在设置里配置一个搜索服务")) }
        return try await SearchClient.search(
            vendor: vendor,
            key: storedKey(vendor),
            baseURL: endpoint(for: vendor),
            query: query
        )
    }

    private func storedKey(_ vendor: SearchVendor) -> String {
        if let cached = keyCache[vendor.rawValue] { return cached }
        do {
            let key = try SearchKeychain.read(vendor)
            keyCache[vendor.rawValue] = key
            return key
        } catch {
            return ""
        }
    }

    private func storeActive(_ vendor: SearchVendor?) {
        activeID = vendor?.rawValue
        if let vendor { defaults.set(vendor.rawValue, forKey: Self.activeKey) }
        else { defaults.removeObject(forKey: Self.activeKey) }
    }

    private static let activeKey = "nomi.search.active"
    private static let guideKey = "nomi.search.guideDismissed"
    private static func baseKey(_ id: String) -> String { "nomi.search.baseURL.\(id)" }
}
