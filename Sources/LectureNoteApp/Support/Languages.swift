import Foundation

enum LectureLanguages {
    static let followSystem = "system"
    static let sourceKey = "nomi.sourceLanguage"
    static let targetKey = "nomi.targetLanguage"
    static let supported = ["zh", "en", "ja", "ko", "de", "fr", "es", "ru", "ar"]

    static func systemCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        code(forPreferred: preferredLanguages.first ?? "en")
    }

    static func code(forPreferred identifier: String) -> String {
        let normalized = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
        if normalized.hasPrefix("zh") { return "zh" }
        if normalized.hasPrefix("en") { return "en" }
        if normalized.hasPrefix("ja") { return "ja" }
        if normalized.hasPrefix("ko") { return "ko" }
        if normalized.hasPrefix("de") { return "de" }
        if normalized.hasPrefix("fr") { return "fr" }
        if normalized.hasPrefix("es") { return "es" }
        if normalized.hasPrefix("ru") { return "ru" }
        if normalized.hasPrefix("ar") { return "ar" }
        return "en"
    }

    static func defaultTarget(for source: String) -> String {
        switch source {
        case "zh": "en"
        case "en": "zh"
        default: "en"
        }
    }

    static func resolve(preferred: String, storedSource: String?, storedTarget: String?) -> (source: String, target: String) {
        let source: String
        if let storedSource, storedSource != followSystem, supported.contains(storedSource) {
            source = storedSource
        } else {
            source = code(forPreferred: preferred)
        }
        let target: String
        if let storedTarget, storedTarget == "none" || supported.contains(storedTarget) {
            target = storedTarget
        } else {
            target = defaultTarget(for: source)
        }
        return (source, target)
    }

    static func currentPair() -> (source: String, target: String) {
        resolve(
            preferred: Locale.preferredLanguages.first ?? "en",
            storedSource: UserDefaults.standard.string(forKey: sourceKey),
            storedTarget: UserDefaults.standard.string(forKey: targetKey)
        )
    }
}
