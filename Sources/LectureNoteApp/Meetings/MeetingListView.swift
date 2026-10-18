import SwiftUI

struct MeetingListView: View {
    @Bindable var model: AppModel
    var namespace: Namespace.ID
    var reduceMotion: Bool
    @FocusState private var searchFocused: Bool
    @State private var importTitle = "上次导入"
    @State private var exportTitle = "导出会议记录"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                SearchField(text: $model.query, isFocused: $searchFocused)
                if model.filteredMeetings().isEmpty {
                    Text("没有匹配的会议")
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Space.s4)
                } else {
                    sections
                }
            }
            .padding(.horizontal, Space.s6)
            .padding(.top, 28)
            .padding(.bottom, Space.s7)
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: model.searchRequest) { _, _ in
            searchFocused = true
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text("会议")
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: Space.s3)
            PillButton(title: importTitle) { flashImport() }
                .help("导入会在下一步接上")
            PillButton(title: exportTitle) { flashExport() }
        }
    }

    @ViewBuilder
    private var sections: some View {
        let groups = grouped(model.filteredMeetings())
        if !groups.today.isEmpty {
            section(title: "今天", meetings: groups.today, showsNow: model.query.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        if !groups.earlier.isEmpty {
            section(title: "更早", meetings: groups.earlier, showsNow: false)
        }
    }

    private func section(title: String, meetings: [Meeting], showsNow: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title)
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.textPrimary)
            if showsNow {
                NowDivider()
            }
            VStack(spacing: Space.s3) {
                ForEach(meetings) { meeting in
                    MeetingCard(meeting: meeting, namespace: namespace, reduceMotion: reduceMotion) {
                        withAnimation(Motion.layout(reduceMotion)) {
                            model.openMeeting(meeting.id)
                        }
                    }
                }
            }
        }
    }

    private func grouped(_ meetings: [Meeting]) -> (today: [Meeting], earlier: [Meeting]) {
        let calendar = Calendar.current
        let today = meetings
            .filter { calendar.isDateInToday($0.startedAt) }
            .sorted(by: sortToday)
        let earlier = meetings
            .filter { !calendar.isDateInToday($0.startedAt) }
            .sorted { $0.startedAt > $1.startedAt }
        return (today, earlier)
    }

    private func sortToday(_ lhs: Meeting, _ rhs: Meeting) -> Bool {
        if lhs.isLive != rhs.isLive { return lhs.isLive && !rhs.isLive }
        return lhs.startedAt > rhs.startedAt
    }

    private func flashImport() {
        importTitle = "尚未接上"
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            importTitle = "上次导入"
        }
    }

    private func flashExport() {
        guard model.copyNotes() else { return }
        exportTitle = "已复制"
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            exportTitle = "导出会议记录"
        }
    }
}
