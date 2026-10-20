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

    @Test func everyHtmlFenceBecomesAWidget() {
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
        #expect(widgets == ["拖动看斜率", "", ""])
        #expect(!pieces.contains { if case .code = $0 { return true } else { return false } })
        #expect(pieces.contains { if case .paragraph(let text) = $0 { return text == "前面" || text == "中间" || text == "后面" } else { return false } })
    }

    @Test func unsafeHtmlStaysACodeBlock() {
        let iframe = AnswerDocument.pieces(in: """
        ```html
        <iframe src="https://example.com"></iframe>
        ```
        """)
        #expect(iframe.contains { if case .code = $0 { return true } else { return false } })
        #expect(!iframe.contains { if case .widget = $0 { return true } else { return false } })
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
        #expect(chinese.contains("明确说不要演示"))
        #expect(chinese.contains("主动意愿要非常高"))
        let english = ChatContext.systemPrompt(language: "English", allowsWeb: false)
        #expect(english.contains("Write the answer in Markdown"))
        #expect(english.contains("explicitly says they do not want a demonstration"))
        #expect(english.contains("Be very eager"))
        #expect(!english.contains("语言为 html"))
        let chat = ChatContext.systemPrompt(language: "Simplified Chinese", allowsWeb: false, tools: true, webTool: .available)
        #expect(chat.contains("create_demo"))
        #expect(chat.contains("web_search"))
        #expect(chat.contains("明确说不要演示"))
        #expect(chat.contains("寒暄、关于学生自己的对话记录"))
        #expect(!chat.contains("另行生成"))
        let chatEnglish = ChatContext.systemPrompt(language: "English", allowsWeb: false, tools: true, webTool: .available)
        #expect(chatEnglish.contains("create_demo"))
        #expect(chatEnglish.contains("hidden subtask"))
        #expect(chatEnglish.contains("Do not call create_demo for small talk"))
        #expect(!chatEnglish.contains("语言为 html"))
    }

    @Test func toolCallsStayOutOfTheVisibleAnswer() {
        let raw = """
        双缝实验里，电子会自己干涉。

        <tool name="create_demo">做一块双缝页面，有缝距滑块和屏幕亮度。</tool>
        <tool name='web_search'>单电子双缝干涉</tool>
        """
        let parsed = ChatTools.parse(raw, streaming: false)
        #expect(parsed.visible.contains("双缝实验"))
        #expect(!parsed.visible.contains("<tool"))
        #expect(!parsed.visible.contains("缝距"))
        #expect(parsed.calls.map(\.name) == [ChatTools.createDemo, ChatTools.webSearch])
        #expect(parsed.calls[0].body.contains("缝距"))
        #expect(parsed.calls[1].body == "单电子双缝干涉")

        let streaming = ChatTools.parse("先看结论。<tool name=\"create_demo\">页面还在写", streaming: true)
        #expect(streaming.visible == "先看结论。")
        #expect(streaming.calls.isEmpty)
        let partial = ChatTools.parse("先看结论。<to", streaming: true)
        #expect(partial.visible == "先看结论。")
    }

    @Test func textAfterASearchCallWaitsForTheResults() {
        let raw = """
        我先查一下。
        <tool name="web_search">2026 诺贝尔物理学奖</tool>
        <tool name="web_search">诺贝尔物理学奖 得主 研究</tool>
        今年的得主是某某。
        <tool name="create_demo">做一条时间线。</tool>
        """
        let cut = ChatTools.parse(raw, streaming: false, stopAtSearch: true)
        #expect(cut.visible.trimmingCharacters(in: .whitespacesAndNewlines) == "我先查一下。")
        #expect(cut.calls.map(\.name) == [ChatTools.webSearch, ChatTools.webSearch])
        let kept = ChatTools.parse(raw, streaming: false)
        #expect(kept.visible.contains("今年的得主"))
        #expect(kept.calls.contains { $0.name == ChatTools.createDemo })
        let streaming = ChatTools.parse("<tool name=\"web_search\">双缝</tool>结论是", streaming: true, stopAtSearch: true)
        #expect(streaming.visible.isEmpty)
    }

    @Test func webPromptMakesSearchingTheDefault() {
        let available = ChatContext.toolInstruction(language: "Simplified Chinese", webTool: .available)
        #expect(available.contains("搜索是默认动作"))
        let prefetched = ChatContext.toolInstruction(language: "Simplified Chinese", webTool: .prefetched)
        #expect(prefetched.contains("已经用这个问题搜索过一次"))
        #expect(prefetched.contains("web_search"))
        let english = ChatContext.toolInstruction(language: "English", webTool: .available)
        #expect(english.contains("searching is the default"))
        #expect(ChatContext.toolInstruction(language: "English", webTool: .off).contains("Do not call web_search"))
        #expect(available.contains("最多一个 create_demo"))
    }

    @Test func aShortFollowUpBorrowsThePreviousQuestion() {
        let earlier = ChatTurn(question: "量子隧穿效应是什么", answer: "……", modelName: "m", citations: [], error: nil)
        #expect(ChatContext.searchQuery(question: "那它的应用呢", history: [earlier]) == "量子隧穿效应是什么 那它的应用呢")
        #expect(ChatContext.searchQuery(question: "解释一下扫描隧道显微镜的工作原理", history: [earlier]) == "解释一下扫描隧道显微镜的工作原理")
        #expect(ChatContext.searchQuery(question: "  ", history: []) == nil)
    }

    @Test func theDemoTaskSeesTheAnswerAndTheSandboxRules() {
        let prompt = ChatContext.visualUserPrompt(brief: "做一个缝距滑块", question: "什么是双缝干涉", answer: "条纹间距 Δy = λL/d。")
        #expect(prompt.contains("什么是双缝干涉"))
        #expect(prompt.contains("Δy = λL/d"))
        #expect(prompt.contains("做一个缝距滑块"))
        #expect(ChatContext.visualUserPrompt(brief: nil, answer: "答案").contains("NONE"))
        let system = ChatContext.visualSystemPrompt(language: "Simplified Chinese")
        #expect(system.contains("--nomi-accent"))
        #expect(system.contains("img"))
        #expect(ChatContext.wantsFallbackVisual(question: "讲讲傅里叶变换", answer: String(repeating: "字", count: 400)))
        #expect(!ChatContext.wantsFallbackVisual(question: "讲讲傅里叶变换，不要演示", answer: String(repeating: "字", count: 400)))
        #expect(!ChatContext.wantsFallbackVisual(question: "你好", answer: "你好！"))
    }

    @Test func aCutOffOrBlockedPageIsNotAppended() {
        #expect(ChatContext.htmlFence(from: "```html\n<div><script>let a = 1") == nil)
        #expect(ChatContext.htmlFence(from: "```html\n<html><body><p>完整</p></body></html>") != nil)
        let titled = ChatContext.htmlFence(from: "```html 双缝\n<button>发射</button>\n```")
        #expect(titled == "```html 双缝\n<button>发射</button>\n```")
        #expect(ChatContext.rendersWidget(titled ?? ""))
        #expect(!ChatContext.rendersWidget("```html\n<img src=\"https://example.com/a.png\">\n```"))
    }

    @Test func aLongDisplayPageStillRuns() {
        let script = String(repeating: "const n = 1;\n", count: 2200)
        let page = "<!doctype html><html><head><title>双缝</title></head><body><canvas></canvas><script>\n\(script)</script></body></html>"
        #expect(page.utf8.count > 24 * 1024)
        let pieces = AnswerDocument.pieces(in: "```html\n\(page)\n```")
        #expect(pieces.contains { if case .widget(let title, _) = $0 { return title == "双缝" } else { return false } })
    }

    @Test func anHtmlFilenameBecomesAFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = """
        保存为 `double-slit.html` 后打开。
        ```html
        <button>发射</button>
        ```
        """
        let export = ChatFiles.export(source, directory: directory)
        let url = try #require(export.named["double-slit.html"])
        #expect(url.lastPathComponent == "double-slit.html")
        #expect(export.widgets == [url])
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved.contains("<button>发射</button>"))
        #expect(saved.contains("<!DOCTYPE html>"))
        let linked = AnswerInline.render("保存为 `double-slit.html` 后打开。", files: export.named)
        #expect(linked.runs.contains { $0.link == url })
        let plain = AnswerInline.render("`let x = 1` 和 `double-slit.html`")
        #expect(!plain.runs.contains { $0.link != nil })
    }

    @Test func preParsedHtmlUsesTheSameExport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = """
        保存为 `double-slit.html` 后打开。
        ```html
        <button>发射</button>
        ```
        """
        let fromSource = ChatFiles.export(source, directory: directory)
        let fromPieces = ChatFiles.export(AnswerDocument.pieces(in: source), directory: directory)
        #expect(fromPieces == fromSource)
    }

    @MainActor @Test func aFinishedAnswerIsParsedOnceUntilItsCitationsChange() {
        AnswerPreparedCache.removeAll()
        defer { AnswerPreparedCache.removeAll() }
        let source = "# 标题\n干涉条纹 [1]。\n\n- 第一\n- 第二"
        let first = [ChatCitation(title: "第一讲", passage: 1)]
        var made = 0
        func prepared(_ citations: [ChatCitation]) -> AnswerPrepared {
            AnswerPreparedCache.prepared(source, citations: citations) {
                made += 1
                return AnswerBody.prepare(source, streaming: false, citations: citations)
            }
        }
        let cached = prepared(first)
        #expect(prepared(first) == cached)
        #expect(made == 1)
        #expect(cached == AnswerBody.prepare(source, streaming: false, citations: first))
        let renamed = [ChatCitation(id: first[0].id, title: "第二讲", passage: 1)]
        #expect(prepared(renamed).citations[1]?.title == "第二讲")
        #expect(made == 2)
        #expect(AnswerPreparedCache.count == 1)
    }

    @Test func aVisualMarkerWaitsForASecondReply() {
        let streaming = ChatContext.splitVisual("光会干涉。\n[[vis", streaming: true)
        #expect(streaming.text == "光会干涉。")
        #expect(!streaming.wantsVisual)
        let citation = ChatContext.splitVisual("见 [3]", streaming: true)
        #expect(citation.text == "见 [3]")
        let finished = ChatContext.splitVisual("光会干涉。\n\n[[visual]]\n", streaming: false)
        #expect(finished.text == "光会干涉。")
        #expect(finished.wantsVisual)
        let source = ChatContext.htmlFence(from: "说明\n```html\n<div>演示</div>\n```\n")
        #expect(source == "```html\n<div>演示</div>\n```")
        #expect(ChatContext.htmlFence(from: "NONE") == nil)
    }

    @Test func anHttpsImageBecomesAPictureAndOtherAddressesStayText() {
        let pieces = AnswerDocument.pieces(in: "先看这张。\n\n![双缝](https://example.com/slit.png)\n\n后面继续。")
        #expect(pieces.contains { if case .remoteImage(let alt, let url) = $0 { return alt == "双缝" && url == "https://example.com/slit.png" } else { return false } })
        let http = AnswerDocument.pieces(in: "![本地](http://example.com/a.png)")
        #expect(!http.contains { if case .remoteImage = $0 { return true } else { return false } })
        #expect(http.contains { if case .paragraph(let text) = $0 { return text.contains("http://example.com/a.png") } else { return false } })
        let fenced = AnswerDocument.pieces(in: "```\n![双缝](https://example.com/slit.png)\n```")
        #expect(fenced.contains { if case .code(let code) = $0 { return code.contains("![双缝]") } else { return false } })
        #expect(!fenced.contains { if case .remoteImage = $0 { return true } else { return false } })
    }

    @Test func oldChatsOpenWithoutImages() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","question":"问题","answer":"回答","modelName":"MiniMax","createdAt":0,"citations":[]}
        """
        let turn = try JSONDecoder().decode(ChatTurn.self, from: Data(json.utf8))
        #expect(turn.images.isEmpty)
        #expect(turn.question == "问题")
    }

    @Test func onlyRecentImagesAreSent() {
        let older = ChatTurn(question: "旧", answer: "答", modelName: "m", images: [sampleImage("old")])
        let recent = (0..<4).map { index in
            ChatTurn(question: "问\(index)", answer: "答", modelName: "m", images: [sampleImage("\(index)")])
        }
        let plan = ChatContext.attachedImages(history: [older] + recent, currentCount: 6)
        #expect(plan.history.count == 2)
        #expect(plan.mentionsOlderImages)
        #expect(plan.omittedTurnIDs.count == 2)
        #expect(ChatImages.seesImages(mode: .local, modelID: "Qwen3.5 2B") == false)
        #expect(ChatImages.seesImages(mode: .api, modelID: "MiniMax-M2.7") == false)
        #expect(ChatImages.seesImages(mode: .api, modelID: "MiniMax-M3.1-Flash") == true)
        #expect(ChatImages.seesImages(mode: .api, modelID: "gpt-5.6-sol") == true)
        let content = RemoteLLMClient.openAIContent(prompt: "Question:", images: [ModelImage(mime: "image/png", base64: "YQ==")], miniMax: true) as? [[String: Any]]
        #expect(content?.count == 2)
        let image = content?[1]["image_url"] as? [String: Any]
        #expect(image?["detail"] as? String == "default")
        #expect((image?["url"] as? String)?.hasPrefix("data:image/png;base64,") == true)
        let anthropic = RemoteLLMClient.anthropicContent(prompt: "Question:", images: [ModelImage(mime: "image/png", base64: "YQ==")]) as? [[String: Any]]
        let source = (anthropic?[1]["source"] as? [String: Any])
        #expect(source?["type"] as? String == "base64")
        #expect(source?["media_type"] as? String == "image/png")
    }

    private func sampleImage(_ name: String) -> ChatImage {
        ChatImage(id: UUID(), name: name, mime: "image/png", relativePath: "\(name).png")
    }
}
