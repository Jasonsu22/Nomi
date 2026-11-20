import Foundation

/// Who speaks in a recording: the teacher, you, and everyone else (classmates, guests).
///
/// After a recording, the voice pass (`VoiceAnalyzer`) groups the speech by voice and labels each
/// transcript line (commit) with the voice that said it. The voice that speaks most is taken as the
/// teacher; "This is the teacher" on any line changes that. "This is me" marks your own voice, which
/// is remembered (`MyVoice`) and found again in other lectures. Lines by any other voice are
/// classmates': greyed, hidden by "Teacher only", and marked for the AI. See docs/teacher-voice-plan.md.
struct MeetingVoices: Equatable, Codable, Sendable {
    /// The teacher's voice, one of `seconds`' keys.
    var teacher: String
    /// How long each voice speaks, in seconds.
    var seconds: [String: Double]
    var checkedAt: Date
    /// Each voice's voiceprint (256 numbers describing how it sounds), to find your voice again.
    var prints: [String: [Float]]? = nil
    /// Your own voice, if it is in this recording.
    var me: String? = nil
    /// You chose `me` here yourself (or said it isn't you), so matching your saved voice leaves it alone.
    var meChosen: Bool? = nil
    /// Names given to voices ("Jenny"), replacing "Speaker 3".
    var names: [String: String]? = nil

    /// The voices other than the teacher, most heard first: Speaker 2, Speaker 3, ….
    var others: [String] {
        seconds.keys.filter { $0 != teacher }.sorted {
            let a = seconds[$0] ?? 0, b = seconds[$1] ?? 0
            return a == b ? $0 < $1 : a > b
        }
    }

    /// The speaker number shown for a voice; the teacher is 1.
    func number(of speaker: String) -> Int {
        speaker == teacher ? 1 : (others.firstIndex(of: speaker) ?? others.count) + 2
    }

    /// What a voice is called in the transcript: its given name, Teacher, Me, Several people for a
    /// blended group, or Speaker N.
    func name(of speaker: String) -> String {
        if let given = names?[speaker]?.trimmingCharacters(in: .whitespacesAndNewlines), !given.isEmpty { return given }
        if speaker == teacher { return tr("老师") }
        if speaker == me { return tr("我") }
        if MyVoice.blends(in: prints ?? [:]).contains(speaker) { return tr("多人") }
        return trf("说话人 %d", number(of: speaker))
    }

    enum Side: Equatable { case teacher, me, classmate }

    /// Whose line `commit` is. Unlabelled lines count as the teacher's.
    func side(of commit: Commit) -> Side {
        guard let speaker = commit.speaker, speaker != teacher else { return .teacher }
        return speaker == me ? .me : .classmate
    }

    func isClassmate(_ commit: Commit) -> Bool { side(of: commit) == .classmate }

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

    /// The voice most heard in `paragraph` other than `excluding`; what "This is the teacher" or
    /// "This is me" on that paragraph refers to.
    static func mainVoice(in paragraph: Paragraph, excluding: String?) -> String? {
        var heard: [String: Double] = [:]
        for commit in paragraph.commits {
            guard let speaker = commit.speaker, speaker != excluding else { continue }
            heard[speaker, default: 0] += commit.end - commit.start
        }
        return MeetingVoices.mostHeard(heard)
    }

    /// The voice to make the teacher's when the student picks "This is the teacher" on a paragraph.
    static func voiceToPromote(in paragraph: Paragraph, voices: MeetingVoices) -> String? {
        mainVoice(in: paragraph, excluding: voices.teacher)
    }
}

/// Your own voice, remembered across lectures as a voiceprint once you pick "This is me". Kept on this
/// Mac only, in the app's settings; no audio is kept.
enum MyVoice {
    static let key = "lecturenote.myVoice"

    /// A voice matches yours when its voiceprint is at least this similar (cosine). In the English class
    /// of Nov 8, different people came out 0.13–0.56; a wrong match is fixed with "This isn't me".
    static let threshold: Float = 0.65
    /// And clearly closer than the next voice.
    static let lead: Float = 0.1

    static var print: [Float]? {
        get { (UserDefaults.standard.array(forKey: key) as? [NSNumber])?.map(\.floatValue) }
        set {
            if let newValue { UserDefaults.standard.set(newValue.map { NSNumber(value: $0) }, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        return na > 0 && nb > 0 ? dot / (na.squareRoot() * nb.squareRoot()) : 0
    }

    /// Your saved voice blended with a new sample of it, so it holds up across rooms and days.
    static func blended(_ old: [Float]?, with new: [Float]) -> [Float] {
        guard let old, old.count == new.count else { return unit(new) }
        let a = unit(old), b = unit(new)
        return unit(zip(a, b).map { 0.7 * $0 + 0.3 * $1 })
    }

    private static func unit(_ v: [Float]) -> [Float] {
        let n = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return n > 0 ? v.map { $0 / n } : v
    }

    /// A group whose voiceprint is this close to two or more other voices is a blend (people talking
    /// over each other, noise), not one person; in that class one such group was 0.69–0.78 from three others.
    static let blendBar: Float = 0.6

    /// Which of a recording's voices is yours, if any clearly is. The teacher's voice is never you,
    /// and neither is a blended group.
    /// The groups that are blends of several voices.
    static func blends(in prints: [String: [Float]]) -> Set<String> {
        Set(prints.keys.filter { key in
            prints.filter { $0.key != key && cosine($0.value, prints[key]!) >= blendBar }.count >= 2
        })
    }

    static func match(_ mine: [Float], in prints: [String: [Float]], teacher: String) -> String? {
        let blends = blends(in: prints)
        let scored = prints.filter { $0.key != teacher && !blends.contains($0.key) }
            .map { ($0.key, cosine(mine, $0.value)) }.sorted { $0.1 > $1.1 }
        guard let best = scored.first, best.1 >= threshold else { return nil }
        if scored.count > 1, best.1 - scored[1].1 < lead { return nil }
        return best.0
    }
}

extension Paragraph {
    /// The original text with a classmate's lines marked "[Student]" and yours "[Me]", for the AI.
    func renderedSourceMarkingStudents(language: String, voices: MeetingVoices?) -> String {
        guard let voices, commits.contains(where: { voices.side(of: $0) != .teacher }) else { return renderedSource(language: language) }
        var parts: [String] = []
        var run: [String] = []
        var side = MeetingVoices.Side.teacher
        var name = ""
        func flush() {
            guard !run.isEmpty else { return }
            let text = TranscriptText.join(run, language: sourceLanguage ?? language)
            switch side {
            case .teacher: parts.append(text)
            case .classmate: parts.append("[Student: \(name)] \(text) [/Student]")
            case .me: parts.append("[Me] \(text) [/Me]")
            }
            run = []
        }
        for commit in commits {
            let next = voices.side(of: commit)
            let nextName = commit.speaker.map(voices.name(of:)) ?? name
            if next != side || (next == .classmate && nextName != name) { flush(); side = next }
            name = nextName
            run.append(commit.source)
        }
        flush()
        return parts.joined(separator: " ")
    }
}
