import AppKit
import Foundation

enum AppPage: String, CaseIterable, Identifiable {
    case meetings
    case ask
    case sources
    case stats
    case help
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meetings: "会议"
        case .ask: "提问"
        case .sources: "资料"
        case .stats: "统计"
        case .help: "帮助"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .meetings: "calendar"
        case .ask: "text.bubble"
        case .sources: "folder"
        case .stats: "chart.bar"
        case .help: "questionmark.circle"
        case .settings: "gearshape"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var page: AppPage = .meetings
    var meetings: [Meeting]
    var query = ""
    var openMeetingID: UUID?
    var searchRequest = 0
    let engine: ReplayEngine

    private var liveMeetingID: UUID?

    init(engine: ReplayEngine = ReplayEngine(), meetings: [Meeting]? = nil) {
        self.engine = engine
        self.meetings = meetings ?? SampleMeetings.make()
        engine.onFinished = { [weak self] paragraphs, duration in
            self?.finishLiveMeeting(paragraphs: paragraphs, duration: duration)
        }
    }

    var statusTitle: String {
        if engine.loadError != nil { return "示例加载失败" }
        switch engine.session.phase {
        case .idle: return "预览 · 示例回放"
        case .preparing: return "准备中"
        case .listening: return engine.session.isPaused ? "已暂停" : "正在转录"
        case .stopping: return "正在保存"
        }
    }

    var statusIsLive: Bool {
        engine.session.phase == .listening && !engine.session.isPaused
    }

    func filteredMeetings() -> [Meeting] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return meetings }
        return meetings.filter { meeting in
            meeting.title.localizedStandardContains(trimmed)
                || meeting.paragraphs.contains {
                    $0.source.localizedStandardContains(trimmed)
                        || $0.translation.localizedStandardContains(trimmed)
                }
        }
    }

    func startTranscription() {
        guard engine.session.phase == .idle, engine.loadError == nil else { return }
        let meeting = Meeting.live()
        meetings.insert(meeting, at: 0)
        liveMeetingID = meeting.id
        openMeetingID = meeting.id
        page = .meetings
        engine.start()
    }

    func stopTranscription() {
        engine.stop()
    }

    func togglePause() {
        engine.togglePause()
    }

    func openMeeting(_ id: UUID) {
        openMeetingID = id
        page = .meetings
    }

    func closeMeeting() {
        openMeetingID = nil
    }

    func rename(id: UUID, to title: String) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        meetings[index].title = title
    }

    func requestSearch() {
        page = .meetings
        openMeetingID = nil
        searchRequest += 1
    }

    func copyNotes() -> Bool {
        let items: [Meeting]
        if let openMeetingID, let meeting = meetings.first(where: { $0.id == openMeetingID }) {
            items = [meeting]
        } else {
            items = meetings
        }
        let markdown = items.map(\.markdown).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(markdown, forType: .string)
    }

    private func finishLiveMeeting(paragraphs: [Paragraph], duration: TimeInterval) {
        guard let id = liveMeetingID, let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        let hasText = paragraphs.contains { !$0.source.isEmpty }
        if !hasText {
            meetings.remove(at: index)
            if openMeetingID == id { openMeetingID = nil }
        } else {
            meetings[index].paragraphs = paragraphs
            meetings[index].duration = duration
            meetings[index].isLive = false
        }
        liveMeetingID = nil
    }
}
