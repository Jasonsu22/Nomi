import SwiftUI

struct AskView: View {
    var model: AppModel
    @State private var selectedID: UUID?

    private var selectedMeeting: Meeting? {
        model.meetings.first { $0.id == selectedID } ?? model.meetings.first
    }

    var body: some View {
        PageScaffold(title: tr("提问")) {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let meeting = selectedMeeting {
                    Picker(tr("选择会议"), selection: Binding(get: { selectedMeeting?.id }, set: { selectedID = $0 })) {
                        ForEach(model.meetings) { Text($0.title).tag(Optional($0.id)) }
                    }
                    .font(AppFont.body)
                    MeetingAssistantPanel(model: model, meeting: meeting)
                        .id(meeting.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                } else {
                    Text(tr("先录制一场会议，再根据转写提问。"))
                        .font(AppFont.secondary).foregroundStyle(AppColor.textSecondary)
                }
            }
            .pageColumn(maxWidth: 900)
            .padding(.bottom, Space.s5)
            .frame(maxHeight: .infinity)
        }
    }
}
