import SwiftUI

/// Nomi's loading animation: three small leaves circle; each opens from a round seed into the
/// Nomi leaf at the top of the circle and closes again at the bottom. With Reduce Motion it is a
/// still frame. Drawn from the real logo outline (`LeafOutline`), so it stays sharp at any size.
struct LeafOrbit: View {
    var size: CGFloat = 16
    /// Seconds for one full turn.
    var period: Double = 2.4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
            Canvas { canvas, canvasSize in
                let phase = reduceMotion ? 0 : (context.date.timeIntervalSinceReferenceDate / period).truncatingRemainder(dividingBy: 1)
                LeafMorph.drawOrbit(in: &canvas, size: canvasSize, phase: phase)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The geometry behind `LeafOrbit`. Pure functions of the phase, so a frame can be drawn anywhere.
enum LeafMorph {
    static let leafColor = Color(red: 0x20 / 255, green: 0xB6 / 255, blue: 0x8A / 255)
    static let mintColor = Color(red: 0x8E / 255, green: 0xDD / 255, blue: 0xBA / 255)

    /// The seed: the leaf's own points laid on a small circle, starting at the same angle and running
    /// the same way round, so the morph never twists.
    static let seed: [CGPoint] = {
        let leaf = LeafOutline.leaf
        let start = atan2(leaf[0].y, leaf[0].x)
        let next = atan2(leaf[1].y, leaf[1].x)
        let direction: CGFloat = sin(next - start) >= 0 ? 1 : -1
        return leaf.indices.map { index in
            let angle = start + direction * 2 * .pi * CGFloat(index) / CGFloat(leaf.count)
            return CGPoint(x: cos(angle) * 0.17, y: sin(angle) * 0.17)
        }
    }()

    static let highlightPath = smoothPath(LeafOutline.highlight)

    static func ease(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// The outline `amount` of the way from seed (0) to leaf (1).
    static func outline(_ amount: CGFloat) -> [CGPoint] {
        let e = ease(min(1, max(0, amount)))
        return zip(seed, LeafOutline.leaf).map { s, l in
            CGPoint(x: s.x + (l.x - s.x) * e, y: s.y + (l.y - s.y) * e)
        }
    }

    /// A closed Catmull-Rom curve through the points.
    static func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        let n = points.count
        guard n > 2 else { return path }
        path.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n], p1 = points[i], p2 = points[(i + 1) % n], p3 = points[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }

    /// Three leaves on a circle; the one at the top is fully open.
    static func drawOrbit(in canvas: inout GraphicsContext, size: CGSize, phase: Double) {
        let unit = min(size.width, size.height) / 1.5
        for index in 0..<3 {
            let angle = 2 * Double.pi * (phase + Double(index) / 3) - .pi / 2
            let open = CGFloat(pow(0.5 - 0.5 * sin(angle), 1.6))
            let shape = smoothPath(outline(open))
            var context = canvas
            // Larger leaves on a tighter circle than the web preview, so they still read as leaves at 16 pt.
            context.translateBy(x: size.width / 2 + CGFloat(cos(angle)) * 0.36 * unit,
                                y: size.height / 2 + CGFloat(sin(angle)) * 0.36 * unit)
            context.rotate(by: .radians(angle + .pi / 2 + .pi / 4))
            context.scaleBy(x: 0.56 * unit, y: 0.56 * unit)
            context.fill(shape, with: .color(leafColor))
            let shine = max(0, (ease(open) - 0.45) / 0.45)
            if shine > 0 {
                context.opacity = min(1, shine)
                context.fill(highlightPath, with: .color(mintColor))
            }
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
