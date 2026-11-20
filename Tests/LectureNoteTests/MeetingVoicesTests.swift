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
        #expect(text.hasPrefix("Today we talk about nerves. [Student: \(tr("说话人 %d").replacingOccurrences(of: "%d", with: "2"))] I usually get nervous in front of so many people. [/Student] Okay."))
        #expect(paragraph().renderedSourceMarkingStudents(language: "en", voices: nil) == paragraph().renderedSource(language: "en"))
        #expect(ChatContext.systemPrompt(language: "Chinese", allowsWeb: false).contains("[Student: name]"))
    }

    @Test func oldMeetingsAndLinesStillLoad() throws {
        let commit = try JSONDecoder().decode(Commit.self, from: Data(#"{"id":1,"source":"a","translation":"b","start":0,"end":1}"#.utf8))
        #expect(commit.speaker == nil)
        var meeting = Meeting.live(sourceLanguage: "en", targetLanguage: "zh")
        meeting.voices = MeetingVoices(teacher: "S1", seconds: ["S1": 10], checkedAt: .now)
        let again = try JSONDecoder().decode(Meeting.self, from: JSONEncoder().encode(meeting))
        #expect(again.voices?.teacher == "S1")
    }

    @Test func yourLinesAreYoursAndMarkedForTheAI() {
        guard var result = VoiceLabels.label([paragraph()], spans: spans) else { Issue.record("no labels"); return }
        #expect(VoiceLabels.mainVoice(in: result.paragraphs[0], excluding: result.voices.teacher) == "S2")
        result.voices.me = "S2"
        let commits = result.paragraphs[0].commits
        #expect(result.voices.side(of: commits[0]) == .teacher)
        #expect(result.voices.side(of: commits[1]) == .me)
        #expect(!result.voices.isClassmate(commits[1]), "your lines are not a classmate's")
        let text = result.paragraphs[0].renderedSourceMarkingStudents(language: "en", voices: result.voices)
        #expect(text.contains("[Me] I usually get nervous in front of so many people. [/Me]"))
        #expect(ChatContext.studentRule.contains("[Me]"))
    }

    @Test func yourSavedVoiceIsFoundOnlyWhenItClearlyMatches() {
        let me: [Float] = [1, 0, 0, 0]
        let prints: [String: [Float]] = [
            "S1": [0, 0, 1, 0],          // the teacher
            "S2": [0.9, 0.3, 0, 0],      // you, in another room
            "S3": [0.4, 0, 0, 0.9],      // a classmate (about 0.4 similar, like the class measured)
        ]
        #expect(MyVoice.match(me, in: prints, teacher: "S1") == "S2")
        #expect(MyVoice.match(me, in: ["S1": [1, 0, 0, 0], "S3": [0.4, 0, 0, 0.9]], teacher: "S1") == nil, "the teacher is never you, and nobody else is close enough")
        #expect(MyVoice.match(me, in: ["S1": [0, 1, 0, 0], "S2": [0.9, 0.3, 0, 0], "S4": [0.88, 0.32, 0.05, 0]], teacher: "S1") == nil, "two voices too alike to choose")
        // A blend of several voices (overlapping speech) is never taken as you, however close.
        let withBlend: [String: [Float]] = [
            "S1": [0, 0, 1, 0], "S2": [0.9, 0.3, 0, 0], "S4": [0.3, 0.9, 0.3, 0],
            "S7": [0.7, 0.7, 0.3, 0],
        ]
        #expect(MyVoice.match([0.75, 0.65, 0.2, 0], in: withBlend, teacher: "S1") != "S7")
        let blended = MyVoice.blended([1, 0, 0, 0], with: [0, 1, 0, 0])
        #expect(MyVoice.cosine(blended, [1, 0, 0, 0]) > MyVoice.cosine(blended, [0, 1, 0, 0]), "the saved voice moves only a little")
    }

    @Test func speakersAreNumberedByHowMuchTheySpeakAndCanBeNamed() {
        var voices = MeetingVoices(teacher: "S1", seconds: ["S1": 6956, "S2": 524, "S3": 167, "S7": 892], checkedAt: .now)
        #expect(voices.others == ["S7", "S2", "S3"])
        #expect(voices.number(of: "S1") == 1 && voices.number(of: "S7") == 2 && voices.number(of: "S3") == 4)
        #expect(voices.name(of: "S1") == tr("老师"))
        #expect(voices.name(of: "S2") == trf("说话人 %d", 3))
        voices.me = "S2"
        #expect(voices.name(of: "S2") == tr("我"))
        voices.names = ["S3": "Jenny"]
        #expect(voices.name(of: "S3") == "Jenny")
        // A group close to two other voices is a blend, shown as several people.
        voices.prints = ["S1": [0, 0, 1, 0], "S2": [1, 0, 0, 0], "S3": [0, 1, 0, 0], "S7": [0.7, 0.7, 0.2, 0]]
        #expect(voices.name(of: "S7") == tr("多人"))
    }

    @Test func eachClassmateKeepsTheirOwnNameForTheAI() {
        var p = paragraph()
        p.commits[0].speaker = "S2"
        p.commits[1].speaker = "S3"
        let voices = MeetingVoices(teacher: "S1", seconds: ["S1": 100, "S2": 20, "S3": 10], checkedAt: .now, names: ["S3": "Jenny"])
        let text = p.renderedSourceMarkingStudents(language: "en", voices: voices)
        #expect(text.contains("[Student: Jenny] I usually get nervous"))
        #expect(text.hasPrefix("[Student: \(trf("说话人 %d", 2))] Today we talk about nerves. [/Student] [Student: Jenny]"))
    }
}

