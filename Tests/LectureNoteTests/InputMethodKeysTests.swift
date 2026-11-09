import AppKit
import Testing
@testable import LectureNoteApp

@MainActor
struct InputMethodKeysTests {
    private func window(composing: Bool) -> (NSWindow, NSTextView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let view = NSTextView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(view)
        window.makeFirstResponder(view)
        if composing { view.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        return (window, view)
    }

    private func key(_ code: UInt16, _ characters: String, flags: NSEvent.ModifierFlags = [], window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    @Test func returnAndEscapeGoOnlyToAComposingInputMethod() {
        let (window, _) = window(composing: true)
        #expect(InputMethodKeys.route(key(36, "\r", window: window), in: window) == nil)
        let (other, _) = self.window(composing: true)
        #expect(InputMethodKeys.route(key(53, "\u{1b}", window: other), in: other) == nil)
    }

    @Test func withoutCompositionTheKeysWorkAsUsual() {
        let (window, _) = window(composing: false)
        let event = key(36, "\r", window: window)
        #expect(InputMethodKeys.route(event, in: window) === event)
    }

    @Test func otherKeysAndCommandReturnAreLeftAlone() {
        let (window, _) = window(composing: true)
        let letter = key(0, "a", window: window)
        #expect(InputMethodKeys.route(letter, in: window) === letter)
        let send = key(36, "\r", flags: .command, window: window)
        #expect(InputMethodKeys.route(send, in: window) === send)
    }
}
