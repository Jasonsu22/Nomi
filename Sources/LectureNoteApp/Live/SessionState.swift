import Foundation

enum SessionPhase: Equatable {
    case idle
    case preparing
    case listening
    case stopping
}

@MainActor
@Observable
final class SessionState {
    var phase: SessionPhase = .idle
    var isPaused = false
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?

    var elapsed: TimeInterval {
        guard let runningSince, phase == .listening, !isPaused else { return accumulated }
        return accumulated + Date().timeIntervalSince(runningSince)
    }

    func begin(at offset: TimeInterval = 0) {
        phase = .preparing
        isPaused = false
        accumulated = max(0, offset)
        runningSince = nil
    }

    func markListening() {
        phase = .listening
        isPaused = false
        runningSince = Date()
    }

    func togglePause() {
        guard phase == .listening else { return }
        if isPaused {
            isPaused = false
            runningSince = Date()
        } else {
            accumulated = elapsed
            isPaused = true
            runningSince = nil
        }
    }

    func beginStopping() -> TimeInterval {
        accumulated = elapsed
        runningSince = nil
        isPaused = false
        phase = .stopping
        return accumulated
    }

    func markIdle() {
        phase = .idle
        isPaused = false
        runningSince = nil
    }
}
