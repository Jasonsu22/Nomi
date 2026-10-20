import Foundation
import Testing
@testable import LectureNoteApp

struct LibrarySearchTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Tuesday, 2026-10-20, 15:00 in New York.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 15))!
    }

    private func day(_ value: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: value, hour: hour))!
    }

    @Test func relativePhrasesBecomeDateRanges() throws {
        let lastWeek = try #require(LibraryDates.range(in: "上周老师讲了什么", now: now, calendar: calendar))
        #expect(lastWeek.start == calendar.startOfDay(for: day(12)))
        #expect(lastWeek.end == calendar.startOfDay(for: day(19)))
        #expect(LibraryDates.range(in: "what did we talk about last week", now: now, calendar: calendar) == lastWeek)

        let yesterday = try #require(LibraryDates.range(in: "yesterday's lecture", now: now, calendar: calendar))
        #expect(yesterday.contains(day(19)))
        #expect(!yesterday.contains(day(20)))

        let recent = try #require(LibraryDates.range(in: "最近3天的对话", now: now, calendar: calendar))
        #expect(recent.contains(day(18)))
        #expect(!recent.contains(day(16)))

        #expect(LibraryDates.range(in: "What is photosynthesis?", now: now, calendar: calendar) == nil)
    }

    @Test func aToolCallReadsJSONOrPlainText() {
        let json = LibraryRequest.parse(#"{"query": "exam", "in": ["chats", "lectures"], "from": "2026-10-12", "to": "2026-10-18"}"#, now: now, calendar: calendar)
        #expect(json.query == "exam")
        #expect(json.kinds == [.chat, .meeting])
        #expect(json.range?.contains(day(18, hour: 23)) == true)
        #expect(json.range?.contains(day(19, hour: 1)) == false)

        let plain = LibraryRequest.parse("osmosis last week", now: now, calendar: calendar)
        #expect(plain.query == "osmosis last week")
        #expect(plain.kinds == Set(LibraryDocument.Kind.allCases))
        #expect(plain.range?.contains(day(14)) == true)
    }

    @Test func questionsAboutThePastAreSearchedFirst() {
        #expect(LibraryRequest.referencesPast("上次我们聊了什么", now: now, calendar: calendar))
        #expect(LibraryRequest.referencesPast("What did the teacher said about the midterm?", now: now, calendar: calendar))
        #expect(LibraryRequest.referencesPast("昨天的课讲了啥", now: now, calendar: calendar))
        #expect(!LibraryRequest.referencesPast("What is photosynthesis?", now: now, calendar: calendar))
    }

    private var library: [LibraryDocument] {
        let lecture = UUID(), chatA = UUID(), chatB = UUID(), file = UUID()
        return [
            LibraryDocument(kind: .meeting, title: "Biology 101", date: day(14), detail: "2026-10-14 · 12:04", body: "The midterm exam covers photosynthesis and cell respiration.", group: lecture, meetingID: lecture),
            LibraryDocument(kind: .meeting, title: "Biology 101", date: day(14, hour: 11), detail: "2026-10-14 · 40:10", body: "Mitochondria produce ATP for the cell.", group: lecture, meetingID: lecture),
            LibraryDocument(kind: .chat, title: "光合作用", date: day(13), detail: "2026-10-13 10:00", body: "Earlier conversation.\nStudent: 光合作用在哪里发生？\nNomi: 主要在叶绿体中。", group: chatA, chatID: chatA),
            LibraryDocument(kind: .chat, title: "Economics", date: day(5), detail: "2026-10-05 10:00", body: "Earlier conversation.\nStudent: What is opportunity cost?\nNomi: The value of the next best choice.", group: chatB, chatID: chatB),
            LibraryDocument(kind: .source, title: "Week 4.pdf", date: day(2), detail: "p.3", body: "Opportunity cost and supply curves.", group: file, sourceID: file),
        ]
    }

    @Test func keywordsFindTheRightPassageAcrossKinds() {
        let exam = LibrarySearch.run(LibraryRequest(query: "When is the midterm exam?"), in: library, now: now)
        #expect(exam.first?.title == "Biology 101")
        #expect(exam.first?.meetingID != nil)

        let chinese = LibrarySearch.run(LibraryRequest(query: "光合作用发生在哪里"), in: library, now: now)
        #expect(chinese.first?.chatID != nil)

        let cost = LibrarySearch.run(LibraryRequest(query: "opportunity cost"), in: library, now: now)
        #expect(Set(cost.map(\.title)) == ["Economics", "Week 4.pdf"])
    }

    @Test func kindsAndDatesNarrowTheSearch() {
        let filesOnly = LibrarySearch.run(LibraryRequest(query: "opportunity cost", kinds: [.source]), in: library, now: now)
        #expect(filesOnly.map(\.title) == ["Week 4.pdf"])

        let lastWeek = LibraryDates.range(in: "last week", now: now, calendar: calendar)
        let recentCost = LibrarySearch.run(LibraryRequest(query: "opportunity cost", range: lastWeek), in: library, now: now)
        #expect(recentCost.isEmpty == false)
        #expect(recentCost.allSatisfy { $0.title != "Economics" && $0.title != "Week 4.pdf" })
    }

    @Test func aQuestionWithoutKeywordsGetsAnOverviewOfTheRange() {
        let range = LibraryDates.range(in: "last week", now: now, calendar: calendar)
        let overview = LibrarySearch.run(LibraryRequest(query: "what did we talk about last week", range: range), in: library, now: now)
        // One passage for the lecture, the chat turn, newest first; nothing outside the week.
        #expect(overview.map(\.title) == ["Biology 101", "光合作用"])
    }

    @Test func meetingTranscriptsAreGroupedIntoDatedPassages() {
        let id = UUID()
        let start = day(14, hour: 9)
        let paragraphs = (0..<12).map { index in
            (openedAt: TimeInterval(index * 60), source: String(repeating: "word ", count: 30) + "\(index)", translation: "翻译\(index)")
        }
        let documents = LibrarySearch.meetingDocuments(id: id, title: "Lecture", startedAt: start, paragraphs: paragraphs)
        #expect(documents.count > 1)
        #expect(documents.allSatisfy { $0.meetingID == id && $0.group == id })
        #expect(documents[0].detail.hasPrefix("2026-10-14 · "))
        #expect(documents[1].date > documents[0].date)
        #expect(documents[0].body.contains("(翻译0)"))
    }

    @Test func aLibraryCallPausesTheReplyLikeWebSearch() {
        let raw = #"Let me check. <tool name="search_library">{"query": "exam"}</tool> The exam is on Monday."#
        let parsed = ChatTools.parse(raw, streaming: false, stopAtSearch: true)
        #expect(parsed.visible.trimmingCharacters(in: .whitespaces) == "Let me check.")
        #expect(parsed.calls == [ChatTools.Call(name: "search_library", body: #"{"query": "exam"}"#)])
    }

    @Test func aCitedEarlierChatOpensThatChat() {
        let chat = UUID()
        let blocks = [ContextBlock(title: "光合作用", detail: "2026-10-13 10:00", body: "Earlier conversation.", chatID: chat)]
        let citations = ChatContext.citations(in: "你上周问过这个 [1]。", blocks: blocks)
        #expect(citations.first?.chatID == chat)
        #expect(citations.first?.inlineURL != nil)
        #expect(citations.first?.symbolName == "bubble.left.and.bubble.right")
    }

    @Test func thePromptOffersTheLibraryWithTodaysDate() {
        let offered = ChatContext.toolInstruction(language: "English", webTool: .off, library: .available, now: now)
        #expect(offered.contains("search_library"))
        #expect(offered.contains("Today is 2026-10-20"))
        let chinese = ChatContext.toolInstruction(language: "Simplified Chinese", webTool: .off, library: .used, now: now)
        #expect(chinese.contains("不要再调用 search_library"))
        let off = ChatContext.toolInstruction(language: "English", webTool: .off, library: .off, now: now)
        #expect(!off.contains("search_library"))
    }
}
