import Foundation
import Testing
@testable import LectureNoteApp

/// Transcripts where the speech model looped on one word, like "Okay." hundreds of times.
struct RepeatCleanupTests {
    @Test func aWordSaidHundredsOfTimesIsKeptOnce() {
        let looped = "Can you tell the first thing? " + String(repeating: "Okay. ", count: 300)
        #expect(RepeatCleanup.collapse(looped) == "Can you tell the first thing? Okay.")
    }

    @Test func aLoopingPhraseIsKeptOnceAndWhatFollowsStays() {
        let looped = String(repeating: "you can see the summary, ", count: 8) + "and then we start."
        #expect(RepeatCleanup.collapse(looped) == "you can see the summary, and then we start.")
        #expect(RepeatCleanup.collapse("好的，" + String(repeating: "对", count: 40) + "下一题") == "好的，对下一题")
        #expect(RepeatCleanup.collapse(String(repeating: "我们看一下。", count: 20)) == "我们看一下。")
    }

    @Test func ordinaryEmphasisIsLeftAlone() {
        for text in ["It is very very very important.", "No, no, no, that's not it.", "Okay. Okay. Let's start.", "对对对，就是这个。", "哈哈哈", "The the cat.", "啊，Ielts，雅思，雅思，雅思，雅思，那种文科音。", "到到到，到到到，"] {
            #expect(RepeatCleanup.collapse(text) == text, "\(text)")
        }
    }

    private func line(_ id: Int, _ text: String) -> Commit {
        Commit(id: id, source: text, translation: "", start: Double(id), end: Double(id) + 1)
    }

    @Test func savedTranscriptsAreCleaned() throws {
        let looped = Paragraph(id: 1, openedAt: 0, commits: [
            line(1, "What was the summary?"),
            line(2, String(repeating: "Okay. ", count: 200)),
            line(3, "Okay."), line(4, "Okay."), line(5, "Okay."), line(6, "Okay."),
            line(7, "Next question."),
        ], tail: "", closed: true)
        let cleaned = try #require(RepeatCleanup.cleaned([looped]))
        #expect(cleaned[0].commits.map(\.source) == ["What was the summary?", "Okay.", "Okay.", "Okay.", "Next question."])
        let fine = Paragraph(id: 2, openedAt: 0, commits: [line(1, "Okay."), line(2, "Let's begin.")], tail: "", closed: true)
        #expect(RepeatCleanup.cleaned([fine]) == nil, "nothing to clean leaves the meeting untouched")
    }
}
