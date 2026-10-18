import SwiftUI

struct DotWaveform: View {
    var meter: LevelMeter
    var paused: Bool
    var reduceMotion: Bool

    private let count = 24
    @State private var targets: [CGFloat]
    @State private var shown: [CGFloat]
    @State private var lastShift = Date.distantPast

    init(meter: LevelMeter, paused: Bool, reduceMotion: Bool) {
        self.meter = meter
        self.paused = paused
        self.reduceMotion = reduceMotion
        let flat = Array(repeating: CGFloat(0.2), count: 24)
        _targets = State(initialValue: flat)
        _shown = State(initialValue: flat)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: paused)) { timeline in
            Canvas { context, size in
                let gap: CGFloat = 2
                let diameter = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
                for index in 0..<count {
                    let level = shown[index]
                    let height = max(diameter, size.height * level)
                    let rect = CGRect(
                        x: CGFloat(index) * (diameter + gap),
                        y: (size.height - height) / 2,
                        width: diameter,
                        height: height
                    )
                    context.fill(Path(ellipseIn: rect), with: .foreground)
                }
            }
            .onChange(of: timeline.date) { _, date in
                advance(to: date)
            }
        }
        .frame(width: 96, height: 16)
        .opacity(paused ? 0.45 : 1)
        .accessibilityHidden(true)
    }

    private func advance(to date: Date) {
        if date.timeIntervalSince(lastShift) >= 0.05 {
            lastShift = date
            targets.removeFirst()
            let level = paused ? 0.2 : min(1, max(0.16, meter.rms))
            targets.append(CGFloat(level))
        }
        if reduceMotion || paused {
            shown = targets
            return
        }
        for index in shown.indices {
            shown[index] += (targets[index] - shown[index]) * 0.35
        }
    }
}
