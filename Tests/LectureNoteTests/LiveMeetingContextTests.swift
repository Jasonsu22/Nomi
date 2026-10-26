import Foundation
import Testing
@testable import LectureNoteApp

/// Chat, summaries and search read the class being recorded from the live transcript.
/// They used to read the empty copy from before the recording, so answers came from older lectures.
@MainActor
struct LiveMeetingContextTests {
    @Test func theRecordingMeetingReadsTheLiveTranscript() throws {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        model.startTranscription(title: "Biology")
        let id = try #require(model.recordingMeetingID)
        model.engine.transcript.applyCommit(
            Commit(id: 900, source: "Are there any concerns you'd like to discuss?", translation: "", start: 619, end: 622),
            tail: "",
            reduceMotion: true
        )
        let stored = try #require(model.meetings.first { $0.id == id })
        let live = model.current(stored)
        let text = live.paragraphs.map { $0.renderedSource(language: "en") }.joined(separator: " ")
        #expect(text.contains("concerns you'd like to discuss"))
    }

    @Test func otherMeetingsAreReadAsSaved() {
        var past = Meeting.live(sourceLanguage: "en", targetLanguage: "zh")
        past.isLive = false
        let model = AppModel(engine: ReplayEngine(), meetings: [past], categories: [])
        #expect(model.current(past) == past)
    }
}
