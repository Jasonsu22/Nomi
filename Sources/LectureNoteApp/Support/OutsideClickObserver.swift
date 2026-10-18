import AppKit
import SwiftUI

struct OutsideClickObserver: NSViewRepresentable {
    var isActive: Bool
    var onOutsideClick: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        ObserverView()
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onOutsideClick = onOutsideClick
        view.setActive(isActive)
    }

    static func dismantleNSView(_ view: ObserverView, coordinator: ()) {
        view.setActive(false)
    }

    final class ObserverView: NSView {
        var onOutsideClick: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func setActive(_ active: Bool) {
            if !active, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            } else if active, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    MainActor.assumeIsolated {
                        guard let self, let window = self.window else { return }
                        let inside = event.window === window
                            && self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                        if !inside {
                            window.makeFirstResponder(nil)
                            self.onOutsideClick?()
                        }
                    }
                    return event
                }
            }
        }
    }
}
