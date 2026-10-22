import SwiftUI

enum PageColumnLayout {
    static let maxWidth: CGFloat = 1200
    /// Settings and Help: a centered column of rows, like System Settings.
    static let narrowWidth: CGFloat = 760
    static let leading: CGFloat = 48
    static let trailing: CGFloat = 32

    static func leadingInset(in availableWidth: CGFloat) -> CGFloat {
        leading + max(0, (availableWidth - maxWidth - leading - trailing) / 2)
    }
}

struct PageScaffold<Content: View>: View {
    var title: String
    /// The title sits on the same centered column as the page's content.
    var columnWidth: CGFloat = PageColumnLayout.maxWidth
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.textPrimary)
                .pageColumn(maxWidth: columnWidth)
                .padding(.top, 28)
                .padding(.bottom, Space.s5)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension View {
    func pageColumn(maxWidth: CGFloat = PageColumnLayout.maxWidth) -> some View {
        frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.leading, PageColumnLayout.leading)
            .padding(.trailing, PageColumnLayout.trailing)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
