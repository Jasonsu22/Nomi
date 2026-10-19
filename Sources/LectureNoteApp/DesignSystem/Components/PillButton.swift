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
