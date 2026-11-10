import Foundation
import Testing
@testable import LectureNoteApp

/// What a citation's preview shows, and where a click on it goes.
@MainActor
struct CitationPreviewTests {
    @Test func theCitedSentenceIsPickedFromThePassage() {
        let passage = "Okay, a few words about the exam. For the midterm, it's lectures four to seven. Most of the marks are on action potentials, so make sure you can draw that graph. Next week is synapses."
        let picked = CitationQuote.pick(in: passage, for: "The midterm covers lectures 4 to 7, with most weight on action potentials")
        #expect(picked.quote.contains("action potentials") || picked.quote.contains("midterm"))
        #expect(picked.excerpt.contains(picked.quote.replacingOccurrences(of: "…", with: "")))
        let chinese = CitationQuote.pick(in: "今天先复习。期中考试考第四到第七讲。大部分分数在动作电位上。", for: "期中考第四到第七讲")
        #expect(chinese.quote.contains("第四到第七讲"))
    }

    @Test func theClaimIsTheSentenceBeforeTheMarker() {
        let answer = "Myelin insulates the axon. So the impulse jumps between nodes [2]. More text."
        let marker = answer.range(of: "[2]")!.lowerBound
        #expect(CitationQuote.claim(in: answer, before: marker) == "So the impulse jumps between nodes")
    }

    @Test func timesAndPagesAreReadFromOldDetails() {
        #expect(CitationQuote.clockSeconds(in: "2026-11-08 · 31:20") == 1880)
        #expect(CitationQuote.clockSeconds(in: "1:02:05") == 3725)
        #expect(CitationQuote.clockSeconds(in: "会议摘要") == nil)
        #expect(CitationQuote.pageNumber(in: "第 3 页") == 3)
        #expect(CitationQuote.pageNumber(in: "Page 12 · part 2") == 12)
        #expect(CitationQuote.pageNumber(in: "Results") == nil)
    }

    @Test func newCitationsKeepTheMomentPageAndQuote() {
        let meetingID = UUID(), sourceID = UUID()
        let blocks = [
            ContextBlock(title: "Lecture 6", detail: "41:18", body: "For the midterm, it's lectures four to seven.", meetingID: meetingID, at: 2478),
            ContextBlock(title: "Syllabus.pdf", detail: "第 3 页", body: "Midterm exam: November 18, Hall B.", sourceID: sourceID, page: 3),
        ]
        let citations = ChatContext.citations(in: "It covers lectures 4 to 7 [1]. It is on November 18 [2].", blocks: blocks)
        #expect(citations[0].at == 2478)
        #expect(citations[0].quote?.contains("lectures four to seven") == true)
        #expect(citations[1].page == 3)
        #expect(citations[1].quote?.contains("November 18") == true)
    }

    @Test func oldLectureCitationsStillFindTheirMomentAndWords() throws {
        var meeting = Meeting.live(sourceLanguage: "en", targetLanguage: "zh")
        meeting.isLive = false
        meeting.title = "Lecture 6"
        meeting.paragraphs = [
            Paragraph(id: 1, openedAt: 0, commits: [Commit(id: 1, source: "Welcome back.", translation: "欢迎回来。", start: 0, end: 2)], tail: "", closed: true),
            Paragraph(id: 2, openedAt: 1879.6, commits: [Commit(id: 2, source: "Bring one page of notes.", translation: "带一页笔记。", start: 1879.6, end: 1884)], tail: "", closed: true),
        ]
        let model = AppModel(engine: ReplayEngine(), meetings: [meeting], categories: [])
        // Saved before quotes and times were kept: only the clock in its detail.
        let old = ChatCitation(title: "Lecture 6", detail: "2026-11-08 · 31:20", meetingID: meeting.id, passage: 1)
        let details = model.citationDetails(old)
        #expect(details.kind == .lecture)
        #expect(details.at == 1880)
        #expect(details.place == "31:20")
        #expect(details.excerpt.contains("Bring one page of notes"))
        #expect(details.translation == "带一页笔记。")

        model.openCitation(old)
        #expect(model.openMeetingID == meeting.id)
        #expect(model.transcriptJump?.time == 1880, "the transcript jumps to the cited moment")
    }

    @Test func removedSourcesSaySoAndKindsFollowTheFile() {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        let gone = ChatCitation(title: "Old handout.pdf", detail: "第 2 页", sourceID: UUID(), passage: 1)
        #expect(model.citationDetails(gone).kind == .missing)
        #expect(CitationKind.of(gone) == .pdf)
        #expect(CitationKind.of(ChatCitation(title: "Week7.pptx", sourceID: UUID())) == .slides)
        #expect(CitationKind.of(ChatCitation(title: "board.jpg", sourceID: UUID())) == .picture)
        #expect(CitationKind.of(ChatCitation(title: "notes.docx", sourceID: UUID())) == .document)
        #expect(CitationKind.of(ChatCitation(title: "Lecture 6", detail: tr("会议摘要"), meetingID: UUID())) == .summary)
        let web = ChatCitation(title: "Saltatory conduction", detail: "britannica.com", url: "https://www.britannica.com/x", passage: 3)
        let details = model.citationDetails(web)
        #expect(details.kind == .web)
        #expect(details.origin == "britannica.com")
        #expect(details.title == "Saltatory conduction")
    }

    @Test func theSourcesRowListsEachSourceOnce() {
        let meetingID = UUID()
        let citations: [Int: ChatCitation] = [
            1: ChatCitation(title: "Lecture 6", detail: "41:18", meetingID: meetingID, passage: 1),
            2: ChatCitation(title: "Lecture 6", detail: "43:02", meetingID: meetingID, passage: 2),
            3: ChatCitation(title: "Syllabus.pdf", detail: "第 3 页", sourceID: UUID(), passage: 3),
            4: ChatCitation(title: "Saltatory", detail: "britannica.com", url: "https://www.britannica.com/x", passage: 4),
        ]
        let row = AnswerBody.sourceRow(citations)
        #expect(row.map { $0["kind"] } == ["lecture", "doc", "web"])
        #expect(row.last?["label"] == "britannica.com")
        #expect(AnswerBody.sourceRow([1: citations[1]!]).isEmpty, "one source needs no row")
    }

    @Test func savedChatsWithoutTheNewFieldsStillLoad() throws {
        let old = Data(#"{"id":"\#(UUID().uuidString)","title":"Lecture 6","detail":"31:20","passage":1}"#.utf8)
        let citation = try JSONDecoder().decode(ChatCitation.self, from: old)
        #expect(citation.at == nil && citation.quote == nil)
    }
}
