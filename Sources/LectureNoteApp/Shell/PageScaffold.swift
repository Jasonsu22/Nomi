import SwiftUI

struct PageScaffold<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, Space.s6)
                .padding(.top, 28)
                .padding(.bottom, Space.s5)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
