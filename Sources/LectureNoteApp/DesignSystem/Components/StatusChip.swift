import SwiftUI

struct StatusChip: View {
    var title: String
    var live: Bool
    var isError: Bool = false

    static let marker: CGFloat = 6
    static let markerGap: CGFloat = 4
    /// Distance from the chip's leading edge to the first glyph, so the words
    /// can sit on the same x as the page title.
    static var textLead: CGFloat { marker + markerGap }

    private var ink: Color { isError ? .red : AppColor.textSecondary }

    var body: some View {
        HStack(spacing: Self.markerGap) {
            Circle()
                .fill(isError ? Color.red : (live ? AppColor.accent : AppColor.textSecondary))
                .frame(width: Self.marker, height: Self.marker)
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(ink)
        }
        .padding(.vertical, 5)
        .padding(.trailing, 8)
        .background(AppColor.surfaceInset, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
