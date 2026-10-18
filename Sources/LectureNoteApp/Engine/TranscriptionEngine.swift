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
    var onFinished: (@MainActor ([Paragraph], TimeInterval) -> Void)? { get set }
    func start()
    func stop()
    func togglePause()
}
