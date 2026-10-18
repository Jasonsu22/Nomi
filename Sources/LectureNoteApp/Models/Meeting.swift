import Foundation

enum CaptureSource: String, Equatable {
    case microphone
    case system

    var title: String {
        switch self {
        case .microphone: "麦克风"
        case .system: "系统声音"
        }
    }
}

struct Meeting: Identifiable, Equatable {
    var id: UUID
    var title: String
    var startedAt: Date
    var duration: TimeInterval
    var source: CaptureSource
    var sourceLanguage: String
    var targetLanguage: String
    var paragraphs: [Paragraph]
    var isLive: Bool

    var characterCount: Int {
        paragraphs.reduce(0) { $0 + $1.source.count }
    }

    var markdown: String {
        var lines = ["# \(title)", ""]
        lines.append("- 时间：\(formatMeetingTime(startedAt))")
        lines.append("- 时长：\(formatDuration(duration))")
        lines.append("- 输入：\(source.title) · \(languageName(sourceLanguage)) → \(languageName(targetLanguage))")
        lines.append("")
        for paragraph in paragraphs where !paragraph.source.isEmpty {
            lines.append("## \(formatClock(paragraph.openedAt))")
            lines.append("")
            lines.append(paragraph.source)
            if !paragraph.translation.isEmpty {
                lines.append("")
                lines.append(paragraph.translation)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func live() -> Meeting {
        Meeting(
            id: UUID(),
            title: "未命名会议",
            startedAt: .now,
            duration: 0,
            source: .microphone,
            sourceLanguage: "zh",
            targetLanguage: "en",
            paragraphs: [],
            isLive: true
        )
    }
}
