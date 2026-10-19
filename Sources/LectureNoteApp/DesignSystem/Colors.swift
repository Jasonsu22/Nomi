import AppKit
import SwiftUI

enum AppColor {
    static let canvas = Color(light: 0xE9EDF6, dark: 0x0F1216)
    static let surface = Color(light: 0xFFFFFF, dark: 0x181C21)
    static let surfaceInset = Color(light: 0xEBF0F6, dark: 0x1F242B)
    static let selection = Color(light: 0xC2E8FF, dark: 0x1D3A50)
    static let onSelection = Color(light: 0x17587E, dark: 0xCDEBFF)
    static let accent = Color(light: 0x004A77, dark: 0x7CC4F2)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0F1216)
    static let accentSoft = Color(light: 0xE3F3FF, dark: 0x1A2C3A)
    static let textPrimary = Color(light: 0x111418, dark: 0xE6E8EB)
    static let nsTextPrimary = NSColor.nomi(light: 0x111418, dark: 0xE6E8EB)
    static let textSecondary = Color(
        light: 0x5E6670,
        dark: 0x9AA3AD,
        lightIncreased: 0x3E4650,
        darkIncreased: 0xC5CED6
    )
    static let nsTextSecondary = NSColor.nomi(
        light: 0x5E6670,
        dark: 0x9AA3AD,
        lightIncreased: 0x3E4650,
        darkIncreased: 0xC5CED6
    )
    static let outline = Color(light: 0xB0B4BD, dark: 0x3A414A)
    static let separator = Color(light: 0xD5DCE6, dark: 0x2A3038)
}

extension Color {
    init(light: UInt32, dark: UInt32, lightIncreased: UInt32? = nil, darkIncreased: UInt32? = nil) {
        self.init(nsColor: .nomi(light: light, dark: dark, lightIncreased: lightIncreased, darkIncreased: darkIncreased))
    }
}

extension NSColor {
    static func nomi(light: UInt32, dark: UInt32, lightIncreased: UInt32? = nil, darkIncreased: UInt32? = nil) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .accessibilityHighContrastDarkAqua,
                .accessibilityHighContrastAqua,
                .darkAqua,
                .aqua,
            ])
            switch match {
            case .accessibilityHighContrastDarkAqua:
                return NSColor(hex: darkIncreased ?? dark)
            case .accessibilityHighContrastAqua:
                return NSColor(hex: lightIncreased ?? light)
            case .darkAqua:
                return NSColor(hex: dark)
            default:
                return NSColor(hex: light)
            }
        }
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
