import AppKit
import SwiftUI

/// Shrinks the meeting window into the compact card, then puts the previous frame back.
struct MeetingWindowFrame: NSViewRepresentable {
    var compact: Bool
    var reduceMotion: Bool
    @Binding var allowsCompactFrame: Bool

    static let duration: TimeInterval = 0.32
    static let reducedDuration: TimeInterval = 0.2

    static func animation(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? reducedDuration : duration)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.coordinator = context.coordinator
        view.onWindow = { [weak coordinator = context.coordinator] window in
            coordinator?.sync(window: window)
        }
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        let coordinator = context.coordinator
        coordinator.desired = compact
        coordinator.reduceMotion = reduceMotion
        coordinator.allowsCompactFrame = $allowsCompactFrame
        view.coordinator = coordinator
        view.onWindow = { [weak coordinator] window in
            coordinator?.sync(window: window)
        }
        coordinator.sync(window: view.window)
    }

    @MainActor
    final class Coordinator {
        var desired = false
        var reduceMotion = false
        var allowsCompactFrame: Binding<Bool> = .constant(false)
        private var applied: Bool?
        private var saved: NSRect?
        private var generation = 0
        private var pendingFinish: (@MainActor () -> Void)?
        fileprivate var animating = false

        private static let compactSize = NSSize(width: 420, height: 740)
        private static let compactMinimum = NSSize(width: 360, height: 560)
        fileprivate static let regularMinimum = NSSize(width: 960, height: 640)

        func sync(window: NSWindow?) {
            guard let window, applied != desired else { return }
            let compact = desired
            applied = compact
            generation += 1
            let token = generation
            let duration = reduceMotion ? MeetingWindowFrame.reducedDuration : MeetingWindowFrame.duration
            if compact {
                let current = window.frame
                saved = current
                if duration > 0 { animating = true }
                window.minSize = Self.compactMinimum
                var frame = current
                let size = Self.compactSize
                frame.origin.x += (frame.width - size.width) / 2
                frame.origin.y += frame.height - size.height
                frame.size = size
                resize(window, to: frame, duration: duration, token: token, then: nil)
            } else if let saved {
                let target = saved
                self.saved = nil
                if duration > 0 { animating = true }
                window.minSize = Self.compactMinimum
                resize(window, to: target, duration: duration, token: token) { [weak window] in
                    window?.minSize = Self.regularMinimum
                    self.allowsCompactFrame.wrappedValue = false
                }
            } else {
                animating = false
                window.minSize = Self.regularMinimum
            }
        }

        fileprivate func enforceMinimum(window: NSWindow?) {
            guard let window, applied != true, !animating else { return }
            if window.minSize != Self.regularMinimum {
                window.minSize = Self.regularMinimum
            }
        }

        private func resize(
            _ window: NSWindow,
            to frame: NSRect,
            duration: TimeInterval,
            token: Int,
            then completion: (@MainActor () -> Void)?
        ) {
            if duration <= 0 {
                window.setFrame(frame, display: true, animate: false)
                animating = false
                completion?()
                return
            }
            animating = true
            pendingFinish = completion
            let end = End(coordinator: self, token: token)
            Task { @MainActor [weak window] in
                guard let window, end.coordinator?.generation == token else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    context.allowsImplicitAnimation = true
                    window.animator().setFrame(frame, display: true)
                } completionHandler: {
                    MainActor.assumeIsolated {
                        guard let coordinator = end.coordinator, coordinator.generation == end.token else { return }
                        coordinator.animating = false
                        let finish = coordinator.pendingFinish
                        coordinator.pendingFinish = nil
                        finish?()
                    }
                }
            }
        }
    }

    /// Lets the animation completion hop back to the coordinator without capturing it directly.
    private struct End: @unchecked Sendable {
        weak var coordinator: Coordinator?
        let token: Int
    }
}

final class AnchorView: NSView {
    var coordinator: MeetingWindowFrame.Coordinator?
    var onWindow: (@MainActor (NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let callback = onWindow
        let window = self.window
        MainActor.assumeIsolated {
            callback?(window)
        }
    }

    override func layout() {
        super.layout()
        let coordinator = coordinator
        let window = self.window
        MainActor.assumeIsolated {
            coordinator?.enforceMinimum(window: window)
        }
    }
}
