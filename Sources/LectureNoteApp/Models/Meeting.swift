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
    var categoryID: UUID?
    var paragraphs: [Paragraph]
    var isLive: Bool

    var characterCount: Int {
        paragraphs.reduce(0) { $0 + $1.renderedSource(language: sourceLanguage).count }
    }

    func markdown(categoryName: String?) -> String {
        var lines = ["# \(title)", ""]
        lines.append("- 时间：\(formatMeetingTime(startedAt))")
        lines.append("- 时长：\(formatDuration(duration))")
        if let categoryName {
            lines.append("- 分类：\(categoryName)")
        }
        lines.append("- 输入：\(source.title) · \(languageName(sourceLanguage)) → \(languageName(targetLanguage))")
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

    static func live() -> Meeting {
        Meeting(
            id: UUID(),
            title: "未命名会议",
            startedAt: .now,
            duration: 0,
            source: .microphone,
            sourceLanguage: "zh",
            targetLanguage: "en",
            categoryID: nil,
            paragraphs: [],
            isLive: true
        )
    }
}
