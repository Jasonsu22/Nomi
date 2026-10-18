import SwiftUI

struct JumpToLatestPill: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                Text(tr("回到最新"))
            }
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("回到最新"))
    }
}
