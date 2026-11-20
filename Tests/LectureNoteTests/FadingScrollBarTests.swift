import Foundation
import Testing
@testable import LectureNoteApp

/// Where the scroll bar's knob sits, and where dragging it scrolls to.
struct FadingScrollBarTests {
    @Test func theKnobFollowsTheScrollAndDraggingItScrollsBack() {
        let metrics = FadingScrollBar.Metrics(offset: 4_500, content: 10_000, visible: 1_000, width: 540)
        let track: CGFloat = 994
        #expect(metrics.scrollable)
        #expect(metrics.knobHeight(track: track) >= 32, "a long transcript still gets a knob big enough to grab")
        let top = metrics.knobTop(track: track)
        #expect(abs(metrics.offset(forKnobTop: top, track: track) - 4_500) < 0.5)
        #expect(metrics.offset(forKnobTop: -50, track: track) == 0)
        #expect(metrics.offset(forKnobTop: 5_000, track: track) == 9_000, "never past the end")
        #expect(!FadingScrollBar.Metrics(offset: 0, content: 800, visible: 1_000).scrollable)
    }
}
