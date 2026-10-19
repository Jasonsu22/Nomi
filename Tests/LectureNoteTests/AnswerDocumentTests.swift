import Foundation
import Testing
@testable import LectureNoteApp

struct AnswerDocumentTests {
    @Test func proseStaysText() {
        let pieces = AnswerDocument.pieces(in: """
        # 标题
        一段 **重点** 和 [3]。

        - 第一
        - 第二
        """)
        #expect(pieces.contains { if case .heading(1, "标题") = $0 { return true } else { return false } })
        #expect(pieces.contains { if case .paragraph(let text) = $0 { return text.contains("**重点**") && text.contains("[3]") } else { return false } })
        #expect(pieces.contains { if case .list(false, let items) = $0 { return items == ["第一", "第二"] } else { return false } })
        #expect(!pieces.contains { if case .widget = $0 { return true } else { return false } })
    }

    @Test func htmlFenceBecomesAWidgetAndAThirdBecomesCode() {
        let svg = "<svg><text>线</text></svg>"
        let source = """
        前面
        ```html 拖动看斜率
        \(svg)
        ```
        中间
        ```html
        <input type="range">
        ```
        后面
        ```html
        <button>再来</button>
        ```
        """
        let pieces = AnswerDocument.pieces(in: source)
        let widgets = pieces.compactMap { piece -> String? in
            if case .widget(let title, _) = piece { return title }
            return nil
        }
        #expect(widgets == ["拖动看斜率", ""])
        #expect(pieces.contains { if case .code(let body) = $0 { return body.contains("<button>") } else { return false } })
        #expect(pieces.contains { if case .paragraph(let text) = $0 { return text == "前面" || text == "中间" || text == "后面" } else { return false } })
    }

    @Test func unsafeOrOversizedHtmlStaysACodeBlock() {
        let iframe = AnswerDocument.pieces(in: """
        ```html
        <iframe src="https://example.com"></iframe>
        ```
        """)
        #expect(iframe.contains { if case .code = $0 { return true } else { return false } })
        #expect(!iframe.contains { if case .widget = $0 { return true } else { return false } })

        let huge = String(repeating: "a", count: AnswerDocument.widgetByteLimit + 1)
        let oversized = AnswerDocument.pieces(in: """
        ```html
        \(huge)
        ```
        ```html
        <svg></svg>
        ```
        """)
        #expect(oversized.contains { if case .code(let body) = $0 { return body.count > AnswerDocument.widgetByteLimit } else { return false } })
        #expect(oversized.contains { if case .widget = $0 { return true } else { return false } })
    }

    @Test func streamingHidesHtmlFencesUntilTheAnswerFinishes() {
        let open = AnswerDocument.streamingPieces(in: "说明\n```html 图\n<svg>")
        #expect(open.contains { if case .text(let text) = $0 { return text.contains("说明") } else { return false } })
        #expect(open.contains { if case .preparing = $0 { return true } else { return false } })
        #expect(!open.contains { if case .text(let text) = $0 { return text.contains("<svg>") } else { return false } })

        let closed = AnswerDocument.streamingPieces(in: "```html\n<input type=\"range\">\n```\n结尾")
        #expect(closed.first == .preparing)
        #expect(closed.contains { if case .text(let text) = $0 { return text.contains("结尾") } else { return false } })
    }

    @Test func onlyHttpLinksOpen() {
        let linked = AnswerInline.render("看 [课程](https://example.com/a) 和 [坏](javascript:alert(1))")
        let plain = String(linked.characters)
        #expect(plain.contains("课程"))
        #expect(plain.contains("坏"))
        #expect(!plain.contains("javascript"))
        #expect(linked.runs.contains { $0.link?.scheme == "https" })
    }

    @Test func displayInstructionFollowsTheModelLanguage() {
        let chinese = ChatContext.systemPrompt(language: "Simplified Chinese", allowsWeb: false)
        #expect(chinese.contains("语言为 html 的围栏"))
        let english = ChatContext.systemPrompt(language: "English", allowsWeb: false)
        #expect(english.contains("Write the answer in Markdown"))
        #expect(!english.contains("语言为 html"))
    }
}
