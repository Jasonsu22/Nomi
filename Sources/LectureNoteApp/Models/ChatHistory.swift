import Foundation

/// The earlier turns of a chat that go into the next prompt.
struct HistoryWindow: Equatable, Sendable {
    /// The "Previous conversation" block, empty when there is nothing to show.
    var text: String
    /// Turns shown in `text`. Library search leaves these out, so nothing appears twice.
    var includedTurns: Set<UUID>
    /// Answered turns older than the window that the prompt does not show.
    var omittedOlderTurns: Int

    static let empty = HistoryWindow(text: "", includedTurns: [], omittedOlderTurns: 0)
}

/// Chooses and trims earlier turns so a follow-up still sees what was said, within the model's budget.
enum ChatHistory {
    static let questionLimit = 800

    /// Fills the history budget with whole turns, newest first. The newest turn is always shown,
    /// cut harder if it alone is over budget. `dated` adds the day and time to each turn.
    static func window(
        _ turns: [ChatTurn],
        budget: ContextBudget,
        omittedImageTurns: Set<UUID> = [],
        dated: Bool = true
    ) -> HistoryWindow {
        let answered = turns.filter { $0.error == nil && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var shown: [(UUID, String)] = []
        var used = 0
        for turn in answered.reversed() {
            var text = render(turn, answerLimit: budget.turnAnswer, image: omittedImageTurns.contains(turn.id), dated: dated)
            if shown.isEmpty, text.count > budget.history {
                let room = max(200, budget.history - min(turn.question.count, questionLimit) - 60)
                text = render(turn, answerLimit: room, image: omittedImageTurns.contains(turn.id), dated: dated)
            } else if !shown.isEmpty, used + text.count > budget.history {
                break
            }
            shown.append((turn.id, text))
            used += text.count
        }
        guard !shown.isEmpty else { return .empty }
        let body = shown.reversed().map(\.1).joined(separator: "\n\n")
        return HistoryWindow(
            text: "Previous conversation (reference only):\n\(body)",
            includedTurns: Set(shown.map(\.0)),
            omittedOlderTurns: answered.count - shown.count
        )
    }

    private static func render(_ turn: ChatTurn, answerLimit: Int, image: Bool, dated: Bool) -> String {
        let stamp = dated ? "[\(timeStamp(turn.createdAt))] " : ""
        var text = "\(stamp)Question: \(trimmed(turn.question, limit: questionLimit))\nAnswer: \(cleanedAnswer(turn.answer, limit: answerLimit))"
        if image { text += "\n用户发过一张图片" }
        return text
    }

    /// An answer as the model should reread it: a demo page becomes one line, tool and visual
    /// markers are dropped, and a long answer keeps its start and its end, cut at sentence ends.
    static func cleanedAnswer(_ answer: String, limit: Int) -> String {
        var text = ChatContext.splitVisual(answer, streaming: false).text
        text = ChatTools.parse(text, streaming: false).visible
        text = replacingPages(in: text)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed(text, limit: limit)
    }

    /// Keeps about 70% from the start and 30% from the end when `text` is over `limit`.
    /// The start usually holds the main point; the end holds the conclusion and the last list items.
    static func trimmed(_ text: String, limit: Int) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit, limit > 0 else { return text }
        let headLength = limit * 7 / 10
        let tailLength = max(0, limit - headLength - 3)
        let head = cutAfterLastSentence(String(text.prefix(headLength)))
        guard tailLength > 0 else { return head + "…" }
        let tail = cutBeforeFirstSentence(String(text.suffix(tailLength)))
        return head + "\n…\n" + tail
    }

    private static let sentenceEnds: Set<Character> = ["。", "！", "？", "；", ".", "!", "?", ";", "\n"]

    /// Ends the head at its last sentence end, if one falls in its second half.
    private static func cutAfterLastSentence(_ head: String) -> String {
        guard let index = head.lastIndex(where: { sentenceEnds.contains($0) }),
              head.distance(from: head.startIndex, to: index) >= head.count / 2 else { return head }
        return String(head[...index]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Starts the tail after its first sentence end, if one falls in its first half.
    private static func cutBeforeFirstSentence(_ tail: String) -> String {
        guard let index = tail.firstIndex(where: { sentenceEnds.contains($0) }),
              tail.distance(from: tail.startIndex, to: index) < tail.count / 2 else { return tail }
        return String(tail[tail.index(after: index)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let fence = try! NSRegularExpression(pattern: "```([^\\n`]*)\\n([\\s\\S]*?)(?:```|$)")
    private static let pageTitle = try! NSRegularExpression(pattern: "<title>([^<]{1,80})</title>", options: [.caseInsensitive])

    /// A fenced HTML page costs thousands of characters and says little to a model; one line names it.
    private static func replacingPages(in text: String) -> String {
        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in fence.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let info = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces).lowercased()
            let body = source.substring(with: match.range(at: 2))
            let lowered = body.lowercased()
            let isPage = info.hasPrefix("html") || lowered.contains("<!doctype html") || lowered.contains("<html")
            guard isPage else { continue }
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let titleMatch = pageTitle.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length))
            let title = titleMatch.map { (body as NSString).substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces) } ?? ""
            result += title.isEmpty ? "[交互演示]" : "[交互演示：\(title)]"
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return result
    }

    private static func timeStamp(_ date: Date) -> String {
        let parts = LibraryDates.calendar.dateComponents([.hour, .minute], from: date)
        return LibraryDates.dayStamp(date, calendar: LibraryDates.calendar) + String(format: " %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
