import AppKit
import SwiftUI

enum Motion {
    static let reduced = Animation.easeInOut(duration: 0.2)

    static func tap(_ reduce: Bool) -> Animation {
        reduce ? reduced : .snappy(duration: 0.18)
    }

    static func page(_ reduce: Bool) -> Animation {
        reduce ? reduced : .smooth(duration: 0.22)
    }

    static func layout(_ reduce: Bool) -> Animation {
        reduce ? reduced : .smooth(duration: 0.32)
    }

    static func morph(_ reduce: Bool) -> Animation {
        reduce ? reduced : .bouncy(duration: 0.42, extraBounce: 0)
    }

    static func fade(_ reduce: Bool) -> Animation {
        reduce ? reduced : .easeOut(duration: 0.16)
    }
}

enum ReduceMotion {
    static var system: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LECTURE_REDUCE_MOTION"] == "1" {
            return true
        }
        #endif
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

func insertionTransition(reduceMotion: Bool) -> AnyTransition {
    reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
}

extension AnyTransition {
    static func pageEnter(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity.animation(Motion.fade(true))
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)).animation(Motion.page(false)),
            removal: .opacity.animation(.easeOut(duration: 0.1))
        )
    }
}

private struct AppReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var appReduceMotion: Bool {
        get { self[AppReduceMotionKey.self] }
        set { self[AppReduceMotionKey.self] = newValue }
    }
}

struct ReduceMotionBridge: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    private var reduce: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LECTURE_REDUCE_MOTION"] == "1" {
            return true
        }
        #endif
        return systemReduce
    }

    func body(content: Content) -> some View {
        content.environment(\.appReduceMotion, reduce)
    }
}
