import Foundation

/// 最近约两秒的音量。不参与界面观察：波形按时间自己算高度，不在每一帧写状态。
struct LevelHistory {
    static let shift: TimeInterval = 0.05
    static let rest: CGFloat = 0.2

    private var entries: [(time: TimeInterval, level: CGFloat)] = []

    mutating func record(_ rms: Double, at time: TimeInterval) {
        let level = CGFloat(min(1, max(Self.rest, rms)))
        entries.append((time, level))
        let cutoff = time - 2
        if let keep = entries.firstIndex(where: { $0.time >= cutoff }), keep > 0 {
            entries.removeFirst(keep)
        }
    }

    func columnLevel(index: Int, count: Int, at time: TimeInterval, reduceMotion: Bool) -> CGFloat {
        let age = Double(count - 1 - index) * Self.shift
        let sampleTime = time - age
        let target = value(at: sampleTime)
        if reduceMotion { return target }
        let bucket = (sampleTime / Self.shift).rounded(.down) * Self.shift
        let previous = value(at: bucket - 0.0001)
        let fraction = min(1, max(0, (sampleTime - bucket) / Self.shift))
        let progress = 1 - pow(0.65, fraction * 0.05 * 60)
        return previous + (target - previous) * progress
    }

    private func value(at time: TimeInterval) -> CGFloat {
        var result = Self.rest
        for entry in entries where entry.time <= time {
            result = entry.level
        }
        return result
    }
}

@MainActor
@Observable
final class LevelMeter {
    var rms: Double = 0 {
        didSet { history.record(rms, at: ProcessInfo.processInfo.systemUptime) }
    }

    @ObservationIgnored var history = LevelHistory()

    func recordMicrophoneRMS(_ value: Double) {
        let decibels = 20 * log10(max(value, 0.000_001))
        rms = min(1, max(0, (decibels + 65) / 45))
    }

    func columnLevel(index: Int, count: Int, at time: TimeInterval, reduceMotion: Bool) -> CGFloat {
        history.columnLevel(index: index, count: count, at: time, reduceMotion: reduceMotion)
    }
}
