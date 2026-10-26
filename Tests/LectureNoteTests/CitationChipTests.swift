import Foundation
import Testing
@testable import LectureNoteApp

/// Answers stay readable: a run of markers shows each source once, at most two,
/// and one meeting's chips name the moment instead of repeating its title.
@MainActor
struct CitationChipTests {
    private func chips(_ text: AttributedString) -> [String] {
        text.runs.compactMap { run in run.link == nil ? nil : String(text.characters[run.range]) }
    }

    private func citation(_ title: String, _ detail: String, meeting: UUID? = nil, source: UUID? = nil, passage: Int) -> ChatCitation {
        ChatCitation(title: title, detail: detail, meetingID: meeting, sourceID: source, passage: passage)
    }

    @Test func oneMeetingCitedThreeTimesShowsOneChipNamedByTheMoment() {
        let meeting = UUID()
        let map = [1: citation("Untitled Meeting", "8:41", meeting: meeting, passage: 1),
                   2: citation("Untitled Meeting", "8:51", meeting: meeting, passage: 2),
                   3: citation("Untitled Meeting", "9:02", meeting: meeting, passage: 3)]
        let text = AnswerInline.render("They grow in the gut. [1][2] [3]", citations: map)
        #expect(chips(text) == ["8:41"])
        #expect(!String(text.characters).contains("[2]"))
    }

    @Test func aSourceIsNotRepeatedLaterInTheSameParagraph() {
        let meeting = UUID()
        let map = [1: citation("Biology", "8:41", meeting: meeting, passage: 1),
                   2: citation("Biology", "9:02", meeting: meeting, passage: 2)]
        let text = AnswerInline.render("First point. [1] Second point. [2]", citations: map)
        #expect(chips(text).count == 1)
    }

    @Test func aRunShowsAtMostTwoDifferentSourcesByName() {
        let map = [1: citation("Biology", "8:41", meeting: UUID(), passage: 1),
                   2: citation("Slides.pdf", "p. 4", source: UUID(), passage: 2),
                   3: citation("Reading.pdf", "p. 9", source: UUID(), passage: 3)]
        let text = AnswerInline.render("A claim. [1], [2]、[3]", citations: map)
        #expect(chips(text) == ["Biology", "Slides.pdf"])
    }
}
