import Foundation
import Observation

struct PromptSkill: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var body: String
    var enabled: Bool

    init(id: UUID = UUID(), name: String = "", body: String = "", enabled: Bool = true) {
        self.id = id
        self.name = name
        self.body = body
        self.enabled = enabled
    }
}

@MainActor
@Observable
final class PromptPreferences {
    static let followInterface = "interface"
    private static let systemKey = "nomi.prompt.system"
    private static let languageKey = "nomi.prompt.replyLanguage"
    private static let skillsKey = "nomi.prompt.skills"

    private(set) var systemOverride: String?
    private(set) var replyLanguage: String
    private(set) var skills: [PromptSkill]

    init() {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: Self.systemKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        systemOverride = (stored?.isEmpty == false && stored != ChatContext.defaultSystemText) ? stored : nil
        let language = defaults.string(forKey: Self.languageKey) ?? Self.followInterface
        replyLanguage = language == Self.followInterface || LectureLanguages.supported.contains(language)
            ? language
            : Self.followInterface
        skills = defaults.data(forKey: Self.skillsKey).flatMap { try? JSONDecoder().decode([PromptSkill].self, from: $0) } ?? []
    }

    var systemText: String { systemOverride ?? ChatContext.defaultSystemText }
    var isSystemCustomized: Bool { systemOverride != nil }

    var replyLanguageTitle: String {
        replyLanguage == Self.followInterface ? tr("跟随界面") : languageName(replyLanguage)
    }

    var modelLanguageName: String {
        let code = replyLanguage == Self.followInterface
            ? (InterfaceLanguage.current == .chinese ? "zh" : "en")
            : replyLanguage
        switch code {
        case "zh": return "Simplified Chinese"
        case "en": return "English"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "de": return "German"
        case "fr": return "French"
        case "es": return "Spanish"
        case "ru": return "Russian"
        case "ar": return "Arabic"
        default: return "English"
        }
    }

    func saveSystem(_ text: String) {
        let trimmed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == ChatContext.defaultSystemText {
            systemOverride = nil
            UserDefaults.standard.removeObject(forKey: Self.systemKey)
        } else {
            systemOverride = trimmed
            UserDefaults.standard.set(trimmed, forKey: Self.systemKey)
        }
    }

    func setReplyLanguage(_ code: String) {
        let next = code == Self.followInterface || LectureLanguages.supported.contains(code) ? code : Self.followInterface
        replyLanguage = next
        UserDefaults.standard.set(next, forKey: Self.languageKey)
    }

    func upsert(_ skill: PromptSkill) {
        var next = skills
        if let index = next.firstIndex(where: { $0.id == skill.id }) {
            next[index] = skill
        } else {
            next.append(skill)
        }
        skills = next
        persistSkills()
    }

    func setEnabled(_ enabled: Bool, id: UUID) {
        guard let index = skills.firstIndex(where: { $0.id == id }) else { return }
        var next = skills
        next[index].enabled = enabled
        skills = next
        persistSkills()
    }

    func delete(_ id: UUID) {
        skills.removeAll { $0.id == id }
        persistSkills()
    }

    private func persistSkills() {
        guard let data = try? JSONEncoder().encode(skills) else { return }
        UserDefaults.standard.set(data, forKey: Self.skillsKey)
    }
}
