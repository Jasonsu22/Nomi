import Foundation
import Testing
@testable import LectureNoteApp

/// Following the end of a chat, keeping a steered-away question, and how the model is told to cite.
struct ChatFollowAndCiteTests {
    private func at(_ bottom: CGFloat, of height: CGFloat) -> ChatFollow.Geometry {
        ChatFollow.Geometry(visibleBottom: bottom, contentHeight: height)
    }

    @Test func atTheEndNewTextPullsTheViewAlong() {
        var follow = ChatFollow()
        let r1 = follow.update(from: at(800, of: 800), to: at(800, of: 1600))
        #expect(r1, "a long answer keeps the view at its end")
        let r2 = follow.update(from: at(1600, of: 1600), to: at(1600, of: 2400))
        #expect(r2)
        #expect(!follow.showsJumpButton)
    }

    @Test func scrolledUpTheViewStaysAndOffersAJump() {
        var follow = ChatFollow()
        let r3 = follow.update(from: at(1600, of: 1600), to: at(900, of: 1600))
        #expect(!r3, "the student scrolled up")
        #expect(follow.showsJumpButton && !follow.unseen)
        let r4 = follow.update(from: at(900, of: 1600), to: at(900, of: 2200))
        #expect(!r4, "new text does not pull them down")
        #expect(follow.unseen, "the button says a new answer is waiting")
        let r5 = follow.update(from: at(900, of: 2200), to: at(2180, of: 2200))
        #expect(!r5, "scrolling back near the end follows again")
        #expect(follow.following && !follow.unseen && !follow.showsJumpButton)
        follow.following = false
        follow.jumpToEnd()
        #expect(follow.following)
    }

    @Test func aQuestionInterruptedBeforeAnyAnswerStillReachesTheModel() {
        var interrupted = ChatTurn(question: "pre 要讲什么？", answer: "", modelName: "m")
        interrupted.interrupted = true
        let empty = ChatTurn(question: "失败的", answer: "", modelName: "m")
        let answered = ChatHistory.answeredTurns([interrupted, empty])
        #expect(answered.map(\.question) == ["pre 要讲什么？"])
        let text = ChatHistory.rendered(interrupted, answerLimit: 400, dated: false)
        #expect(text.contains("Question: pre 要讲什么？"))
        #expect(text.contains("interrupted before any answer"))
        #expect(ChatContext.steerNote.contains("previous question still stands"))
    }

    @Test func aModelThatMustSearchIsToldToCiteByNumber() {
        let searching = ChatContext.systemPrompt(language: "Chinese", allowsWeb: false, hasPassages: false, tools: true, library: .available)
        #expect(searching.contains("like [3]"), "the rule must be there before the search, since the system prompt is fixed for the answer")
        #expect(searching.contains("never write a source's title, date, timestamp"))
        #expect(!searching.contains("Answer from general knowledge"))
        let offline = ChatContext.systemPrompt(language: "Chinese", allowsWeb: false, hasPassages: false)
        #expect(offline.contains("Answer from general knowledge"))
        let block = ContextBlock(title: "英语课转写", detail: "2026-11-08 · 32:35", body: "Think about purpose and context.")
        let next = ChatContext.continuationPrompt(newBlocks: [block], startingAt: 4, webFinished: false, libraryFinished: true, draftEmpty: true, searchFailed: false)
        #expect(next.contains("[5] 英语课转写"))
        #expect(next.contains("only by their bracketed numbers, like [5]"))
    }
}
