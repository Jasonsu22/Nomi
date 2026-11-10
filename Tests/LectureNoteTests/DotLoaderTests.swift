import Foundation
import Testing
@testable import LectureNoteApp

/// The dot loaders: one per kind of step, three dots each, always inside the loader's box.
struct DotLoaderTests {
    @Test func eachStepHasItsOwnLoader() {
        let styles = [AnswerStep.Kind.files, .library, .web, .thinking, .writing].map(DotLoader.Style.init)
        #expect(styles == [.hop, .gather, .infinity, .circle, .breeze])
        #expect(DotLoader.Style.infinity.period == 4.2 && DotLoader.Style.hop.period == 1.2)
    }

    @Test func dotsStayInsideTheBoxAndLoop() {
        for style in DotLoader.Style.allCases {
            for step in 0..<100 {
                let dots = DotPath.dots(style, phase: Double(step) / 100)
                #expect(dots.count == 3)
                for dot in dots {
                    #expect(abs(dot.x) + dot.radius <= 1, "\(style) leaves the box sideways")
                    #expect(abs(dot.y) + dot.radius <= 0.5, "\(style) leaves the box vertically")
                    #expect((0...1).contains(dot.opacity))
                }
            }
            let start = DotPath.dots(style, phase: 0), end = DotPath.dots(style, phase: 0.999_999)
            for (a, b) in zip(start, end) {
                #expect(abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01 || a.opacity < 0.01 || b.opacity < 0.01, "\(style) jumps at the end of a loop")
            }
        }
    }

    @Test func theEightIsWalkedAtAnEvenPace() {
        var steps: [Double] = []
        var previous = DotPath.Lemniscate.point(at: 0)
        for k in 1...200 {
            let p = DotPath.Lemniscate.point(at: Double(k) / 200)
            steps.append(hypot(p.x - previous.x, p.y - previous.y))
            previous = p
        }
        #expect((steps.max() ?? 0) / (steps.min() ?? 1) < 1.05)
    }
}
