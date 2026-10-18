import AppKit
import SwiftUI

enum AppColor {
    static let canvas = Color(light: 0xEEF2F8, dark: 0x0F1216)
    static let surface = Color(light: 0xFFFFFF, dark: 0x181C21)
    static let surfaceMuted = Color(light: 0xE3EAF4, dark: 0x222830)
    static let accent = Color(light: 0x0B5C8A, dark: 0x6CB4E8)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0F1216)
    static let accentSoft = Color(light: 0xD6E8F7, dark: 0x1E3446)
    static let textPrimary = Color(light: 0x1A1C1E, dark: 0xE6E8EB)
    static let textSecondary = Color(light: 0x5E6670, dark: 0x9AA3AD)
    static let separator = Color(light: 0xD5DCE6, dark: 0x2A3038)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        let dynamic = NSColor(name: nil) { appearance in
            let darkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: darkMode ? dark : light)
        }
        self.init(nsColor: dynamic)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
