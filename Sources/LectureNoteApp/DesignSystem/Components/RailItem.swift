import SwiftUI

struct RailItem: View {
    var page: AppPage
    var selected: Bool
    var namespace: Namespace.ID
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: page.symbol)
                    .font(.system(size: 18, weight: selected ? .semibold : .regular))
                Text(page.title)
                    .font(AppFont.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? AppColor.onSelection : AppColor.textSecondary)
            .frame(width: 60, height: 54)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                        .fill(AppColor.selection)
                        .matchedGeometryEffect(id: "rail", in: namespace)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
