import SwiftUI

struct StatusChip: View {
    var title: String
    var live: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(live ? AppColor.accent : AppColor.textSecondary)
                .frame(width: 6, height: 6)
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppColor.surfaceInset, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
