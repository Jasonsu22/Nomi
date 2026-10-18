import SwiftUI

struct DotWaveform: View {
    var meter: LevelMeter
    var paused: Bool
    var reduceMotion: Bool

    private let count = 24
    @State private var frozenAt: TimeInterval?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: paused)) { timeline in
            Canvas { context, size in
                let time = frozenAt ?? ProcessInfo.processInfo.systemUptime + timeline.date.timeIntervalSinceNow
                let gap: CGFloat = 2
                let diameter = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
                for index in 0..<count {
                    let level = meter.columnLevel(index: index, count: count, at: time, reduceMotion: reduceMotion)
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
        }
        .frame(width: 96, height: 16)
        .opacity(paused ? 0.45 : 1)
        .accessibilityHidden(true)
        .onChange(of: paused) { _, isPaused in
            frozenAt = isPaused ? ProcessInfo.processInfo.systemUptime : nil
        }
    }
}
