import SwiftUI

struct AppShell: View {
    @Bindable var model: AppModel
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
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
        .alert("导出失败", isPresented: exportFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.exportError ?? "")
        }
    }

    private var exportFailed: Binding<Bool> {
        Binding(
            get: { model.exportError != nil },
            set: { if !$0 { model.exportError = nil } }
        )
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
