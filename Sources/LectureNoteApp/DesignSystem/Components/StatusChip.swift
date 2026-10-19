import SwiftUI

struct StatusChip: View {
    var title: String
    var live: Bool
    var isError: Bool = false

    private var ink: Color { isError ? .red : AppColor.textSecondary }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isError ? Color.red : (live ? AppColor.accent : AppColor.textSecondary))
                .frame(width: 6, height: 6)
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppColor.surfaceInset, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
