import AppKit
import SwiftUI

/// Keeps the window above other apps' windows while a recording runs, so the live transcript
/// is never buried; clicks still go to whatever app is in front, and minimizing still works.
/// When the recording ends the window goes back to the normal level and can be covered again.
struct RecordingWindowLevel: NSViewRepresentable {
    var recording: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        let level: NSWindow.Level = recording ? .floating : .normal
        // The window is attached after the first update; apply once it exists.
        DispatchQueue.main.async {
            guard let window = view.window, window.level != level else { return }
            window.level = level
        }
    }
}
