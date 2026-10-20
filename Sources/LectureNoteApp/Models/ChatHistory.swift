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
    /// cut harder if it alone is over budget. A running summary goes first and covers older turns,
    /// which then do not count as hidden. `dated` adds the day and time to each turn.
    static func window(
        _ turns: [ChatTurn],
        budget: ContextBudget,
        summary: ChatSummary? = nil,
        omittedImageTurns: Set<UUID> = [],
        dated: Bool = true
    ) -> HistoryWindow {
        let answered = answeredTurns(turns)
        let summaryBlock = summary.map { "Summary of earlier conversation (reference only):\n\($0.text)" } ?? ""
        let room = max(budget.history / 2, budget.history - summaryBlock.count)
        var shown: [(UUID, String)] = []
        var used = 0
        for turn in answered.reversed() {
            var text = render(turn, answerLimit: budget.turnAnswer, image: omittedImageTurns.contains(turn.id), dated: dated)
            if shown.isEmpty, text.count > room {
                let answerRoom = max(200, room - min(turn.question.count, questionLimit) - 60)
                text = render(turn, answerLimit: answerRoom, image: omittedImageTurns.contains(turn.id), dated: dated)
            } else if !shown.isEmpty, used + text.count > room {
                break
            }
            shown.append((turn.id, text))
            used += text.count
        }
        guard !shown.isEmpty || !summaryBlock.isEmpty else { return .empty }
        var parts: [String] = []
        if !summaryBlock.isEmpty { parts.append(summaryBlock) }
        if !shown.isEmpty {
            parts.append("Previous conversation (reference only):\n" + shown.reversed().map(\.1).joined(separator: "\n\n"))
        }
        let older = answered.count - shown.count
        let covered = summary.map { coveredCount(answered, through: $0.throughTurnID) } ?? 0
        return HistoryWindow(
            text: parts.joined(separator: "\n\n"),
            includedTurns: Set(shown.map(\.0)),
            omittedOlderTurns: max(0, older - covered)
        )
    }

    /// Turns with an answer, in order. Failed or empty turns never reach a prompt.
    static func answeredTurns(_ turns: [ChatTurn]) -> [ChatTurn] {
        turns.filter { $0.error == nil && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// How many of `answered` a summary through `turnID` covers.
    static func coveredCount(_ answered: [ChatTurn], through turnID: UUID) -> Int {
        answered.firstIndex { $0.id == turnID }.map { $0 + 1 } ?? 0
    }

    /// One turn as it appears in a prompt.
    static func rendered(_ turn: ChatTurn, answerLimit: Int, dated: Bool = true) -> String {
        render(turn, answerLimit: answerLimit, image: false, dated: dated)
    }

    private static func render(_ turn: ChatTurn, answerLimit: Int, image: Bool, dated: Bool) -> String {
        let stamp = dated ? "[\(timeStamp(turn.createdAt))] " : ""
        let label = turn.interrupted == true ? "Answer (interrupted by the student)" : "Answer"
        var text = "\(stamp)Question: \(trimmed(turn.question, limit: questionLimit))\n\(label): \(cleanedAnswer(turn.answer, limit: answerLimit))"
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

/// When a long chat's older turns get summarized, and how.
enum ChatSummaries {
    /// A chat shorter than this is never summarized.
    static let minimumTurns = 6
    /// Uncovered older turns, or their characters, that start a new pass.
    static let batchTurns = 3
    static let batchCharacters = 3_000
    /// Failed passes before a chat is left alone until the app restarts.
    static let maxFailures = 3

    static func limit(for mode: LLMMode) -> Int {
        mode == .local ? 600 : 1_500
    }

    /// The older turns not yet in the summary, when there are enough of them; nil otherwise.
    static func pending(_ turns: [ChatTurn], summary: ChatSummary?, budget: ContextBudget) -> [ChatTurn]? {
        let answered = ChatHistory.answeredTurns(turns)
        guard answered.count >= minimumTurns else { return nil }
        let window = ChatHistory.window(turns, budget: budget, summary: summary)
        guard let oldestShown = answered.firstIndex(where: { window.includedTurns.contains($0.id) }) else { return nil }
        let covered = summary.map { ChatHistory.coveredCount(answered, through: $0.throughTurnID) } ?? 0
        guard covered < oldestShown else { return nil }
        let uncovered = Array(answered[covered..<oldestShown])
        let characters = uncovered.reduce(0) { $0 + ChatHistory.rendered($1, answerLimit: budget.turnAnswer).count }
        guard uncovered.count >= batchTurns || characters >= batchCharacters else { return nil }
        return uncovered
    }

    static func system(language: String, limit: Int) -> String {
        """
        You keep a running summary of one study conversation between a student and Nomi, their study assistant. Merge the earlier summary with the new turns into one summary.
        Keep the topics covered, conclusions and definitions given, numbers, names and dates, decisions the student made, and questions still open. Drop greetings, demos and anything repeated.
        Write in \(language), as short plain sentences or bullets, at most \(limit) characters. Reply with the summary only.
        """
    }

    static func prompt(previous: ChatSummary?, turns: [ChatTurn], budget: ContextBudget) -> String {
        let earlier = previous?.text ?? "(none)"
        let body = turns.map { ChatHistory.rendered($0, answerLimit: budget.turnAnswer) }.joined(separator: "\n\n")
        return "Earlier summary:\n\(earlier)\n\nNew turns:\n\(body)"
    }

    /// The summary to store, or nil for an empty reply.
    static func cleaned(_ reply: String, limit: Int) -> String? {
        var text = ChatContext.splitVisual(reply, streaming: false).text
        text = ChatTools.parse(text, streaming: false).visible
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return ChatHistory.trimmed(text, limit: limit)
    }
}
