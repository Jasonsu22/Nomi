import Foundation
import Observation

enum LLMMode: String, CaseIterable, Identifiable, Equatable {
    case local, api
    var id: String { rawValue }
    var title: String { self == .local ? tr("本地模型") : "API" }
}

enum LLMAPIFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI, anthropic
    var id: String { rawValue }
    var title: String { self == .openAI ? tr("OpenAI 兼容") : "Anthropic Messages" }
}

struct LLMAPIProfile: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var providerID = "custom"
    var name = ""
    var baseURL = ""
    var modelID = ""
    var format = LLMAPIFormat.openAI
    var savedModelIDs: [String] = []
    /// How many characters one request may carry, for a model with a small window. Nil uses
    /// `ContextBudget.api`. Not shown in Settings; edit it for a model that rejects long prompts.
    var contextCharacters: Int?

    init(
        id: UUID = UUID(),
        providerID: String = "custom",
        name: String = "",
        baseURL: String = "",
        modelID: String = "",
        format: LLMAPIFormat = .openAI,
        savedModelIDs: [String] = []
    ) {
        self.id = id
        self.providerID = providerID
        self.name = name
        self.baseURL = baseURL
        self.modelID = modelID
        self.format = format
        self.savedModelIDs = savedModelIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id, providerID, name, baseURL, modelID, format, savedModelIDs, contextCharacters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        providerID = try container.decodeIfPresent(String.self, forKey: .providerID) ?? "custom"
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID) ?? ""
        format = try container.decodeIfPresent(LLMAPIFormat.self, forKey: .format) ?? .openAI
        savedModelIDs = try container.decodeIfPresent([String].self, forKey: .savedModelIDs) ?? []
        contextCharacters = try container.decodeIfPresent(Int.self, forKey: .contextCharacters)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(name, forKey: .name)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(format, forKey: .format)
        try container.encode(savedModelIDs, forKey: .savedModelIDs)
        try container.encodeIfPresent(contextCharacters, forKey: .contextCharacters)
    }

    var isLoopback: Bool {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    func validated(requireModel: Bool = true) throws -> Self {
        var value = self
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        value.modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        var models: [String] = []
        for raw in savedModelIDs {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !models.contains(id) else { continue }
            models.append(id)
        }
        if !value.modelID.isEmpty, !models.contains(value.modelID) {
            models.insert(value.modelID, at: 0)
        }
        value.savedModelIDs = models
        guard !value.name.isEmpty, let url = URL(string: value.baseURL),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw llmError(tr("请填写名称和有效的 API 地址。"))
        }
        guard !requireModel || !value.modelID.isEmpty else { throw llmError(tr("请选择或填写模型 ID。")) }
        return value
    }
}

