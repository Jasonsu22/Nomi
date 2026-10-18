import Foundation

@MainActor
protocol TranscriptionEngine: AnyObject {
    var transcript: LiveTranscript { get }
    var level: LevelMeter { get }
    var session: SessionState { get }
    func start()
    func stop()
    func togglePause()
}
