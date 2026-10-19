import Foundation
import SwiftUI

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system, chinese = "zh-Hans", english = "en"

    static let key = "nomi.interfaceLanguage"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: tr("跟随系统")
        case .chinese: "简体中文"
        case .english: "English"
        }
    }

    static func resolved(_ choice: String, preferredLanguages: [String] = Locale.preferredLanguages) -> InterfaceLanguage {
        if choice == chinese.rawValue { return .chinese }
        if choice == english.rawValue { return .english }
        return preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .chinese : .english
    }

    static var current: InterfaceLanguage {
        resolved(UserDefaults.standard.string(forKey: key) ?? "system")
    }

    var locale: Locale { Locale(identifier: self == .chinese ? "zh-Hans" : "en") }
}

enum MicrophonePrompt: String, CaseIterable, Identifiable {
    case ask
    case allow

    static let key = "nomi.microphonePrompt"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ask: tr("开始时询问")
        case .allow: tr("全部允许")
        }
    }
}

enum InterfaceAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "nomi.appearance"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: tr("跟随系统")
        case .light: tr("白色")
        case .dark: tr("黑色")
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private let englishInterfaceBundle: Bundle? = {
    guard let path = Bundle.module.path(forResource: "en", ofType: "lproj") else { return nil }
    return Bundle(path: path)
}()

func tr(_ key: String) -> String {
    guard InterfaceLanguage.current == .english else { return key }
    return englishInterfaceBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
}

func trf(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: tr(key), locale: InterfaceLanguage.current.locale, arguments: arguments)
}
