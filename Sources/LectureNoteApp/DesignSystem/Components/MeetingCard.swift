import SwiftUI

struct MeetingCard: View {
    var meeting: Meeting
    var symbol: String
    var colorIndex: Int
    var reduceMotion: Bool
    /// `nil` outside manage mode. Live meetings stay `nil` and cannot be selected.
    var selected: Bool? = nil
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Space.s3) {
                if let selected {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(selected ? AppColor.accent : AppColor.textSecondary)
                        .frame(width: 22)
                }
                CategoryIcon(symbol: symbol, colorIndex: colorIndex, size: 32)
                VStack(alignment: .leading, spacing: 6) {
                    Text(meeting.title)
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s3)
                if meeting.isLive {
                    HStack(spacing: 6) {
                        LiveDot(reduceMotion: reduceMotion)
                        Text(tr("进行中"))
                    }
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.accent)
                } else {
                    Text(formatDuration(meeting.duration))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                hovering ? AppColor.surfaceInset : AppColor.surface,
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.fade(reduceMotion), value: hovering)
    }

    private var subtitle: String {
        let length = meeting.isLive ? tr("进行中") : formatDuration(meeting.duration)
        return "\(formatStartStamp(meeting.startedAt)) · \(length)"
    }
}

private struct LiveDot: View {
    var reduceMotion: Bool
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(AppColor.accent)
            .frame(width: 7, height: 7)
            .opacity(dimmed ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
            .accessibilityLabel(tr("进行中"))
    }
}
