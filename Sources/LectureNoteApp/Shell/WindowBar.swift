import AppKit
import SwiftUI

extension View {
    /// For the areas that stand in for the hidden title bar: dragging moves the window, and a
    /// double-click does what a title bar does (fill the screen and back, by default).
    func windowBarGestures() -> some View {
        gesture(WindowDragGesture())
            .simultaneousGesture(TapGesture(count: 2).onEnded { TitleBarDoubleClick.perform() })
    }
}

/// The action chosen in System Settings › Desktop & Dock for double-clicking a title bar.
@MainActor
enum TitleBarDoubleClick {
    enum Action: Equatable { case zoom, minimize, nothing }

    /// `setting` is AppleActionOnDoubleClick; `minimizes` is the older AppleMiniaturizeOnDoubleClick.
    static func action(setting: String?, minimizes: Bool) -> Action {
        switch setting {
        case "Minimize": return .minimize
        case "None": return .nothing
        case nil: return minimizes ? .minimize : .zoom
        default: return .zoom  // "Maximize", "Fill" and anything newer
        }
    }

    static func perform(_ window: NSWindow? = NSApp.keyWindow) {
        let defaults = UserDefaults.standard
        switch action(setting: defaults.string(forKey: "AppleActionOnDoubleClick"), minimizes: defaults.bool(forKey: "AppleMiniaturizeOnDoubleClick")) {
        case .zoom: window?.performZoom(nil)
        case .minimize: window?.performMiniaturize(nil)
        case .nothing: break
        }
    }
}
