import AppKit
import Testing
@testable import LectureNoteApp

@MainActor
struct ComposerHeightTests {
    private func textView() -> NSTextView {
        let view = NSTextView()
        view.font = .systemFont(ofSize: 15)
        view.textContainerInset = NSSize(width: 2, height: 8)
        return view
    }

    @Test func oneLineStaysAtTheSmallestHeight() {
        let view = textView()
        #expect(AskComposerField.height(of: "", width: 500, in: view) == AskComposerField.minHeight)
        #expect(AskComposerField.height(of: "Hello", width: 500, in: view) == AskComposerField.minHeight)
    }

    @Test func wrappedLinesMakeTheBoxTaller() {
        let view = textView()
        let one = AskComposerField.height(of: "short", width: 300, in: view)
        let long = String(repeating: "a long sentence that wraps ", count: 4)
        let wrapped = AskComposerField.height(of: long, width: 300, in: view)
        #expect(wrapped > one + 30, "about three wrapped lines, without any newline typed")
        #expect(AskComposerField.height(of: "a\nb\nc", width: 300, in: view) > one)
        #expect(AskComposerField.height(of: "a\n", width: 300, in: view) > one, "a newline at the end starts a new line")
    }

    @Test func theBoxStopsGrowingAtTheLineLimit() {
        let view = textView()
        let eight = AskComposerField.height(of: Array(repeating: "line", count: AskComposerField.maxLines).joined(separator: "\n"), width: 300, in: view)
        let forty = AskComposerField.height(of: Array(repeating: "line", count: 40).joined(separator: "\n"), width: 300, in: view)
        #expect(forty == eight)
        #expect(forty < 220)
    }
}
