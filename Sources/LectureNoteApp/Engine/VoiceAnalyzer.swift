import AVFoundation
@preconcurrency import FluidAudio
import Foundation
import OSLog

/// Finds who speaks when in a finished recording, with FluidAudio's offline diarization on Core ML
/// (about 100× faster than real time on Apple silicon). The models, about 20 MB, download once from
/// Hugging Face into Application Support/FluidAudio. Nothing leaves the Mac.
actor VoiceAnalyzer {
    static let shared = VoiceAnalyzer()
    private static let logger = Logger(subsystem: "Nomi", category: "VoiceAnalyzer")

    private var manager: OfflineDiarizerManager?

    enum Failure: LocalizedError {
        case noAudio
        var errorDescription: String? { tr("这场会议没有保存录音，无法识别声音。") }
    }

    /// The stretches of speech in a meeting's recordings, with times on the transcript's clock. A
    /// meeting recorded in several runs keeps one file per run; they are joined in order first, so
    /// a voice keeps one label across them.
    /// The stretches of speech, and each voice's voiceprint (to find your voice again).
    func spans(meetingID: UUID, audioFiles: [String]) async throws -> (spans: [VoiceSpan], prints: [String: [Float]]) {
        let folder = MeetingStore.audioDirectory(for: meetingID)
        let urls = audioFiles.map { folder.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { throw Failure.noAudio }
        let joined = FileManager.default.temporaryDirectory.appendingPathComponent("nomi-voices-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: joined) }
        try Self.join(urls, into: joined)
        try Task.checkCancellation()

        let manager = try await readyManager()
        let started = Date()
        let result = try await manager.process(joined)
        Self.logger.notice("Voices: \(result.segments.count, privacy: .public) stretches in \(Date().timeIntervalSince(started), privacy: .public) s")
        let spans = result.segments.map {
            VoiceSpan(start: TimeInterval($0.startTimeSeconds), end: TimeInterval($0.endTimeSeconds), speaker: $0.speakerId)
        }
        return (spans, result.speakerDatabase ?? [:])
    }

    private func readyManager() async throws -> OfflineDiarizerManager {
        if let manager { return manager }
        let manager = OfflineDiarizerManager()
        try await manager.prepareModels()
        self.manager = manager
        return manager
    }

    /// Writes the recordings one after another into one 16 kHz mono WAV, a few seconds at a time.
    private static func join(_ urls: [URL], into output: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ]
        let writer = try AVAudioFile(forWriting: output, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        for url in urls {
            let reader = try AVAudioFile(forReading: url)
            let converter = reader.processingFormat == format ? nil : AVAudioConverter(from: reader.processingFormat, to: format)
            let chunk = AVAudioFrameCount(reader.processingFormat.sampleRate * 10)
            while reader.framePosition < reader.length {
                try Task.checkCancellation()
                guard let input = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: chunk) else { break }
                try reader.read(into: input, frameCount: chunk)
                guard input.frameLength > 0 else { break }
                if let converter {
                    let ratio = format.sampleRate / reader.processingFormat.sampleRate
                    guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024) else { break }
                    var fed = false
                    var error: NSError?
                    converter.convert(to: out, error: &error) { _, status in
                        if fed { status.pointee = .noDataNow; return nil }
                        fed = true
                        status.pointee = .haveData
                        return input
                    }
                    if let error { throw error }
                    try writer.write(from: out)
                } else {
                    try writer.write(from: input)
                }
            }
        }
    }
}

/// Settings › Recording & Translation › Mark classmates' voices. On by default.
enum ClassmateVoicesPreference {
    static let key = "lecturenote.classmateVoices"
    static var isOn: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }
}
