import SwiftUI

struct NowDivider: View {
    var body: some View {
        HStack(spacing: Space.s3) {
            line
            TimelineView(.everyMinute) { context in
                Text("现在 · \(context.date.formatted(date: .omitted, time: .shortened))")
                    .font(AppFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppColor.accent)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppColor.accentSoft, in: Capsule())
            }
            line
        }
        .accessibilityElement(children: .combine)
    }

    private var line: some View {
        Rectangle()
            .fill(AppColor.separator)
            .frame(height: 1)
    }
}
