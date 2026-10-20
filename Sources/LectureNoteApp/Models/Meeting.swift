import Foundation

enum CaptureSource: String, Equatable, Codable {
    case microphone
    case system

    var title: String {
        switch self {
        case .microphone: tr("麦克风")
        case .system: tr("系统声音")
        }
    }
}

struct Meeting: Identifiable, Equatable, Codable {
    var id: UUID
    var title: String
    var startedAt: Date
    var duration: TimeInterval
    var source: CaptureSource
    var sourceLanguage: String
    var targetLanguage: String
    var categoryID: UUID?
    var paragraphs: [Paragraph]
    var isLive: Bool
    var inputDeviceName: String? = nil
    /// File names inside `MeetingStore.audioDirectory(for: id)`, one per recording run.
    var audioFiles: [String]? = nil
    /// The side panel's summary and questions, kept so they survive a restart.
    var assistant: MeetingAssistantRecord? = nil

    var inputTitle: String { inputDeviceName ?? source.title }

    var characterCount: Int {
        paragraphs.reduce(0) { $0 + $1.renderedSource(language: sourceLanguage).count }
    }

    func markdown(categoryName: String?) -> String {
        var lines = ["# \(title)", ""]
        lines.append(trf("- 时间：%@", formatMeetingTime(startedAt)))
        lines.append(trf("- 时长：%@", formatDuration(duration)))
        if let categoryName {
            lines.append(trf("- 分类：%@", categoryName))
        }
        lines.append(trf("- 输入：%@ · %@ → %@", inputTitle, languageName(sourceLanguage), languageName(targetLanguage)))
        lines.append("")
        for paragraph in paragraphs {
            let source = paragraph.renderedSource(language: sourceLanguage)
            guard !source.isEmpty else { continue }
            lines.append("## \(formatClock(paragraph.openedAt))")
            lines.append("")
            lines.append(source)
            let translation = paragraph.renderedTranslation(language: targetLanguage)
            if !translation.isEmpty {
                lines.append("")
                lines.append(translation)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func live(sourceLanguage: String? = nil, targetLanguage: String? = nil, inputDeviceName: String? = nil) -> Meeting {
        let pair = LectureLanguages.currentPair()
        return Meeting(
            id: UUID(),
            title: tr("未命名会议"),
            startedAt: .now,
            duration: 0,
            source: .microphone,
            sourceLanguage: sourceLanguage ?? pair.source,
            targetLanguage: targetLanguage ?? pair.target,
            categoryID: nil,
            paragraphs: [],
            isLive: true,
            inputDeviceName: inputDeviceName
        )
    }
}

/// What the meeting side panel produced: its summary and the questions asked about this meeting.
struct MeetingAssistantRecord: Codable, Equatable, Sendable {
    struct Answer: Codable, Equatable, Sendable, Identifiable {
        var id = UUID()
        var question: String
        var answer: String
        var modelName: String
        var createdAt: Date
    }

    /// Questions kept per meeting; older ones are dropped.
    static let answerLimit = 50

    var summary: String?
    var summaryModelName: String?
    var summaryAt: Date?
    /// The transcript time the summary saw, to tell when the transcript has grown since.
    var summaryCoversUntil: TimeInterval?
    var answers: [Answer] = []

    mutating func append(_ answer: Answer) {
        answers.append(answer)
        if answers.count > Self.answerLimit { answers.removeFirst(answers.count - Self.answerLimit) }
    }

    /// True when the transcript runs more than a minute past what the summary saw.
    func summaryIsStale(transcriptEnd: TimeInterval) -> Bool {
        guard summary != nil, let covered = summaryCoversUntil else { return false }
        return transcriptEnd > covered + 60
    }
}
