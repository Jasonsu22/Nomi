import Foundation

@MainActor
protocol TranscriptionEngine: AnyObject {
    var transcript: LiveTranscript { get }
    var level: LevelMeter { get }
    var session: SessionState { get }
    var loadError: String? { get }
    var sourceLanguage: String { get set }
    var onFinished: (@MainActor ([Paragraph], TimeInterval) -> Void)? { get set }
    func start()
    func stop()
    func togglePause()
}
