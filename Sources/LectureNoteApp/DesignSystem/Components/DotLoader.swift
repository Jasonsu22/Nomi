import SwiftUI

/// Nomi's loading animation: three green dots, moving differently for each kind of work, the way
/// Claude Code changes its spinner by tool. Designed in `Design/Animations/leaf-loaders-preview.html`;
/// the chosen design is `Design/Animations/leaf-loaders.json`. With Reduce Motion it is a still frame.
struct DotLoader: View {
    enum Style: String, CaseIterable, Sendable {
        /// Reading files: the typing dots, each hopping in turn.
        case hop
        /// Searching the library: dots spiral in to the middle and fade.
        case gather
        /// Searching the web: dots run round an 8 on its side.
        case infinity
        /// Thinking: dots circle.
        case circle
        /// Writing: dots drift across on a wave.
        case breeze

        /// Seconds for one loop.
        var period: Double {
            switch self {
            case .hop: 1.2
            case .gather: 3.0
            case .infinity: 4.2
            case .circle: 3.0
            case .breeze: 2.8
            }
        }

        init(_ kind: AnswerStep.Kind) {
            switch kind {
            case .files: self = .hop
            case .library: self = .gather
            case .web: self = .infinity
            case .thinking: self = .circle
            case .writing: self = .breeze
            }
        }
    }

    var style: Style
    /// The loader is twice as wide as it is tall, unless `width` says otherwise.
    var height: CGFloat = 16
    var width: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
            Canvas { canvas, size in
                let phase = reduceMotion ? 0.08 : (context.date.timeIntervalSinceReferenceDate / style.period).truncatingRemainder(dividingBy: 1)
                let unit = size.height
                for dot in DotPath.dots(style, phase: phase) where dot.opacity > 0.01 && dot.radius > 0.001 {
                    let center = CGPoint(x: size.width / 2 + dot.x * unit, y: size.height / 2 + dot.y * unit)
                    let r = dot.radius * unit
                    var layer = canvas
                    layer.opacity = dot.opacity
                    layer.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)), with: .color(DotPath.color))
                }
            }
        }
        .frame(width: width ?? height * 2, height: height)
        .accessibilityHidden(true)
    }
}

/// Where the dots are. Units of the loader's height, from its centre: x runs -1…1, y -0.5…0.5.
/// Pure functions of the phase (0…1), so they can be tested and drawn anywhere.
enum DotPath {
    static let color = Color(red: 0x20 / 255, green: 0xB6 / 255, blue: 0x8A / 255)
    static let count = 3

    struct Dot: Equatable {
        var x: CGFloat
        var y: CGFloat
        var radius: CGFloat
        var opacity: Double = 1
    }

    private static func wrap(_ value: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: 1)
        return r < 0 ? r + 1 : r
    }

    /// Fades a dot in at the start of its path and out at the end.
    private static func edge(_ s: Double) -> Double { min(1, s / 0.14, (1 - s) / 0.14) }

    static func dots(_ style: DotLoader.Style, phase: Double) -> [Dot] {
        let n = Double(count), gap = 1 / n
        return (0..<count).map { index in
            let i = Double(index)
            switch style {
            case .hop:
                let s = wrap(phase - i * gap * 0.42)
                let up = s < 0.4 ? sin(.pi * s / 0.4) : 0
                return Dot(x: (i - (n - 1) / 2) * 0.44, y: 0.08 - 0.2 * up, radius: 0.17 * 0.44)
            case .gather:
                let s = wrap(phase + i * gap)
                let r = 0.42 * (1 - s), angle = 2 * .pi * 1.2 * s + 2 * .pi * i / n
                return Dot(x: cos(angle) * r * 1.6, y: sin(angle) * r * 0.8,
                           radius: 0.17 * 0.5 * (0.55 + 0.45 * s), opacity: min(1, s / 0.1, (1 - s) / 0.06))
            case .infinity:
                let point = Lemniscate.point(at: wrap(phase + i * gap))
                return Dot(x: point.x * 0.6, y: point.y * 0.6, radius: 0.17 * 0.52)
            case .circle:
                let angle = 2 * .pi * wrap(phase + i * gap) - .pi / 2
                return Dot(x: cos(angle) * 0.3, y: sin(angle) * 0.3, radius: 0.17 * 0.5)
            case .breeze:
                let s = wrap(phase + i * gap)
                return Dot(x: -0.85 + 1.7 * s, y: 0.16 * sin(2 * .pi * 1.25 * s + 1), radius: 0.17 * 0.46, opacity: edge(s))
            }
        }
    }

    /// An 8 on its side (a lemniscate of Gerono), walked at an even speed: a table maps the distance
    /// along it to the curve's own angle.
    enum Lemniscate {
        static let squash = 0.9
        private static let steps = 1200
        private static func raw(_ t: Double) -> CGPoint { CGPoint(x: cos(t), y: squash * sin(t) * cos(t)) }

        private static let table: (angles: [Double], lengths: [Double]) = {
            var angles = [0.0], lengths = [0.0], previous = raw(0), total = 0.0
            for step in 1...steps {
                let t = 2 * .pi * Double(step) / Double(steps), p = raw(t)
                total += hypot(p.x - previous.x, p.y - previous.y)
                angles.append(t)
                lengths.append(total)
                previous = p
            }
            return (angles, lengths.map { $0 / total })
        }()

        /// The point `s` (0…1) of the way round, measured along the curve.
        static func point(at s: Double) -> CGPoint {
            let lengths = table.lengths
            var low = 0, high = lengths.count - 1
            while high - low > 1 {
                let middle = (low + high) / 2
                if lengths[middle] < s { low = middle } else { high = middle }
            }
            let span = lengths[high] - lengths[low]
            let f = span > 0 ? (s - lengths[low]) / span : 0
            return raw(table.angles[low] + (table.angles[high] - table.angles[low]) * f)
        }
    }
}

/// A light band that sweeps across the text of a step that is still running.
struct Shimmer: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    GeometryReader { geometry in
                        let phase = (context.date.timeIntervalSinceReferenceDate / 1.8).truncatingRemainder(dividingBy: 1)
                        let width = max(40, geometry.size.width * 0.45)
                        LinearGradient(colors: [.clear, AppColor.textPrimary, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: width)
                            .offset(x: -width + CGFloat(phase) * (geometry.size.width + width))
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
            }
        } else {
            content
        }
    }
}

extension View {
    func shimmering(_ active: Bool = true) -> some View { modifier(Shimmer(active: active)) }
}
