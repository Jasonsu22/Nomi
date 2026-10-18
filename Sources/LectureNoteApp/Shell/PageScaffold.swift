import SwiftUI

struct PageScaffold<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.textPrimary)
                .pageColumn()
                .padding(.top, 28)
                .padding(.bottom, Space.s5)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension View {
    func pageColumn(maxWidth: CGFloat = 1200) -> some View {
        frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.leading, 48)
            .padding(.trailing, 32)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
