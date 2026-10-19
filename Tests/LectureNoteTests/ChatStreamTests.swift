import Foundation
import Testing
@testable import LectureNoteApp

struct ChatStreamTests {
    @Test func thinkBlockStaysHiddenUntilItCloses() {
        #expect(ChatStream.visible("<think>先想一下") == "")
        #expect(ChatStream.visible("<think>先想一下</think>\n结论") == "结论")
        #expect(ChatStream.visible("直接回答") == "直接回答")
    }

    @Test func openAIDeltaShowsContentAndKeepsReasoningAside() {
        var stream = ChatStream.Accumulator()
        #expect(stream.apply([
            "choices": [["delta": ["reasoning_content": "内部", "content": "你"]]],
        ]) == nil)
        #expect(stream.display == "你")
        #expect(stream.apply([
            "choices": [["delta": ["content": "好"], "finish_reason": "stop"]],
        ]) == nil)
        stream.finished = true
        #expect(stream.answer == "你好")
    }

    @Test func anthropicTextAndCitationArriveAsSeparateEvents() {
        var stream = ChatStream.Accumulator()
        #expect(stream.apply([
            "type": "content_block_delta",
            "delta": ["type": "text_delta", "text": "答案"],
        ]) == nil)
        #expect(stream.apply([
            "type": "content_block_delta",
            "delta": ["type": "citations_delta", "citation": ["title": "来源", "url": "https://example.com"]],
        ]) == nil)
        #expect(stream.apply(["type": "message_stop"]) == nil)
        #expect(stream.answer == "答案\n来源 https://example.com")
    }

    @Test func localSnapshotReplacesTheVisibleAnswer() {
        var stream = ChatStream.Accumulator()
        #expect(stream.apply(["text": "你"]) == nil)
        #expect(stream.apply(["text": "你好"]) == nil)
        #expect(stream.display == "你好")
        #expect(stream.apply(["done": true, "text": "你好。"]) == nil)
        #expect(stream.answer == "你好。")
    }

    @Test func doneLineEndsTheEvent() {
        #expect(ChatStream.line("data: [DONE]") == .done)
        if case .payload(let payload) = ChatStream.line("data: {\"text\":\"你\"}") {
            #expect(payload == "{\"text\":\"你\"}")
        } else {
            Issue.record("expected a payload")
        }
    }
}
