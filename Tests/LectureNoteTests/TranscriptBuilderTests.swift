import Foundation
import Testing
@testable import LectureNoteApp

struct TranscriptBuilderTests {
    @Test func tailReplacesWithinTheSameParagraph() {
        var builder = TranscriptBuilder()
        #expect(builder.applyTail(text: "今天", start: 0) == .paragraphOpened)
        #expect(builder.applyTail(text: "今天我们", start: 0) == .tailReplaced)
        #expect(builder.paragraphs.count == 1)
        #expect(builder.paragraphs[0].id == 1)
        #expect(builder.paragraphs[0].tail == "今天我们")
    }

    @Test func pauseOpensANewParagraph() {
        var builder = TranscriptBuilder()
        builder.applyTail(text: "第一句", start: 0)
        builder.applyCommit(
            Commit(id: 1, source: "第一句", translation: "First.", start: 0, end: 1.2),
            tail: ""
        )
        builder.applyTail(text: "隔了很久", start: 4)
        #expect(builder.paragraphs.count == 2)
        #expect(builder.paragraphs[0].closed)
        #expect(builder.paragraphs[0].tail.isEmpty)
        #expect(builder.paragraphs[1].tail == "隔了很久")
    }

    @Test func longSentenceClosesTheParagraphAndKeepsTheRemainder() {
        var builder = TranscriptBuilder()
        let unit = "注意力决定模型看向哪里。"
        let sentence = String(repeating: unit, count: (TranscriptBuilder.maxCharacters / unit.count) + 1)
        #expect(sentence.count >= 200)
        builder.applyTail(text: "起", start: 0)
        builder.applyCommit(
            Commit(id: 1, source: sentence, translation: "Attention.", start: 0, end: 8),
            tail: "下一"
        )
        #expect(builder.paragraphs.count == 2)
        #expect(builder.paragraphs[0].closed)
        #expect(builder.paragraphs[0].tail.isEmpty)
        #expect(builder.paragraphs[0].source == sentence)
        #expect(builder.paragraphs[1].tail == "下一")
    }

    @Test func sampleLectureBecomesSeparateParagraphs() throws {
        let events = try SampleLecture.load()
        var builder = TranscriptBuilder()
        for event in events {
            switch event.kind {
            case .tail(let text, let start, _):
                builder.applyTail(text: text, start: start)
            case .commit(let commit, let tail):
                builder.applyCommit(commit, tail: tail)
            }
        }
        #expect(events.count > 10)
        #expect(builder.paragraphs.count >= 2)
        #expect(builder.paragraphs[0].closed)
        #expect(builder.paragraphs[0].source.count >= 200)
        let spoken = builder.paragraphs.map(\.source).joined()
        #expect(spoken.contains("注意力机制"))
        #expect(spoken.contains("垫子"))
        #expect(builder.paragraphs.allSatisfy { $0.tail.isEmpty })
    }
}
