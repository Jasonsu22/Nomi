import SwiftUI

struct ParagraphRow: View {
    var paragraph: Paragraph

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(formatClock(paragraph.openedAt))
                .font(AppFont.caption)
                .monospacedDigit()
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                spoken
                    .font(AppFont.body)
                    .lineSpacing(5)
                    .contentTransition(.interpolate)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !paragraph.translation.isEmpty {
                    Text(paragraph.translation)
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineSpacing(4)
                        .contentTransition(.interpolate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 10)
        .background {
            if paragraph.isLive {
                RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
                    .fill(AppColor.accentSoft)
            }
        }
    }

    private var spoken: Text {
        var committed = AttributedString(paragraph.source)
        committed.foregroundColor = AppColor.textPrimary
        if !paragraph.tail.isEmpty {
            var pending = AttributedString(paragraph.tail)
            pending.foregroundColor = AppColor.textSecondary
            committed.append(pending)
        }
        return Text(committed)
    }
}
