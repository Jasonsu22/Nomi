import SwiftUI

/// Keeps a chat pinned to its end while new text arrives, unless the student has scrolled up to
/// read: then it stays put, and notes that something new is waiting below.
struct ChatFollow: Equatable {
    struct Geometry: Equatable {
        /// The bottom of what is visible, in content coordinates.
        var visibleBottom: CGFloat
        var contentHeight: CGFloat

        var distanceFromEnd: CGFloat { contentHeight - visibleBottom }
    }

    /// Within this distance of the end still counts as at the end.
    static let slack: CGFloat = 48

    /// At the end, so new text should pull the view along.
    var following = true
    /// New text arrived below while the student was reading further up.
    var unseen = false

    /// Records a change of the scroll view; true means scroll to the end now.
    mutating func update(from old: Geometry, to new: Geometry) -> Bool {
        if new.contentHeight > old.contentHeight + 0.5 {
            // The chat grew: an answer streaming in, a new question, a picture loading.
            if following { return true }
            unseen = true
            return false
        }
        // The student scrolled, the window was resized, or the chat got shorter.
        following = new.distanceFromEnd <= Self.slack
        if following { unseen = false }
        return false
    }

    /// The student sent something or asked to jump: follow the end again.
    mutating func jumpToEnd() {
        following = true
        unseen = false
    }

    var showsJumpButton: Bool { !following }
}

/// The round button that jumps a chat to its newest message. It turns green, with a label, when a
/// new answer has arrived below.
struct JumpToEndButton: View {
    var unseen: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                if unseen {
                    Text(tr("新回答"))
                        .font(AppFont.caption.weight(.semibold))
                }
            }
            .foregroundStyle(unseen ? Color.white : AppColor.textPrimary)
            .frame(minWidth: 32, minHeight: 32)
            .padding(.horizontal, unseen ? 12 : 0)
            .background(unseen ? AnyShapeStyle(AppColor.accent) : AnyShapeStyle(AppColor.surface), in: Capsule())
            .overlay { Capsule().strokeBorder(unseen ? Color.clear : AppColor.separator, lineWidth: 1) }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain.clicking())
        .help(tr("跳到最新"))
        .accessibilityLabel(unseen ? tr("跳到新回答") : tr("跳到最新"))
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
