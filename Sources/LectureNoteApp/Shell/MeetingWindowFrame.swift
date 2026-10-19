import AppKit
import SwiftUI

/// Shrinks the meeting window into the compact card, then puts the previous frame back.
struct MeetingWindowFrame: NSViewRepresentable {
    var compact: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onWindow = { [weak coordinator = context.coordinator] window in
            coordinator?.sync(window: window)
        }
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        let coordinator = context.coordinator
        coordinator.desired = compact
        view.onWindow = { [weak coordinator] window in
            coordinator?.sync(window: window)
        }
        coordinator.sync(window: view.window)
    }

    @MainActor
    final class Coordinator {
        var desired = false
        private var applied: Bool?
        private var saved: NSRect?

        func sync(window: NSWindow?) {
            guard let window, applied != desired else { return }
            let compact = desired
            applied = compact
            if compact {
                let current = window.frame
                saved = current
                window.minSize = NSSize(width: 360, height: 560)
                var frame = current
                let size = NSSize(width: 420, height: 740)
                frame.origin.x += (frame.width - size.width) / 2
                frame.origin.y += frame.height - size.height
                frame.size = size
                window.setFrame(frame, display: true, animate: true)
            } else {
                window.minSize = NSSize(width: 960, height: 640)
                if let saved {
                    window.setFrame(saved, display: true, animate: true)
                    self.saved = nil
                }
            }
        }
    }
}

final class AnchorView: NSView {
    var onWindow: (@MainActor (NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let callback = onWindow
        let window = self.window
        MainActor.assumeIsolated {
            callback?(window)
        }
    }
}
