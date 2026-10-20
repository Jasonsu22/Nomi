import Foundation

/// One searchable piece of the student's own material: part of a lecture transcript,
/// one earlier chat turn, or a chunk of an imported file.
struct LibraryDocument: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case meeting
        case chat
        case source
    }

    var kind: Kind
    var title: String
    var date: Date
    /// Shown with the citation, for example "2026-10-14 · 12:04".
    var detail: String
    var body: String
    /// Pieces of the same meeting, chat or file share a group, so an overview lists each item once.
    var group: UUID
    var meetingID: UUID? = nil
    var sourceID: UUID? = nil
    var chatID: UUID? = nil
}

/// What to look for. Built from the model's `search_library` call or from the question itself.
struct LibraryRequest: Equatable, Sendable {
    var query: String
    var kinds: Set<LibraryDocument.Kind>
    var range: DateInterval?

    init(query: String, kinds: Set<LibraryDocument.Kind> = Set(LibraryDocument.Kind.allCases), range: DateInterval? = nil) {
        self.query = query
        self.kinds = kinds.isEmpty ? Set(LibraryDocument.Kind.allCases) : kinds
        self.range = range
    }

    /// Reads `{"query": …, "in": […], "from": "YYYY-MM-DD", "to": "YYYY-MM-DD"}`. Plain text is taken as the query.
    /// Phrases such as "last week" or 上周 in the query also set the dates when none are given.
    static func parse(_ body: String, now: Date = .now, calendar: Calendar = LibraryDates.calendar) -> LibraryRequest {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return LibraryRequest(query: trimmed, range: LibraryDates.range(in: trimmed, now: now, calendar: calendar))
        }
        let query = (object["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let names = (object["in"] as? [String]) ?? (object["in"] as? String).map { [$0] } ?? []
        let kinds = Set(names.compactMap(Self.kind))
        let from = (object["from"] as? String).flatMap { LibraryDates.day($0, calendar: calendar) }
        let to = (object["to"] as? String).flatMap { LibraryDates.day($0, calendar: calendar) }
        var range: DateInterval?
        if from != nil || to != nil {
            let start = from?.start ?? .distantPast
            let end = to?.end ?? now
            range = start <= end ? DateInterval(start: start, end: end) : DateInterval(start: end, end: start)
        } else {
            range = LibraryDates.range(in: query, now: now, calendar: calendar)
        }
        return LibraryRequest(query: query, kinds: kinds, range: range)
    }

    private static func kind(_ name: String) -> LibraryDocument.Kind? {
        switch name.lowercased().trimmingCharacters(in: .whitespaces) {
        case "meeting", "meetings", "lecture", "lectures", "transcript", "transcripts", "recording", "recordings": .meeting
        case "chat", "chats", "conversation", "conversations", "history": .chat
        case "source", "sources", "file", "files", "document", "documents", "material", "materials": .source
        default: nil
        }
    }

    private static let pastCues = [
        "上次", "上回", "之前", "以前", "刚才", "聊过", "聊了", "说过", "讲过", "问过", "提到过", "老师说", "老师讲", "教授说", "上节课", "上一节课", "那节课", "课上说", "课上讲", "我们讨论",
        "last time", "earlier", "previously", "we talked", "we discussed", "we chatted", "you said", "you told", "i asked", "teacher said", "professor said", "lecturer said", "in class", "last class", "last lecture", "last session", "remember when",
    ]

    /// Whether the question points at something from the past, so the library is searched before the first answer.
    static func referencesPast(_ question: String, now: Date = .now, calendar: Calendar = LibraryDates.calendar) -> Bool {
        let folded = question.lowercased()
        if pastCues.contains(where: { folded.contains($0) }) { return true }
        return LibraryDates.range(in: question, now: now, calendar: calendar) != nil
    }
}

/// Turns phrases like "last week" or 上周 into a date range.
enum LibraryDates {
    /// Weeks start on Monday, which is how 上周 and "last week" are usually meant for classes.
    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    static func day(_ text: String, calendar: Calendar) -> DateInterval? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        return calendar.dateInterval(of: .day, for: date)
    }

