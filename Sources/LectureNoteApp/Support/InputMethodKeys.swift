import AppKit

/// While an input method is composing (pinyin not yet turned into characters), Return confirms the
/// typed letters and Escape cancels them. SwiftUI sees those keys first for default buttons, cancel
/// buttons and `onSubmit`, so a sheet could save, an alert could close or a field could submit
/// half-typed text. This hands the two keys straight to the input method instead, in every window.
@MainActor
enum InputMethodKeys {
    private static var monitor: Any?
    private static let keys: Set<UInt16> = [36, 76, 53]  // Return, keypad Enter, Escape

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            route(event, in: event.window ?? NSApp.keyWindow)
        }
    }

    /// Returns nil when the key went to the input method, so nothing else acts on it.
    static func route(_ event: NSEvent, in window: NSWindow?) -> NSEvent? {
        guard keys.contains(event.keyCode),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let view = window?.firstResponder as? NSTextView,
              view.hasMarkedText()
        else { return event }
        view.keyDown(with: event)
        return nil
    }
}
