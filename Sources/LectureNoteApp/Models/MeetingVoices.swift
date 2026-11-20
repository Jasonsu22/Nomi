import Foundation

/// Who speaks in a recording: the teacher, and everyone else (classmates, guests).
///
/// After a recording, the voice pass (`VoiceAnalyzer`) groups the speech by voice and labels each
/// transcript line (commit) with the voice that said it. The voice that speaks most is taken as the
/// teacher; "This is the teacher" on any line changes that. Lines by any other voice are classmates':
/// shown greyed, hidden by "Teacher only", and marked for the AI. See docs/teacher-voice-plan.md.
struct MeetingVoices: Equatable, Codable, Sendable {
    /// The teacher's voice, one of `seconds`' keys.
    var teacher: String
    /// How long each voice speaks, in seconds.
    var seconds: [String: Double]
    var checkedAt: Date

    /// Whether `commit` was said by someone other than the teacher. Unlabelled lines count as the teacher's.
    func isClassmate(_ commit: Commit) -> Bool {
        guard let speaker = commit.speaker else { return false }
        return speaker != teacher
    }

    /// The voice that speaks most.
    static func mostHeard(_ seconds: [String: Double]) -> String? {
        seconds.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
    }
}

/// One stretch of speech by one voice, in seconds from the start of the recording.
struct VoiceSpan: Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var speaker: String
}

enum VoiceLabels {
    /// A line gets a voice only when that voice says at least this share of its speech. Long chunks
    /// often mix the teacher and a student; those stay unlabelled (the teacher's) rather than guess.
    static let share = 0.7
    /// Less speech than this is too little to tell voices apart.
    static let minimumSpeech: TimeInterval = 0.4

    /// The voice of each line, or nil when it is unclear.
    static func speaker(of commit: Commit, in spans: [VoiceSpan]) -> String? {
        var heard: [String: Double] = [:]
        for span in spans where span.end > commit.start && span.start < commit.end {
            heard[span.speaker, default: 0] += min(span.end, commit.end) - max(span.start, commit.start)
        }
        let total = heard.values.reduce(0, +)
        guard total >= minimumSpeech, let top = MeetingVoices.mostHeard(heard), heard[top, default: 0] / total >= share else { return nil }
        return top
    }

    /// Labels every line of `paragraphs` and works out who the teacher is. Nil when no speech was found.
    static func label(_ paragraphs: [Paragraph], spans: [VoiceSpan], now: Date = .now) -> (paragraphs: [Paragraph], voices: MeetingVoices)? {
        var seconds: [String: Double] = [:]
        for span in spans { seconds[span.speaker, default: 0] += max(0, span.end - span.start) }
        guard let teacher = MeetingVoices.mostHeard(seconds) else { return nil }
        let sorted = spans.sorted { $0.start < $1.start }
        var labelled = paragraphs
        for p in labelled.indices {
            for c in labelled[p].commits.indices {
                labelled[p].commits[c].speaker = speaker(of: labelled[p].commits[c], in: sorted)
            }
        }
        return (labelled, MeetingVoices(teacher: teacher, seconds: seconds, checkedAt: now))
    }

    /// The voice to make the teacher's when the student picks "This is the teacher" on a paragraph:
    /// the non-teacher voice heard most in it.
    static func voiceToPromote(in paragraph: Paragraph, voices: MeetingVoices) -> String? {
        var heard: [String: Double] = [:]
        for commit in paragraph.commits {
            guard let speaker = commit.speaker, speaker != voices.teacher else { continue }
            heard[speaker, default: 0] += commit.end - commit.start
        }
        return MeetingVoices.mostHeard(heard)
    }
}

extension Paragraph {
    /// The original text with a classmate's lines marked "[Student]", for the AI.
    func renderedSourceMarkingStudents(language: String, voices: MeetingVoices?) -> String {
        guard let voices, commits.contains(where: voices.isClassmate) else { return renderedSource(language: language) }
        var parts: [String] = []
        var run: [String] = []
        var runIsStudent = false
        func flush() {
            guard !run.isEmpty else { return }
            let text = TranscriptText.join(run, language: sourceLanguage ?? language)
            parts.append(runIsStudent ? "[Student] \(text) [/Student]" : text)
            run = []
        }
        for commit in commits {
            let student = voices.isClassmate(commit)
            if student != runIsStudent { flush(); runIsStudent = student }
            run.append(commit.source)
        }
        flush()
        return parts.joined(separator: " ")
    }
}
