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

    @Test func englishCommitsKeepSpacesAndChineseTranslationsDoNot() {
        var builder = TranscriptBuilder()
        builder.sourceLanguage = "en"
        builder.applyCommit(
            Commit(id: 1, source: "Hello", translation: " 你好", start: 0, end: 1),
            tail: ""
        )
        builder.applyCommit(
            Commit(id: 2, source: " world", translation: "世界", start: 1, end: 2),
            tail: ""
        )
        let paragraph = builder.paragraphs[0]
        #expect(paragraph.renderedSource(language: "en") == "Hello world")
        #expect(paragraph.renderedTranslation(language: "zh") == "你好世界")
        #expect(!paragraph.closed)
    }

    @Test func englishFullStopClosesALongParagraph() {
        var builder = TranscriptBuilder()
        builder.sourceLanguage = "en"
        let sentence = String(repeating: "word ", count: 120).trimmingCharacters(in: .whitespaces) + "."
        #expect(sentence.count >= TranscriptBuilder.spacedCharacterLimit)
        builder.applyCommit(
            Commit(id: 1, source: sentence, translation: "", start: 0, end: 8),
            tail: "Next"
        )
        #expect(builder.paragraphs.count == 2)
        #expect(builder.paragraphs[0].closed)
        #expect(builder.paragraphs[1].tail == "Next")
    }

    @Test func shortEnglishSentenceStaysOpen() {
        var builder = TranscriptBuilder()
        builder.sourceLanguage = "en"
        let sentence = String(repeating: "word ", count: 40).trimmingCharacters(in: .whitespaces) + "."
        #expect(sentence.count < TranscriptBuilder.spacedCharacterLimit)
        #expect(sentence.count >= TranscriptBuilder.maxCharacters)
        builder.applyCommit(
            Commit(id: 1, source: sentence, translation: "", start: 0, end: 4),
            tail: ""
        )
        #expect(builder.paragraphs.count == 1)
        #expect(!builder.paragraphs[0].closed)
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
