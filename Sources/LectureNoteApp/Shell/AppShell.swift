import SwiftUI

struct AppShell: View {
    @Bindable var model: AppModel
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
            TopBar(model: model, reduceMotion: reduce)
            HStack(spacing: 0) {
                Rail(model: model, reduceMotion: reduce)
                page
                    .id(model.page)
                    .transition(.pageEnter(reduceMotion: reduce))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .background(AppColor.canvas.ignoresSafeArea())
        .containerBackground(AppColor.canvas, for: .window)
    }

    private var reduce: Bool { reduceMotion }

    @ViewBuilder
    private var page: some View {
        switch model.page {
        case .meetings:
            MeetingsPage(model: model, reduceMotion: reduce)
        case .ask:
            AskView()
        case .sources:
            SourcesView(model: model)
        case .help:
            HelpView()
        case .settings:
            SettingsView()
        }
    }
}
