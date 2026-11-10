import Foundation
import Testing
@testable import LectureNoteApp

/// A lecture citation from a library search keeps only its chunk's opening time and a quote mixing
/// both languages. Its preview, jump and audio must still land on the sentence actually quoted.
@MainActor
struct LectureMomentTests {
    private func lecture() -> Meeting {
        var meeting = Meeting.live(sourceLanguage: "en", targetLanguage: "zh")
        meeting.isLive = false
        meeting.title = "en"
        meeting.paragraphs = [
            Paragraph(id: 1, openedAt: 5749, commits: [
                Commit(id: 1, source: "All right. So that's the side posting. Yep.", translation: "好的。所以这是侧边帖子。嗯。", start: 5749, end: 5753),
            ], tail: "", closed: true),
            Paragraph(id: 2, openedAt: 5754, commits: [
                Commit(id: 2, source: "Okay. So next week I will show you a more technical presentation.", translation: "好的。下周我将向您展示一个更技术性的演示。", start: 5754, end: 5762),
            ], tail: "", closed: true),
            Paragraph(id: 3, openedAt: 5810, commits: [
                Commit(id: 3, source: "Work in slides using the assertion evidence based approach, and then select the right keywords, and then the minimum number of inputs.", translation: "使用基于证据的断言方法制作幻灯片，然后选择正确的关键词，然后是最少的输入数量。", start: 5810, end: 5821),
                Commit(id: 4, source: "Yeah, bring your laptop.", translation: "是的，带上你的笔记本电脑。", start: 5821, end: 5824),
            ], tail: "", closed: true),
        ]
        return meeting
    }

    @Test func theQuotedSentenceIsFoundInsideTheChunk() {
        let meeting = lecture()
        let quote = "So bring your laptop with your PowerPoint下这个。(使用基于证据的断言方法制作幻灯片，然后选择正确的关键词。然后，最小输入的数量。"
        let moment = LectureMoments.locate(in: meeting.paragraphs, near: 5749, needle: quote)
        #expect(moment?.paragraph == 2)
        #expect(moment?.commits == 0..<1)
        #expect(moment?.at == 5810)
    }

    @Test func thePreviewJumpAndChipAllUseThatSentence() {
        let meeting = lecture()
        let model = AppModel(engine: ReplayEngine(), meetings: [meeting], categories: [])
        model.installCitationLookup()
        let citation = ChatCitation(title: "en", detail: "2026-11-08 · 1:35:49", meetingID: meeting.id, passage: 4,
                                    quote: "(使用基于证据的断言方法制作幻灯片，然后选择正确的关键词。", excerpt: nil)
        let details = model.citationDetails(citation)
        #expect(details.at == 5810)
        #expect(details.until == 5821, "plays to the end of the quoted sentence")
        #expect(details.place == "1:36:50")
        #expect(details.quote.hasPrefix("Work in slides using the assertion evidence"), "the original words, not the translation")
        #expect(details.excerpt.contains(details.quote))
        #expect(details.translationQuote.hasPrefix("使用基于证据的断言方法"), "the translation of the same sentence")
        #expect(details.translation.contains(details.translationQuote))
        #expect(!details.translation.contains("侧边帖子"), "not the translation of the chunk's first line")
        model.openCitation(citation)
        #expect(model.transcriptJump?.time == 5810)
        #expect(AnswerBody.citationChips([4: citation])["4"]?["label"] == "2026-11-08 · 1:36:50")
    }

    @Test func aSentenceStartingBeforeItsLineJumpsToThatLineButPlaysFromItsWords() {
        var meeting = lecture()
        meeting.paragraphs[2].commits[0].start = 5800  // spoken before the line opened at 5810
        let model = AppModel(engine: ReplayEngine(), meetings: [meeting], categories: [])
        let citation = ChatCitation(title: "en", detail: "2026-11-08 · 1:35:49", meetingID: meeting.id, passage: 1,
                                    quote: "assertion evidence based approach, select the right keywords", excerpt: nil)
        let details = model.citationDetails(citation)
        #expect(details.at == 5800, "the recording plays from where the words are spoken")
        #expect(details.lineAt == 5810 && details.place == "1:36:50", "the time shown is the transcript line's")
        model.openCitation(citation)
        #expect(model.transcriptJump?.time == 5810, "the jump lands on the line that holds the words")
    }
}

/// A commit often holds several sentences with one time; the quoted one is cut out of it.
struct SentenceTimingTests {
    @Test func sentencesAreTimedByWhereTheirWordsFall() {
        let pieces = LectureMoments.pieces(of: "First part here. Second part, about 3.5 GPUs. Third.", commit: 0, start: 100, end: 152)
        #expect(pieces.map(\.text) == ["First part here.", "Second part, about 3.5 GPUs.", "Third."])
        #expect(pieces[0].start == 100 && abs(pieces[2].end - 152) < 0.001)
        #expect(pieces[1].start > 115 && pieces[1].start < 118, "about a third of the way in")
    }

    @Test func onlyTheQuotedSentenceIsMarkedAndPlayed() {
        let paragraph = Paragraph(id: 1, openedAt: 100, commits: [
            Commit(id: 1, source: "We don't have enough GPU cards. So you should use a small model on the phone. Okay, next.",
                   translation: "我们没有足够的 GPU 卡。所以你应该在手机上用小模型。好的，下一个。", start: 100, end: 118),
        ], tail: "", closed: true)
        let english = LectureMoments.locate(in: [paragraph], near: 100, needle: "use a small model on the phone")
        #expect(english?.source == "So you should use a small model on the phone.")
        #expect(english?.translation == "所以你应该在手机上用小模型。", "the translation of that sentence, found by its time")
        #expect((english?.at ?? 0) > 105 && (english?.end ?? 200) < 116, "only that sentence's stretch of the commit")
        let chinese = LectureMoments.locate(in: [paragraph], near: 100, needle: "在手机上用小模型")
        #expect(chinese?.source == "So you should use a small model on the phone.", "a Chinese quote finds the English it translates")
    }
}

/// Finding a moment across a meeting's recordings, by their measured lengths.
struct MomentPlayerTests {
    @Test func aLateMomentIsFoundInTheFirstLongFile() {
        // The lecture behind the bug: 5809.5 s and 31.9 s of audio. The old estimate said 4609 s.
        let lengths = [5809.536, 31.872]
        #expect(MomentPlayer.locate(5810 - 1, in: lengths).map { $0.file } == 0)
        #expect(abs((MomentPlayer.locate(5749, in: lengths)?.offset ?? 0) - 5749) < 0.001)
        let second = MomentPlayer.locate(5815, in: lengths)
        #expect(second?.file == 1 && abs((second?.offset ?? 0) - 5.464) < 0.01)
        #expect(MomentPlayer.locate(9999, in: lengths)?.file == 1, "past the end plays the end of the last file")
        #expect(MomentPlayer.locate(10, in: []) == nil)
    }

    @Test func theWholeCitedPassagePlays() {
        #expect(MomentPlayer.length(from: 5810, until: 5845) == 35 + MomentPlayer.leadIn + MomentPlayer.tail, "all of a 35 s quote, not 10 s")
        #expect(MomentPlayer.length(from: 100, until: nil) == MomentPlayer.clipSeconds + MomentPlayer.leadIn)
        #expect(MomentPlayer.length(from: 0, until: 900) == MomentPlayer.longest)
    }
}
