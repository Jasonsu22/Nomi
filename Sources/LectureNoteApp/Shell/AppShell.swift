import SwiftUI

struct AppShell: View {
    @Bindable var model: AppModel
    @Environment(\.appReduceMotion) private var reduceMotion
    @Namespace private var meetingsNamespace

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                Rail(selection: $model.page, reduceMotion: reduce)
            }
            .frame(width: 72)

            VStack(spacing: 0) {
                TopBar(model: model, reduceMotion: reduce)
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            meetings
        case .ask:
            AskView()
        case .sources:
            SourcesView(meetings: model.meetings)
        case .stats:
            StatsView(meetings: model.meetings)
        case .help:
            HelpView()
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var meetings: some View {
        if let meetingID = model.openMeetingID {
            MeetingDetailView(
                model: model,
                meetingID: meetingID,
                namespace: meetingsNamespace,
                reduceMotion: reduce
            )
            .transition(reduce ? .opacity : .identity)
        } else {
            MeetingListView(model: model, namespace: meetingsNamespace, reduceMotion: reduce)
                .transition(reduce ? .opacity : .identity)
        }
    }
}
