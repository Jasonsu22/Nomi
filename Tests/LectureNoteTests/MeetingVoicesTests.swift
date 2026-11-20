import Foundation
import Testing
@testable import LectureNoteApp

/// Telling the teacher from classmates: labelling lines from the voice pass, and what the AI sees.
struct MeetingVoicesTests {
    private func paragraph() -> Paragraph {
        Paragraph(id: 1, openedAt: 850, commits: [
            Commit(id: 1, source: "Today we talk about nerves.", translation: "今天讲紧张。", start: 850, end: 858),
            Commit(id: 2, source: "I usually get nervous in front of so many people.", translation: "我在很多人面前通常会紧张。", start: 859, end: 866),
            Commit(id: 3, source: "Okay. You know your work, right? I feel nervous too.", translation: "好。你了解你的工作。我也紧张。", start: 866, end: 880),
            Commit(id: 4, source: "Yes.", translation: "是。", start: 880, end: 880.2),
        ], tail: "", closed: true)
    }

    // The English class of Nov 8, around 14:20: the teacher (S1) and a student (S2).
    private let spans = [
        VoiceSpan(start: 850, end: 858, speaker: "S1"),
        VoiceSpan(start: 859.2, end: 866, speaker: "S2"),
        VoiceSpan(start: 866, end: 874, speaker: "S1"),
        VoiceSpan(start: 874, end: 880, speaker: "S2"),
        VoiceSpan(start: 880, end: 880.2, speaker: "S2"),
        VoiceSpan(start: 0, end: 600, speaker: "S1"),
    ]

    @Test func linesTakeTheVoiceThatSaysMostOfThem() {
        let result = VoiceLabels.label([paragraph()], spans: spans)
        #expect(result?.voices.teacher == "S1", "the voice heard most is the teacher")
        let commits = result?.paragraphs[0].commits ?? []
        #expect(commits.map(\.speaker) == ["S1", "S2", nil, nil])
        #expect(result?.voices.isClassmate(commits[1]) == true)
        #expect(result?.voices.isClassmate(commits[2]) == false, "a line with both voices stays the teacher's")
        #expect(result?.voices.isClassmate(commits[3]) == false, "too short to tell")
    }

    @Test func noSpeechMeansNoLabels() {
        #expect(VoiceLabels.label([paragraph()], spans: []) == nil)
    }

    @Test func choosingTheTeacherSwapsTheLabels() {
        guard let result = VoiceLabels.label([paragraph()], spans: spans) else { Issue.record("no labels"); return }
        #expect(VoiceLabels.voiceToPromote(in: result.paragraphs[0], voices: result.voices) == "S2")
        var swapped = result.voices
        swapped.teacher = "S2"
        #expect(swapped.isClassmate(result.paragraphs[0].commits[0]))
        #expect(!swapped.isClassmate(result.paragraphs[0].commits[1]))
    }

    @Test func theAIIsToldWhichWordsAreAStudents() {
        guard let result = VoiceLabels.label([paragraph()], spans: spans) else { Issue.record("no labels"); return }
        let text = result.paragraphs[0].renderedSourceMarkingStudents(language: "en", voices: result.voices)
        #expect(text.hasPrefix("Today we talk about nerves. [Student] I usually get nervous in front of so many people. [/Student] Okay."))
        #expect(paragraph().renderedSourceMarkingStudents(language: "en", voices: nil) == paragraph().renderedSource(language: "en"))
        #expect(ChatContext.systemPrompt(language: "Chinese", allowsWeb: false).contains("[Student]"))
    }

    @Test func oldMeetingsAndLinesStillLoad() throws {
        let commit = try JSONDecoder().decode(Commit.self, from: Data(#"{"id":1,"source":"a","translation":"b","start":0,"end":1}"#.utf8))
        #expect(commit.speaker == nil)
        var meeting = Meeting.live(sourceLanguage: "en", targetLanguage: "zh")
        meeting.voices = MeetingVoices(teacher: "S1", seconds: ["S1": 10], checkedAt: .now)
        let again = try JSONDecoder().decode(Meeting.self, from: JSONEncoder().encode(meeting))
        #expect(again.voices?.teacher == "S1")
    }
}