struct LLMProviderPreset: Identifiable {
    var id: String
    var name: String
    var baseURL: String
    var format: LLMAPIFormat = .openAI
    static let all: [Self] = [
        .init(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1"),
        .init(id: "anthropic", name: "Anthropic", baseURL: "https://api.anthropic.com/v1", format: .anthropic),
        .init(id: "gemini", name: "Google Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai"),
        .init(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1"),
        .init(id: "kimi", name: "Kimi", baseURL: "https://api.moonshot.ai/v1"),
        .init(id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1"),
        .init(id: "nvidia", name: "NVIDIA", baseURL: "https://integrate.api.nvidia.com/v1"),
        .init(id: "zhipu", name: "Zhipu AI", baseURL: "https://api.z.ai/api/paas/v4"),
        .init(id: "ollama", name: "Ollama", baseURL: "http://localhost:11434/v1"),
        .init(id: "custom", name: "自定义", baseURL: ""),
    ]

    var logoFile: String? { Self.logoFile(for: id) }
    static let localLogoFile = "provider-qwen"

    static func logoFile(for providerID: String) -> String? {
        if providerID == "custom" { return nil }
        guard all.contains(where: { $0.id == providerID }) else { return nil }
        return "provider-\(providerID)"
    }
}

@MainActor
@Observable
final class LLMConfiguration {
    private(set) var mode: LLMMode
    private(set) var profiles: [LLMAPIProfile]
    private(set) var activeID: UUID?
    private(set) var listedModels: [UUID: [String]] = [:]
    var activeProfile: LLMAPIProfile? { profiles.first { $0.id == activeID } }

    init() {
        let defaults = UserDefaults.standard
        mode = LLMMode(rawValue: defaults.string(forKey: "nomi.llm.mode") ?? "local") ?? .local
        profiles = defaults.data(forKey: "nomi.llm.profiles").flatMap { try? JSONDecoder().decode([LLMAPIProfile].self, from: $0) } ?? []
        activeID = defaults.string(forKey: "nomi.llm.active").flatMap(UUID.init(uuidString:))
    }

    func setMode(_ value: LLMMode) {
        mode = value
        UserDefaults.standard.set(value.rawValue, forKey: "nomi.llm.mode")
    }

    func selectModel(_ modelID: String) {
        let modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty, var profile = activeProfile,
              let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profile.modelID = modelID
        if !profile.savedModelIDs.contains(modelID) {
            profile.savedModelIDs.append(modelID)
        }
        profiles[index] = profile
        persist()
    }

    func setListedModels(_ models: [String], for id: UUID) {
        var next = listedModels
        next[id] = models
        listedModels = next
    }

    func activate(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeID = id
        UserDefaults.standard.set(id.uuidString, forKey: "nomi.llm.active")
    }

    func save(_ draft: LLMAPIProfile, key: String) throws {
        let value = try draft.validated()
        let existing = profiles.first { $0.id == value.id }
        let replacement = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isLoopback && replacement.isEmpty {
            let kept = existing?.baseURL == value.baseURL ? ((try? LLMKeychain.read(value)) ?? "") : ""
            guard !kept.isEmpty else { throw llmError(tr("请输入 API 密钥。")) }
        }
        if !replacement.isEmpty { try LLMKeychain.save(replacement, profile: value) }
        if let existing, existing.baseURL != value.baseURL { try LLMKeychain.delete(existing) }
        if let index = profiles.firstIndex(where: { $0.id == value.id }) { profiles[index] = value }
        else { profiles.append(value) }
        persist()
        if activeID == nil { activate(value.id) }
    }

    func delete(_ profile: LLMAPIProfile) throws {
        try LLMKeychain.delete(profile)
        profiles.removeAll { $0.id == profile.id }
        if activeID == profile.id {
            activeID = nil
            UserDefaults.standard.removeObject(forKey: "nomi.llm.active")
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: "nomi.llm.profiles") }
    }
}

enum LLMKeychain {
    private static let service = "local.nomi.llm-api"

    private enum Cache {
        nonisolated(unsafe) static var values: [String: String] = [:]
        static let lock = NSLock()

        static func get(_ account: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return values[account]
        }

        static func set(_ account: String, _ value: String) {
            lock.lock()
            values[account] = value
            lock.unlock()
        }

        static func remove(_ account: String) {
            lock.lock()
            values.removeValue(forKey: account)
            lock.unlock()
        }
    }

    private static func account(_ profile: LLMAPIProfile) -> String {
        "\(profile.id.uuidString)|\(profile.baseURL)"
    }

    static func read(_ profile: LLMAPIProfile) throws -> String {
        let id = account(profile)
        if let cached = Cache.get(id) { return cached }
        let key = try KeychainTrust.read(service: service, account: id)
        Cache.set(id, key)
        return key
    }

    static func save(_ key: String, profile: LLMAPIProfile) throws {
        try KeychainTrust.save(service: service, account: account(profile), secret: key)
        Cache.set(account(profile), key)
    }

    static func delete(_ profile: LLMAPIProfile) throws {
        try KeychainTrust.delete(service: service, account: account(profile))
        Cache.remove(account(profile))
    }
}

func llmError(_ message: String) -> NSError {
    NSError(domain: "Nomi.LLM", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