    static func range(in text: String, now: Date = .now, calendar: Calendar = LibraryDates.calendar) -> DateInterval? {
        let folded = text.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { folded.contains($0) } }
        func shifted(_ unit: Calendar.Component, by value: Int, of component: Calendar.Component) -> DateInterval? {
            guard let date = calendar.date(byAdding: unit, value: value, to: now) else { return nil }
            return calendar.dateInterval(of: component, for: date)
        }
        if let days = lastDays(in: folded), let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) {
            return DateInterval(start: start, end: now)
        }
        if has(["day before yesterday", "前天"]) { return shifted(.day, by: -2, of: .day) }
        if has(["yesterday", "昨天", "昨晚"]) { return shifted(.day, by: -1, of: .day) }
        if has(["today", "今天", "今早", "今晚"]) { return calendar.dateInterval(of: .day, for: now) }
        if has(["last week", "previous week", "上周", "上星期", "上个星期", "上礼拜", "上个礼拜"]) { return shifted(.weekOfYear, by: -1, of: .weekOfYear) }
        if has(["this week", "这周", "本周", "这个星期", "这星期", "这礼拜"]) { return calendar.dateInterval(of: .weekOfYear, for: now) }
        if has(["last month", "previous month", "上个月", "上月"]) { return shifted(.month, by: -1, of: .month) }
        if has(["this month", "这个月", "本月"]) { return calendar.dateInterval(of: .month, for: now) }
        if has(["recently", "lately", "past few days", "最近", "这几天", "近几天"]),
           let start = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) {
            return DateInterval(start: start, end: now)
        }
        return nil
    }

    /// "last 3 days", "past 10 days", 最近3天, 过去 5 天.
    private static func lastDays(in text: String) -> Int? {
        let patterns = [/(?:last|past)\s+(\d{1,3})\s+days?/, /(?:最近|过去|近)\s*(\d{1,3})\s*天/]
        for pattern in patterns {
            if let match = text.firstMatch(of: pattern), let value = Int(match.1), value > 0 { return value }
        }
        return nil
    }

    static func stamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }

    static func shortDay(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d-%02d", parts.month ?? 0, parts.day ?? 0)
    }

    static func dayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Ranks the library for a request and returns passages that fit the answer's budget.
enum LibrarySearch {
    static let budget = 9_000
    static let limit = 14

    static func run(_ request: LibraryRequest, in documents: [LibraryDocument], now: Date = .now, budget: Int = budget, limit: Int = limit) -> [ContextBlock] {
        let candidates = documents.filter { document in
            request.kinds.contains(document.kind) && (request.range?.contains(document.date) ?? true)
        }
        guard !candidates.isEmpty else { return [] }
        let terms = Set(searchTerms(in: request.query))
        let ranked = terms.isEmpty ? [] : rank(candidates, terms: terms, now: now)
        // A question like "what did we talk about last week" has no useful words, so it gets an overview of the range.
        let picked = ranked.isEmpty ? overview(candidates) : ranked
        return fill(picked, budget: budget, limit: limit)
    }

    /// BM25 with a gentle preference for recent material.
    private static func rank(_ documents: [LibraryDocument], terms: Set<String>, now: Date) -> [LibraryDocument] {
        let tokenized = documents.map { searchTerms(in: $0.title + "\n" + $0.body) }
        let lengths = tokenized.map { Double(max($0.count, 1)) }
        let average = lengths.reduce(0, +) / Double(lengths.count)
        var frequency: [String: Int] = [:]
        for tokens in tokenized {
            for term in Set(tokens) where terms.contains(term) { frequency[term, default: 0] += 1 }
        }
        let count = Double(documents.count)
        var scored: [(Double, Int)] = []
        for (index, tokens) in tokenized.enumerated() {
            var counts: [String: Int] = [:]
            for token in tokens where terms.contains(token) { counts[token, default: 0] += 1 }
            guard !counts.isEmpty else { continue }
            var score = 0.0
            for (term, hits) in counts {
                let df = Double(frequency[term] ?? 0)
                let idf = log(1 + (count - df + 0.5) / (df + 0.5))
                let tf = Double(hits)
                score += idf * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * lengths[index] / average))
            }
            let ageDays = max(0, now.timeIntervalSince(documents[index].date) / 86_400)
            score *= 1 + 0.15 * exp(-ageDays / 30)
            scored.append((score, index))
        }
        return scored.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : documents[$0.1].date > documents[$1.1].date }.map { documents[$0.1] }
    }

    /// Newest first. A meeting or file shows its opening; each chat turn stands on its own.
    private static func overview(_ documents: [LibraryDocument]) -> [LibraryDocument] {
        var seen = Set<UUID>()
        var picked: [LibraryDocument] = []
        for document in documents.sorted(by: { $0.date > $1.date }) {
            if document.kind != .chat {
                guard seen.insert(document.group).inserted else { continue }
            }
            picked.append(document)
        }
        return picked
    }

    private static func fill(_ documents: [LibraryDocument], budget: Int, limit: Int) -> [ContextBlock] {
        var blocks: [ContextBlock] = []
        var used = 0
        for document in documents {
            guard blocks.count < limit, used < budget else { break }
            var body = document.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let room = min(budget - used, 1_400)
            guard room >= 120 else { break }
            if body.count > room { body = String(body.prefix(room)) + "…" }
            used += body.count
            blocks.append(ContextBlock(
                title: document.title,
                detail: document.detail,
                body: body,
                meetingID: document.meetingID,
                sourceID: document.sourceID,
                chatID: document.chatID
            ))
        }
        return blocks
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "what", "did", "does", "was", "were", "about", "that", "this", "with", "from", "you", "we", "our", "my", "me", "is", "are", "of", "to", "in", "on", "a", "an", "it", "do", "say", "said", "tell", "talk", "talked", "chat", "chatted", "last", "week", "month", "today", "yesterday", "earlier", "before", "teacher", "professor", "class", "lecture", "time", "previously", "recently",
        "什么", "我们", "你们", "上周", "这周", "本周", "昨天", "今天", "前天", "上次", "之前", "以前", "老师", "教授", "说了", "说过", "讲了", "讲过", "聊了", "聊过", "聊天", "一下", "这个", "那个", "有没", "没有", "哪些", "怎么", "时候", "最近", "个月", "上个", "星期", "礼拜", "提到", "上课", "节课",
    ]

    /// Latin words of two or more letters, and overlapping character pairs for Chinese, Japanese and Korean text.
    static func searchTerms(in text: String) -> [String] {
        var terms: [String] = []
        var latin = ""
        var run: [Character] = []
        func flushLatin() {
            if latin.count >= 2, !stopWords.contains(latin) { terms.append(latin) }
            latin = ""
        }
        func flushRun() {
            if run.count == 1 {
                terms.append(String(run[0]))
            } else if run.count > 1 {
                for index in 0..<(run.count - 1) {
                    let pair = String(run[index...index + 1])
                    if !stopWords.contains(pair) { terms.append(pair) }
                }
            }
            run = []
        }
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                if character.isASCII {
                    flushRun()
                    latin.append(character)
                } else {
                    flushLatin()
                    run.append(character)
                }
            } else {
                flushLatin()
                flushRun()
            }
        }
        flushLatin()
        flushRun()
        return terms
    }
}

