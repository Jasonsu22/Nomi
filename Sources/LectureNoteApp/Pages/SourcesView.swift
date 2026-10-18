import SwiftUI

struct SourcesView: View {
    var model: AppModel

    var body: some View {
        PageScaffold(title: tr("资料")) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text(tr("课件导入还没做。下面是每场会议的转写和录音文件。"))
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.bottom, Space.s2)
                    VStack(spacing: 0) {
                        ForEach(Array(model.meetings.enumerated()), id: \.element.id) { index, meeting in
                            if index > 0 {
                                Rectangle()
                                    .fill(AppColor.separator)
                                    .frame(height: 1)
                                    .padding(.leading, Space.s4)
                            }
                            HStack(spacing: Space.s3) {
                                Image(systemName: "waveform")
                                    .foregroundStyle(AppColor.textSecondary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meeting.title)
                                        .font(AppFont.secondary.weight(.semibold))
                                        .foregroundStyle(AppColor.textPrimary)
                                    Text(detail(meeting))
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                                Spacer()
                                if let audio = audioURL(meeting) {
                                    Button(tr("在 Finder 中显示")) {
                                        NSWorkspace.shared.activateFileViewerSelecting([audio])
                                    }
                                    .buttonStyle(.plain)
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                                }
                                Text(formatMeetingTime(meeting.startedAt))
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            .padding(Space.s4)
                        }
                    }
                    .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
                .pageColumn()
                .padding(.bottom, Space.s7)
            }
        }
    }

    private func detail(_ meeting: Meeting) -> String {
        let category = model.categoryName(for: meeting) ?? tr("未分类")
        let audio = meeting.audioFiles?.count ?? 0
        guard audio > 0 else { return trf("%@ · 转写 %d 段 · 音频尚未录制", category, meeting.paragraphs.count) }
        return trf("%@ · 转写 %d 段 · 音频 %d 段", category, meeting.paragraphs.count, audio)
    }

    private func audioURL(_ meeting: Meeting) -> URL? {
        guard let name = meeting.audioFiles?.last else { return nil }
        let url = MeetingStore.audioDirectory(for: meeting.id).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
