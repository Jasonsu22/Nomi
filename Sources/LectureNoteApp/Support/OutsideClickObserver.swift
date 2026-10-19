import AppKit
import SwiftUI

/// Set when an outside click already closed history, so the history button does not immediately reopen it.
final class HistoryClickGate {
    var suppressButton = false
}

/// A view that counts as “inside” for an outside-click observer, such as the button that opened the panel.
final class ClickShield: @unchecked Sendable {
    weak var view: NSView?
}

struct ClickShieldAnchor: NSViewRepresentable {
    var shield: ClickShield

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        shield.view = view
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 36, height: proposal.height ?? 36)
    }

    func updateNSView(_ view: NSView, context: Context) {
        shield.view = view
    }
}

struct OutsideClickObserver: NSViewRepresentable {
    var isActive: Bool
    var shield: ClickShield? = nil
    var onOutsideClick: () -> Void

    func makeNSView(context: Context) -> ObserverView {
        ObserverView()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ObserverView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onOutsideClick = onOutsideClick
        view.shield = shield
        view.setActive(isActive)
    }

    static func dismantleNSView(_ view: ObserverView, coordinator: ()) {
        view.setActive(false)
    }

    final class ObserverView: NSView {
        var onOutsideClick: (() -> Void)?
        var shield: ClickShield?
        private var monitor: Any?
        private var upMonitor: Any?
        private var armed = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func setActive(_ active: Bool) {
            guard active != (monitor != nil) else { return }
            if !active {
                removeMonitors()
                return
            }
            if shield != nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    MainActor.assumeIsolated { self?.arm(event) }
                    return event
                }
                upMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
                    MainActor.assumeIsolated { self?.finish(event) }
                    return event
                }
            } else {
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

        private func arm(_ event: NSEvent) {
            guard let window, event.window === window else { return }
            armed = !bounds.contains(convert(event.locationInWindow, from: nil))
        }

        private func finish(_ event: NSEvent) {
            guard armed else { return }
            armed = false
            guard let window, event.window === window else { return }
            if bounds.contains(convert(event.locationInWindow, from: nil)) { return }
            if let shield = shield?.view, shield.window === window,
               shield.bounds.contains(shield.convert(event.locationInWindow, from: nil)) {
                return
            }
            window.makeFirstResponder(nil)
            onOutsideClick?()
        }

        private func removeMonitors() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let upMonitor { NSEvent.removeMonitor(upMonitor) }
            monitor = nil
            upMonitor = nil
            armed = false
        }
    }
}
