import SwiftUI

struct Rail: View {
    @Binding var selection: AppPage
    var reduceMotion: Bool
    @Namespace private var namespace

    private let primary: [AppPage] = [.meetings, .ask, .sources, .stats]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(primary) { page in
                item(page)
            }
            Spacer(minLength: 0)
            item(.help)
            item(.settings)
        }
        .padding(.top, Space.s2)
        .padding(.bottom, Space.s4)
        .frame(maxHeight: .infinity)
        .frame(width: 72)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppColor.separator)
                .frame(width: 1)
        }
    }

    private func item(_ page: AppPage) -> some View {
        RailItem(page: page, selected: selection == page, namespace: namespace) {
            withAnimation(Motion.tap(reduceMotion)) {
                selection = page
            }
        }
    }
}
