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

    @Test func completePageBecomesAWidgetWithoutItsShell() {
        let pieces = AnswerDocument.pieces(in: """
        可以。
        ```html
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>互动渐变</title>
        <style>body { margin: 0; }</style>
        </head>
        <body>
        <input type="range">
        </body>
        </html>
        ```
        """)
        let widget = pieces.compactMap { piece -> (String, String)? in
            if case .widget(let title, let html) = piece { return (title, html) }
            return nil
        }
        #expect(widget.count == 1)
        #expect(widget.first?.0 == "互动渐变")
        #expect(widget.first?.1.contains("<input type=\"range\">") == true)
        #expect(widget.first?.1.contains("<style>") == true)
        #expect(widget.first?.1.lowercased().contains("<!doctype") == false)
        #expect(widget.first?.1.lowercased().contains("<meta") == false)
    }

    @Test func finishedPageWithoutAClosingFenceBecomesAWidget() {
        let pieces = AnswerDocument.pieces(in: """
        ```html
        <!DOCTYPE html>
        <html><head><title>轨道</title></head><body><canvas id="c"></canvas></body></html>
        """)
        let widget = pieces.compactMap { piece -> String? in
            if case .widget(let title, _) = piece { return title }
            return nil
        }
        #expect(widget == ["轨道"])
    }

    @Test func truncatedPageStaysCode() {
        let pieces = AnswerDocument.pieces(in: """
        ```html
        <!DOCTYPE html>
        <html><body><script>let
        """)
        #expect(pieces.contains { if case .code(let body) = $0 { return body.contains("let") } else { return false } })
        #expect(!pieces.contains { if case .widget = $0 { return true } else { return false } })
    }

    @Test func completePageWithAnExternalScriptStaysCode() {
        let pieces = AnswerDocument.pieces(in: """
        ```
        <!doctype html>
        <html><body><script src="https://example.com/app.js"></script></body></html>
        ```
        ```python
        <html><body>print</body></html>
        ```
        """)
        #expect(!pieces.contains { if case .widget = $0 { return true } else { return false } })
        #expect(pieces.contains { if case .code(let body) = $0 { return body.contains("example.com") } else { return false } })
        #expect(pieces.contains { if case .code(let body) = $0 { return body.contains("print") } else { return false } })
    }

    @Test func streamingKeepsMarkdownAndHidesAnOpenHtmlFence() {
        let open = AnswerDocument.pieces(in: "说明\n\n# 标题\n\n- 第一\n```html 图\n<svg>", streaming: true)
        #expect(open.contains { if case .paragraph("说明") = $0 { return true } else { return false } })
        #expect(open.contains { if case .heading(1, "标题") = $0 { return true } else { return false } })
        #expect(open.contains { if case .list(false, ["第一"]) = $0 { return true } else { return false } })
        #expect(open.contains { if case .preparing = $0 { return true } else { return false } })
        #expect(!open.contains { if case .code(let body) = $0 { return body.contains("<svg>") } else { return false } })
        #expect(!open.contains { if case .paragraph(let text) = $0 { return text.contains("<svg>") || text.contains("#") } else { return false } })

        let closed = AnswerDocument.pieces(in: "```html\n<input type=\"range\">\n```\n结尾", streaming: true)
        #expect(closed.contains { if case .widget = $0 { return true } else { return false } })
        #expect(!closed.contains { if case .preparing = $0 { return true } else { return false } })
        #expect(!closed.contains { if case .code = $0 { return true } else { return false } })
        #expect(closed.contains { if case .paragraph("结尾") = $0 { return true } else { return false } })
    }

    @Test func formulaDelimitersBecomeMath() {
        let pieces = AnswerDocument.pieces(in: """
        二、焦点在 \\(x\\) 轴上的双曲线

        \\[
        \\boxed{\\frac{x^2}{a^2}-\\frac{y^2}{b^2}=1}
        \\]

        其中 \\(a>0,\\ b>0\\)。
        """)
        #expect(pieces.contains { if case .paragraph(let text) = $0 { return text.contains("\\(x\\)") } else { return false } })
        #expect(pieces.contains { if case .math(let latex) = $0 { return latex.contains("\\frac") && latex.contains("\\boxed") } else { return false } })

        let inline = AnswerInline.render("焦点在 \\(x\\) 轴上，其中 $a>0$。价格 $20 和 $30 不动。")
        let plain = String(inline.characters)
        #expect(plain.contains("焦点在"))
        #expect(plain.contains("轴上"))
        #expect(!plain.contains("\\("))
        #expect(!plain.contains("\\)"))
        #expect(plain.contains("$20"))
        #expect(plain.contains("$30"))
        #expect(inline.runs.contains { $0.link?.scheme == "nomi-math" && $0.link?.host == "inline" })

        let url = MathFormula.url(latex: "\\frac{x}{a}\nb", display: true)
        #expect(url.flatMap { MathFormula.latex(from: $0) }?.latex == "\\frac{x}{a}\nb")
        #expect(url?.host == "display")
    }

    @Test func streamingHidesUnclosedMarkers() {
        let bold = String(AnswerInline.render("这是 **重点", streaming: true).characters)
        #expect(bold == "这是 重点")
        #expect(!bold.contains("*"))
        let open = AnswerDocument.pieces(in: "正文\n\\[\n\\frac{1}{2}", streaming: true)
        #expect(open.contains { if case .paragraph("正文") = $0 { return true } else { return false } })
        #expect(!open.contains { if case .paragraph(let text) = $0 { return text.contains("\\frac") || text.contains("\\[") } else { return false } })
        #expect(!open.contains { if case .math = $0 { return true } else { return false } })
    }

    @Test @MainActor func boxedFractionRenders() {
        let image = MathRaster.raster(
            latex: "\\boxed{\\frac{x^{2}}{a^{2}}-\\frac{y^{2}}{b^{2}}=1}",
            fontSize: 18,
            color: .black,
            display: true,
            maxWidth: 640
        )
        #expect(image != nil)
        #expect((image?.image.size.height ?? 0) > 24)
        #expect((image?.image.size.width ?? 0) > 40)
        let inline = MathRaster.raster(latex: "x", fontSize: 15, color: .black, display: false, maxWidth: 640)
        #expect(inline != nil)
    }

    @Test func passageNumberBecomesTheSourceName() {
        let web = ChatCitation(title: "香港電台網站", detail: "rthk9.rthk.hk", url: "https://rthk9.rthk.hk/", passage: 1)
        let meeting = ChatCitation(title: "计算机网络", detail: "12:30", meetingID: UUID(), passage: 2)
        let file = ChatCitation(title: "01 - Introduction.pdf", detail: "", sourceID: UUID(), passage: 3)
        let rendered = AnswerInline.render("约 27°C。[1] 另一处是【2】，课件见 [3]，未知的 [9] 留着。", citations: [1: web, 2: meeting, 3: file])
        let plain = String(rendered.characters)
        #expect(plain.contains("香港電台網站"))
        #expect(plain.contains("计算机网络"))
        #expect(plain.contains("Introduction.pdf"))
        #expect(plain.contains("[9]"))
        #expect(!plain.contains("[1]"))
        #expect(!plain.contains("【2】"))
        #expect(rendered.runs.contains { $0.link?.host == "rthk9.rthk.hk" && $0.underlineStyle == nil })
        #expect(rendered.runs.contains { $0.link?.scheme == "nomi-cite" })
        #expect(web.symbolName == "globe")
        #expect(meeting.symbolName == "clock")
        #expect(file.symbolName == "doc.richtext")
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
        #expect(chinese.contains("明确要求"))
        let english = ChatContext.systemPrompt(language: "English", allowsWeb: false)
        #expect(english.contains("Write the answer in Markdown"))
        #expect(english.contains("explicitly asks to display"))
        #expect(!english.contains("语言为 html"))
    }
}
