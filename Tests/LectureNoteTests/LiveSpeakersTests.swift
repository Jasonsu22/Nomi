import AVFoundation
import Foundation
import Testing
@testable import LectureNoteApp

/// Live speaker labels: lines take the voice heard while they were spoken, a resumed recording keeps
/// its teacher, and (on this Mac, with a lecture to replay) the app's own tracker labels real audio.
struct LiveSpeakersTests {
    private func lines() -> [Paragraph] {
        [Paragraph(id: 1, openedAt: 100, commits: [
            Commit(id: 1, source: "Teacher talks.", translation: "", start: 100, end: 108),
            Commit(id: 2, source: "A student answers.", translation: "", start: 108, end: 112),
            Commit(id: 3, source: "Earlier run.", translation: "", start: 10, end: 12, speaker: "R1-S1"),
        ], tail: "", closed: true)]
    }

    @Test func onlyLinesTheSpansCoverAreLabelled() {
        let spans = [VoiceSpan(start: 100, end: 108, speaker: "R2-S1"), VoiceSpan(start: 108.2, end: 112, speaker: "R2-S2")]
        let labelled = VoiceLabels.apply(spans, to: lines())[0].commits
        #expect(labelled.map(\.speaker) == ["R2-S1", "R2-S2", "R1-S1"], "an earlier run's label is left alone")
    }

    @Test func theFastLookupMatchesTheSimpleOne() {
        var spans: [VoiceSpan] = []
        for i in 0..<400 { spans.append(VoiceSpan(start: Double(i) * 3, end: Double(i) * 3 + 2.5, speaker: i % 7 == 0 ? "S2" : "S1")) }
        let sorted = spans.sorted { $0.start < $1.start }
        for start in stride(from: 0.0, to: 1200, by: 7.3) {
            let commit = Commit(id: 0, source: "", translation: "", start: start, end: start + 4)
            #expect(VoiceLabels.speaker(of: commit, sorted: sorted, longest: 2.5) == VoiceLabels.speaker(of: commit, in: spans))
        }
    }

    @Test func aResumedRecordingKeepsItsTeacher() {
        let prior = MeetingVoices(teacher: "R1-S1", seconds: ["R1-S1": 3000, "R1-S4": 60], checkedAt: .now)
        let spans = [VoiceSpan(start: 5000, end: 5100, speaker: "R2-S3"), VoiceSpan(start: 5100, end: 5110, speaker: "R2-S1")]
        let merged = VoiceLabels.merging(prior, spans: spans, prints: [:])
        #expect(merged?.voices.teacher == "R1-S1")
        #expect(merged?.spans.first?.speaker == "R1-S1", "this run's main voice is the same teacher")
        #expect(merged?.voices.seconds["R1-S1"] == 3100)
        #expect(merged?.voices.seconds["R2-S1"] == 10)
        let fresh = VoiceLabels.merging(nil, spans: spans, prints: [:])
        #expect(fresh?.voices.teacher == "R2-S3")
    }

    /// Replays a lecture through the app's live tracker in 0.1 s pieces, as the microphone would, and
    /// reports how many voices it found. Runs only when NOMI_LIVE_WAV names a 16 kHz mono file.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NOMI_LIVE_WAV"] != nil))
    func replayALectureThroughTheLiveTracker() async throws {
        let path = ProcessInfo.processInfo.environment["NOMI_LIVE_WAV"]!
        let kind = ProcessInfo.processInfo.environment["NOMI_LIVE_MODEL"].flatMap(SpeakerModelKind.init(rawValue:)) ?? .standard
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))

        let updates = UpdateCount()
        let tracker = LiveSpeakerTracker(kind: kind, offset: 0, tag: "R1-") { _, _ in updates.add() }
        tracker.start()
        try await Task.sleep(for: .seconds(3))  // the model loads while audio arrives
        let started = Date()
        var at = 0
        while at < samples.count {
            let end = min(at + 1_600, samples.count)
            samples[at..<end].withUnsafeBufferPointer { tracker.append($0) }
            at = end
        }
        let result: ([VoiceSpan], [String: [Float]]) = await withCheckedContinuation { done in
            tracker.finish { spans, prints in done.resume(returning: (spans, prints)) }
        }
        let seconds = Double(samples.count) / 16_000
        var talk: [String: Double] = [:]
        for span in result.0 { talk[span.speaker, default: 0] += span.end - span.start }
        let summary = talk.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key) \(Int($0.value))s" }.joined(separator: ", ")
        print("LIVE \(kind.rawValue): \(Int(seconds))s of audio in \(String(format: "%.1f", Date().timeIntervalSince(started)))s; \(updates.value) updates; voices: \(summary)")
        let out = ProcessInfo.processInfo.environment["NOMI_LIVE_OUT"]
        if let out {
            let rows = result.0.map { ["speaker": $0.speaker, "start": $0.start, "end": $0.end] as [String: Any] }
            try JSONSerialization.data(withJSONObject: ["segments": rows]).write(to: URL(fileURLWithPath: out))
        }
        #expect(talk.count >= 2, "a class has more than one voice")
    }
}

private final class UpdateCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
