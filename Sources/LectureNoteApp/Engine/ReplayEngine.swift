import Foundation
import SwiftUI

@MainActor
@Observable
final class ReplayEngine: TranscriptionEngine {
    let transcript = LiveTranscript()
    let level = LevelMeter()
    let session = SessionState()

    var loadError: String?
    var readiness: EngineReadiness { .preview }
    var canStart: Bool { loadError == nil && session.phase == .idle }
    var sourceLanguage = "zh"
    var targetLanguage = "en"
    var inputDeviceUID: String?
    var onFinished: (@MainActor ([Paragraph], TimeInterval) -> Void)?

    private var events: [FixtureEvent] = []
    private var cursor = 0
    private var playback: TimeInterval = 0
    private var playTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?

    init() {
        do {
            events = try SampleLecture.load()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func start(resuming paragraphs: [Paragraph] = [], at offset: TimeInterval = 0) {
        guard session.phase == .idle else { return }
        guard loadError == nil else { return }
        cursor = 0
        playback = 0
        transcript.setSourceLanguage(sourceLanguage)
        transcript.reset(keeping: paragraphs, at: offset)
        session.begin(at: offset)
        startLevel()
        playTask = Task {
            try? await Task.sleep(for: .milliseconds(780))
            guard !Task.isCancelled, session.phase == .preparing else { return }
            withAnimation(Motion.morph(ReduceMotion.system)) {
                session.markListening()
            }
            await runPlayback()
        }
    }

    func stop() {
        guard session.phase == .preparing || session.phase == .listening else { return }
        let duration = session.beginStopping()
        playTask?.cancel()
        playTask = nil
        transcript.flush(at: duration, reduceMotion: ReduceMotion.system)
        let snapshot = transcript.paragraphs
        stopTask?.cancel()
        stopTask = Task {
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.morph(ReduceMotion.system)) {
                session.markIdle()
            }
            level.rms = 0
            levelTask?.cancel()
            levelTask = nil
            onFinished?(snapshot, duration)
        }
    }

    func togglePause() {
        guard session.phase == .listening else { return }
        withAnimation(Motion.tap(ReduceMotion.system)) {
            session.togglePause()
        }
    }

    private func runPlayback() async {
        var lastTick = Date()
        while !Task.isCancelled {
            if session.phase != .listening { return }
            let now = Date()
            let delta = now.timeIntervalSince(lastTick)
            lastTick = now
            if !session.isPaused {
                playback += min(max(0, delta), 0.25)
                pump()
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    private func pump() {
        let reduce = ReduceMotion.system
        while cursor < events.count, events[cursor].time <= playback {
            let event = events[cursor]
            cursor += 1
            switch event.kind {
            case .tail(let text, let start, _):
                transcript.applyTail(text: text, start: start, reduceMotion: reduce)
            case .commit(let commit, let tail):
                transcript.applyCommit(commit, tail: tail, reduceMotion: reduce)
            }
        }
    }

    private func startLevel() {
        levelTask?.cancel()
        levelTask = Task {
            var time = 0.0
            while !Task.isCancelled {
                if session.phase == .idle {
                    level.rms = 0
                    return
                }
                if session.phase == .listening, !session.isPaused {
                    time += 0.05
                    level.rms = speechLevel(time)
                } else {
                    level.rms = 0
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func speechLevel(_ time: Double) -> Double {
        let slow = abs(sin(time * 2.2))
        let fast = abs(sin(time * 6.7))
        return 0.18 + 0.82 * pow(slow, 0.85) * (0.45 + 0.55 * fast)
    }
}
