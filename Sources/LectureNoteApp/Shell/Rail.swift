import SwiftUI

struct Rail: View {
    var model: AppModel
    var reduceMotion: Bool
    @Namespace private var namespace

    private let primary: [AppPage] = [.meetings, .ask, .sources]

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
    }

    private func item(_ page: AppPage) -> some View {
        RailItem(page: page, selected: model.page == page, namespace: namespace) {
            let backToList = page == .meetings && model.page == .meetings && model.openMeetingID != nil
            withAnimation(backToList ? Motion.layout(reduceMotion) : Motion.tap(reduceMotion)) {
                model.select(page)
            }
        }
    }
}
