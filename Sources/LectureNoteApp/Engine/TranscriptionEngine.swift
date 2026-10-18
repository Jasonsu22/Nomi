import Foundation

enum EngineReadiness: Equatable {
    case preview
    case preparing
    case ready
    case sourceOnly
    case asrMissing
    case unavailable
}

@MainActor
protocol TranscriptionEngine: AnyObject {
    var transcript: LiveTranscript { get }
    var level: LevelMeter { get }
    var session: SessionState { get }
    var loadError: String? { get }
    var readiness: EngineReadiness { get }
    var canStart: Bool { get }
    var sourceLanguage: String { get set }
    var targetLanguage: String { get set }
    var inputDeviceUID: String? { get set }
    var recordingURL: URL? { get set }
    var onFinished: (@MainActor ([Paragraph], TimeInterval) -> Void)? { get set }
    func start(resuming paragraphs: [Paragraph], at offset: TimeInterval)
    func stop()
    func togglePause()
}

extension TranscriptionEngine {
    func start() { start(resuming: [], at: 0) }
}
