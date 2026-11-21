import AVFoundation
@preconcurrency import FluidAudio
import Foundation
import OSLog

/// The live speaker models a student can download in Settings and choose between. All run on this
/// Mac through FluidAudio and Core ML. Tested on two of the user's own lectures (English class,
/// NLP class; docs/teacher-voice-plan.md): all three agreed with the after-recording pass 92–100%.
enum SpeakerModelKind: String, CaseIterable, Identifiable, Sendable {
    /// pyannote segmentation + WeSpeaker voiceprints with online clustering, in 5 s chunks.
    case standard
    /// NVIDIA Sortformer: end-to-end, good in noise, at most 4 voices.
    case sortformer
    /// NVIDIA Nemotron 3 diarization: end-to-end, up to 8 voices.
    case nemotron

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: tr("标准")
        case .sortformer: "Sortformer"
        case .nemotron: "Nemotron 3"
        }
    }

    var detail: String {
        switch self {
        case .standard: tr("最快、最小，测试中最准；标签约晚 5 秒出现。能记住你的声音。")
        case .sortformer: tr("噪音大的教室更稳；最多分出 4 个人。")
        case .nemotron: tr("最多分出 8 个人；比标准稍慢，偶尔会把老师标成别人。")
        }
    }

    /// Download size, from the models as cached on disk.
    var size: String {
        switch self {
        case .standard: "36 MB"
        case .sortformer: "236 MB"
        case .nemotron: "195 MB"
        }
    }

    /// Where FluidAudio keeps the model, under Application Support/FluidAudio/Models.
    var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
        switch self {
        case .standard: return base.appendingPathComponent("speaker-diarization", isDirectory: true)
        case .sortformer: return base.appendingPathComponent("sortformer", isDirectory: true)
        case .nemotron: return base.appendingPathComponent("nemotron-3-diarization", isDirectory: true)
        }
    }

    var isDownloaded: Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return !contents.isEmpty
    }

    /// Settings › Live speakers: on, and which model.
    static let enabledKey = "lecturenote.liveSpeakers"
    static let choiceKey = "lecturenote.liveSpeakerModel"

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var chosen: SpeakerModelKind {
        UserDefaults.standard.string(forKey: choiceKey).flatMap(SpeakerModelKind.init(rawValue:)) ?? .standard
    }

    /// Downloads (if needed) and loads the model, ready to listen.
    func load() async throws -> LiveSpeakerModel {
        switch self {
        case .standard:
            let models = try await DiarizerModels.downloadIfNeeded()
            var config = DiarizerConfig.default
            config.clusteringThreshold = StandardSpeakers.threshold
            config.chunkDuration = Float(StandardSpeakers.chunk)
            let manager = DiarizerManager(config: config)
            manager.initialize(models: models)
            return StandardSpeakers(manager: manager)
        case .sortformer:
            let models = try await SortformerModels.loadFromHuggingFace(config: .default, computeUnits: .cpuOnly)
            let diarizer = SortformerDiarizer(config: .default, timelineConfig: .sortformerDefault)
            diarizer.initialize(models: models)
            return TimelineSpeakers(diarizer: diarizer)
        case .nemotron:
            let config = Nemotron3Config.preset(named: "low") ?? Nemotron3Config.preset(named: "fast32")!
            let models = try await Nemotron3Models.loadFromHuggingFace(config: config, computeUnits: .all)
            return NemotronSpeakers(diarizer: Nemotron3Diarizer(config: config, models: models))
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}

/// One live model behind a common shape: feed audio, get who spoke when (seconds from the start of
/// this run). Called only on `LiveSpeakerTracker`'s queue.
protocol LiveSpeakerModel: AnyObject {
    func feed(_ samples: [Float]) throws -> [VoiceSpan]?
    /// Each voice's voiceprint, when the model has them (for "This is me").
    func prints() -> [String: [Float]]
}

/// pyannote + WeSpeaker with online clustering, a few seconds at a time. The tested settings:
/// 5 s chunks and a stricter 0.5 match (the default merged a classroom's students into the teacher).
final class StandardSpeakers: LiveSpeakerModel {
    static let threshold: Float = 0.5
    static let chunk: TimeInterval = 5

    private let manager: DiarizerManager
    private var buffer: [Float] = []
    private var consumed: TimeInterval = 0
    private var spans: [VoiceSpan] = []

    init(manager: DiarizerManager) { self.manager = manager }

    func feed(_ samples: [Float]) throws -> [VoiceSpan]? {
        buffer.append(contentsOf: samples)
        let size = Int(Self.chunk * 16_000)
        var changed = false
        while buffer.count >= size {
            let chunk = Array(buffer.prefix(size))
            buffer.removeFirst(size)
            let result = try manager.performCompleteDiarization(chunk, sampleRate: 16_000, atTime: consumed)
            spans += result.segments.map {
                VoiceSpan(start: TimeInterval($0.startTimeSeconds), end: TimeInterval($0.endTimeSeconds), speaker: "S\($0.speakerId)")
            }
            consumed += Self.chunk
            changed = true
        }
        return changed ? spans : nil
    }

    func prints() -> [String: [Float]] {
        var result: [String: [Float]] = [:]
        for (id, speaker) in manager.speakerManager.getAllSpeakers() { result["S\(id)"] = speaker.currentEmbedding }
        return result
    }
}

/// Sortformer, through FluidAudio's common streaming timeline.
final class TimelineSpeakers: LiveSpeakerModel {
    private let diarizer: SortformerDiarizer

    init(diarizer: SortformerDiarizer) { self.diarizer = diarizer }

    func feed(_ samples: [Float]) throws -> [VoiceSpan]? {
        guard try diarizer.process(samples: samples, sourceSampleRate: nil) != nil else { return nil }
        return diarizer.timeline.speakers.values.flatMap { speaker in
            speaker.finalizedSegments.map {
                VoiceSpan(start: TimeInterval($0.startTime), end: TimeInterval($0.endTime), speaker: "S\(speaker.index + 1)")
            }
        }
    }

    func prints() -> [String: [Float]] { [:] }
}

/// Nemotron 3: frame probabilities, turned into stretches of speech per voice.
final class NemotronSpeakers: LiveSpeakerModel {
    private let diarizer: Nemotron3Diarizer
    private var probabilities: [Float] = []
    private var frames = 0

    init(diarizer: Nemotron3Diarizer) { self.diarizer = diarizer }

    func feed(_ samples: [Float]) throws -> [VoiceSpan]? {
        diarizer.appendAudio(samples)
        let results = try diarizer.processBufferedAudio()
        guard !results.isEmpty else { return nil }
        for result in results {
            probabilities.append(contentsOf: result.probabilities)
            frames += result.frameCount
        }
        return Nemotron3Diarizer.segments(probabilities: probabilities, frameCount: frames).map {
            VoiceSpan(start: TimeInterval($0.startSeconds), end: TimeInterval($0.endSeconds), speaker: "S\($0.speakerIndex + 1)")
        }
    }

    func prints() -> [String: [Float]] { [:] }
}

/// Listens alongside a recording and reports who is speaking. Audio arrives on the audio thread;
/// the model runs on its own queue; updates reach the main actor about once a second. Times are on
/// the transcript's clock: `offset` is where this recording run starts in the meeting.
final class LiveSpeakerTracker: @unchecked Sendable {
    private static let logger = Logger(subsystem: "Nomi", category: "LiveSpeakers")

    let kind: SpeakerModelKind
    private let offset: TimeInterval
    private let tag: String
    private let queue = DispatchQueue(label: "nomi.live-speakers", qos: .userInitiated)
    private var model: LiveSpeakerModel?
    private var pending: [Float] = []
    private var stopped = false
    private var loadFailed = false
    /// A stop that came while the model was still loading; answered once it has heard everything.
    private var finishing: (@Sendable ([VoiceSpan], [String: [Float]]) -> Void)?
    private var lastSent = Date.distantPast
    private var latest: [VoiceSpan] = []
    private let onUpdate: @Sendable ([VoiceSpan], [String: [Float]]) -> Void

    /// `tag` keeps one run's voice labels apart from another's ("R2-S1").
    init(kind: SpeakerModelKind, offset: TimeInterval, tag: String, onUpdate: @escaping @Sendable ([VoiceSpan], [String: [Float]]) -> Void) {
        self.kind = kind
        self.offset = offset
        self.tag = tag
        self.onUpdate = onUpdate
    }

    /// Loads the model in the background; audio that arrives meanwhile waits for it.
    func start() {
        let kind = kind
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let model = try await kind.load()
                self?.queue.async {
                    guard let self, !self.stopped else { return }
                    self.model = model
                    self.drain(force: self.finishing != nil)
                    if let finishing = self.finishing { self.complete(finishing) }
                }
            } catch {
                Self.logger.error("Live speakers could not start: \(String(describing: error), privacy: .public)")
                self?.queue.async {
                    guard let self else { return }
                    self.loadFailed = true
                    if let finishing = self.finishing { self.complete(finishing) }
                }
            }
        }
    }

    /// From the audio thread: copy and hand over.
    func append(_ samples: UnsafeBufferPointer<Float>) {
        let copy = Array(samples)
        queue.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.pending.append(contentsOf: copy)
            if self.model != nil, self.pending.count >= 8_000 { self.drain() }
        }
    }

    /// Everything heard so far, then no more updates.
    func finish(_ done: @escaping @Sendable ([VoiceSpan], [String: [Float]]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            // Still loading: wait for the model, then let it hear what was recorded meanwhile.
            guard self.model != nil || self.loadFailed else { self.finishing = done; return }
            if self.model != nil { self.drain(force: true) }
            self.complete(done)
        }
    }

    private func complete(_ done: @Sendable ([VoiceSpan], [String: [Float]]) -> Void) {
        stopped = true
        finishing = nil
        done(latest, taggedPrints())
    }

    private func drain(force: Bool = false) {
        guard let model, !pending.isEmpty else { return }
        let samples = pending
        pending.removeAll(keepingCapacity: true)
        do {
            if let spans = try model.feed(samples) {
                latest = spans.map { VoiceSpan(start: $0.start + offset, end: $0.end + offset, speaker: "\(tag)\($0.speaker)") }
            }
        } catch {
            Self.logger.error("Live speakers failed: \(String(describing: error), privacy: .public)")
            return
        }
        if force || Date().timeIntervalSince(lastSent) >= 1 {
            lastSent = Date()
            onUpdate(latest, taggedPrints())
        }
    }

    private func taggedPrints() -> [String: [Float]] {
        guard let model else { return [:] }
        var result: [String: [Float]] = [:]
        for (key, print) in model.prints() { result["\(tag)\(key)"] = print }
        return result
    }
}
