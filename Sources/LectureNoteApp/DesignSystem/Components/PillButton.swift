import SwiftUI

struct PillButton: View {
    var title: String
    var tint: Color = AppColor.textPrimary
    var action: () -> Void
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.secondary.weight(.medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(hovering ? AppColor.surfaceInset : AppColor.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .onHover { hovering = $0 }
        .animation(Motion.fade(reduceMotion), value: hovering)
    }
}

struct PillMenu<Content: View>: View {
    var title: String
    var enabled: Bool = true
    @ViewBuilder var content: () -> Content
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Menu(content: content) {
            Text(title)
                .font(AppFont.secondary.weight(.medium))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(hovering && enabled ? AppColor.surfaceInset : AppColor.surface, in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .animation(Motion.fade(reduceMotion), value: hovering)
    }
}

/// Swaps the trailing toolbar without resizing each button into the next one.
/// The list keeps its own checkbox animation; this only fades the button bar.
struct TrailingBarSwap<Idle: View, Manage: View>: View {
    var managing: Bool
    var reduceMotion: Bool
    @ViewBuilder var idle: () -> Idle
    @ViewBuilder var manage: () -> Manage

    var body: some View {
        ZStack(alignment: .trailing) {
            if managing {
                manage().transition(transition)
            } else {
                idle().transition(transition)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .animation(Motion.layout(reduceMotion), value: managing)
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 12)),
            removal: .opacity
        )
    }
}