extension LibrarySearch {
    /// Splits lecture transcripts into passages of a few paragraphs, so a hit carries its surrounding sentences.
    static func meetingDocuments(id: UUID, title: String, startedAt: Date, paragraphs: [(openedAt: TimeInterval, source: String, translation: String)]) -> [LibraryDocument] {
        var documents: [LibraryDocument] = []
        var text = ""
        var opened: TimeInterval?
        func flush() {
            guard let opened, !text.isEmpty else { return }
            documents.append(LibraryDocument(
                kind: .meeting,
                title: title,
                date: startedAt.addingTimeInterval(opened),
                detail: LibraryDates.dayStamp(startedAt) + " · " + formatClock(opened),
                body: text,
                group: id,
                meetingID: id
            ))
        }
        for paragraph in paragraphs {
            let source = paragraph.source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { continue }
            if opened == nil { opened = paragraph.openedAt }
            let translation = paragraph.translation.trimmingCharacters(in: .whitespacesAndNewlines)
            text += (text.isEmpty ? "" : "\n") + source + (translation.isEmpty ? "" : "\n(" + translation + ")")
            if text.count >= 700 {
                flush()
                text = ""
                opened = nil
            }
        }
        flush()
        return documents
    }

    static func chatDocuments(id: UUID, title: String, turns: [ChatTurn]) -> [LibraryDocument] {
        turns.compactMap { turn in
            let answer = turn.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard turn.error == nil, !turn.question.isEmpty || !answer.isEmpty else { return nil }
            // A chat's own title is usually its first question, which says little; the date tells turns apart.
            return LibraryDocument(
                kind: .chat,
                title: trf("%@ 的对话", LibraryDates.shortDay(turn.createdAt)),
                date: turn.createdAt,
                detail: LibraryDates.stamp(turn.createdAt),
                body: "Earlier conversation.\nStudent: \(turn.question.prefix(600))\nNomi: \(answer.prefix(1_000))",
                group: id,
                chatID: id
            )
        }
    }

    static func sourceDocuments(_ source: KnowledgeSource, blocks: [ContextBlock]) -> [LibraryDocument] {
        blocks.map { block in
            LibraryDocument(
                kind: .source,
                title: block.title,
                date: source.importedAt,
                detail: block.detail,
                body: block.body,
                group: source.id,
                sourceID: source.id
            )
        }
    }
}

/// Extracted text of imported files, kept until the file changes, so searching the
/// whole library does not read every PDF again.
actor SourceTextCache {
    static let shared = SourceTextCache()
    private var entries: [UUID: (modified: Date, blocks: [ContextBlock])] = [:]

    func blocks(for source: KnowledgeSource) -> [ContextBlock] {
        if let entry = entries[source.id], entry.modified == source.fileModifiedAt { return entry.blocks }
        let blocks = SourceText.blocks(url: SourceStore.fileURL(for: source), title: source.title, sourceID: source.id)
        entries[source.id] = (source.fileModifiedAt, blocks)
        return blocks
    }

    /// Drops files that were removed from Sources.
    func keep(only ids: Set<UUID>) {
        entries = entries.filter { ids.contains($0.key) }
    }
}

/// What a question already carries, so the library does not send it twice.
struct LibraryExclusions: Sendable {
    var turns: Set<UUID>
    var meetings: Set<UUID>
    var sources: Set<UUID>
}
