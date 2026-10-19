import AppKit
import SwiftUI
import WebKit
import Testing
@testable import LectureNoteApp

@Suite(.serialized)
struct ChatPerformanceTests {
    /// Opt-in local smoke check. No private chat fixture is added to the repository.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NOMI_CHAT_PERF_DATA"] != nil))
    @MainActor func storedConversationsRenderThroughTheAppShell() async throws {
        let directory = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["NOMI_CHAT_PERF_DATA"]))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 780), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for file in files {
            var session = try JSONDecoder().decode(ChatSession.self, from: Data(contentsOf: file))
            guard !session.turns.isEmpty else { continue }
            // Exercise the standalone Chat page using a copy of meeting-bound chats too.
            session.anchorMeetingID = nil
            let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
            model.chats = [session]
            model.currentChatID = session.id
            let host = NSHostingView(rootView: AppShell(model: model))
            window.contentView = host
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(100))
            let start = ContinuousClock.now
            FileHandle.standardError.write(Data("CHAT_REAL: start \(session.turns.count) turns\n".utf8))
            withAnimation(Motion.tap(false)) { model.select(.ask) }
            try await Task.sleep(for: .milliseconds(500))
            host.layoutSubtreeIfNeeded()
            let table = try #require(descendants(host).compactMap { $0 as? ChatTableView }.first)
            #expect(table.numberOfRows >= session.turns.count)
            for index in session.turns.indices.reversed() {
                table.scrollRowToVisible(index)
                try await Task.sleep(for: .milliseconds(80))
                #expect(descendants(host).contains { $0 is NSTextView && !($0 is SubmitTextView) && !$0.visibleRect.isEmpty })
            }
            FileHandle.standardError.write(Data("CHAT_REAL: finished \(session.turns.count) turns in \(start.duration(to: .now))\n".utf8))
        }
    }

    @Test @MainActor func cumulativeUpdatesFlushWithoutLosingTheTail() {
        var shown: [String] = []
        let updates = ChatStreamUpdates { shown.append($0) }
        for index in 0..<1_000 { updates.submit("完整累计答案 \(index)") }
        #expect(shown.isEmpty)
        updates.flush()
        #expect(shown == ["完整累计答案 999"])
        updates.flush()
        #expect(shown.count == 1)
    }

    @Test @MainActor func scheduledUpdateAndCancellation() async throws {
        var shown: [String] = []
        let updates = ChatStreamUpdates(interval: .milliseconds(5)) { shown.append($0) }
        updates.submit("第一段")
        updates.submit("第一段和第二段")
        try await Task.sleep(for: .milliseconds(40))
        #expect(shown == ["第一段和第二段"])
        updates.submit("不应该显示")
        updates.cancel()
        try await Task.sleep(for: .milliseconds(40))
        #expect(shown == ["第一段和第二段"])
    }

    @Test @MainActor func preparationDoesNotConfuseStreamingAndFinalContent() async throws {
        let text = "缓存测试 \(UUID())\n\n**完成**"
        let partial = await AnswerPreparation.prepare(text, streaming: true)
        #expect(partial?.source == text)
        #expect(AnswerPreparation.cached(text) == nil)
        let final = try #require(await AnswerPreparation.prepare(text, streaming: false))
        #expect(final.pieces == AnswerDocument.pieces(in: text))
        #expect(AnswerPreparation.cached(text)?.pieces == final.pieces)
        let next = try #require(await AnswerPreparation.prepare(text + "另一个答案", streaming: false))
        #expect(next.source != final.source)
        #expect(next.pieces != final.pieces)
    }

    @Test @MainActor func ordinaryRunsKeepTheirTextAndFormatting() {
        let source = String(repeating: "中文 English 普通长文本，数字 123。", count: 1_000)
        let start = ContinuousClock.now
        let rendered = AnswerInline.render(source)
        let elapsed = start.duration(to: .now)
        #expect(String(rendered.characters) == source)
        #expect(rendered.runs.count == 1)
        let mixed = AnswerInline.render("前文https://example.com 后文 **粗体** `代码` \\(x\\) end")
        #expect(String(mixed.characters) == "前文https://example.com 后文 粗体 代码 \u{FFFC} end")
        #expect(mixed.runs.contains { $0.link?.host == "example.com" })
        #expect(mixed.runs.contains { $0.link?.scheme == "nomi-math" })
        print("CHAT_PERF: inline \(source.count) characters = \(elapsed)")
    }

    @Test @MainActor func coldPreviewNeverFlashesGeneratedHTML() {
        let source = "可阅读的历史正文\n```html\n<script>window.secret = 1</script>\n```\n最后一段"
        #expect(AnswerPreparation.preview(source) == "可阅读的历史正文\n最后一段")
        #expect(!AnswerPreparation.preview(source).contains("<script>"))
    }

    @Test @MainActor func longHistoryBuildsOnlyNearbyNativeViewsAndWebPoolIsBounded() async throws {
        _ = NSApplication.shared
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        let paragraph = String(repeating: "中英混排的历史消息。A long message with **formatting** and `code`. ", count: 10)
        let turns = (0..<200).map { index in
            ChatTurn(question: "问题 \(index)", answer: "# 回答 \(index)\n\n" + paragraph, modelName: "Test")
        }
        let session = ChatSession(turns: turns)
        model.chats = [session]
        model.currentChatID = session.id
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 720), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let start = ContinuousClock.now
        let host = NSHostingView(rootView: AskView(model: model))
        window.contentView = host
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(700))
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let nativeTexts = descendants(host).filter { $0 is NSTextView && !($0 is SubmitTextView) }.count
        #expect(nativeTexts > 0)
        #expect(nativeTexts < 40, "200 轮历史不能一次创建全部富文本视图")
        #expect(descendants(host).compactMap { ($0 as? NSTextView)?.string }.contains { $0.contains("回答 199") })
        print("CHAT_PERF: 200 turns, \(nativeTexts) mounted answer text views after \(start.duration(to: .now)) (includes 700 ms settle)")
        let table = try #require(descendants(host).compactMap { $0 as? ChatTableView }.first)
        for index in [0, 140, 30, 190, 0] {
            table.scrollRowToVisible(index)
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
            let visibleText = descendants(host).compactMap { $0 as? NSTextView }.filter {
                !($0 is SubmitTextView) && !$0.visibleRect.isEmpty && !$0.string.isEmpty
            }
            #expect(!visibleText.isEmpty, "快速跳到历史的第 \(index) 轮不能整屏空白")
        }
        // Re-entering the page uses the same completed-answer cache.
        window.contentView = NSHostingView(rootView: AskView(model: model))
        try await Task.sleep(for: .milliseconds(250))
        let returningTexts = descendants(try #require(window.contentView)).filter { $0 is NSTextView && !($0 is SubmitTextView) }.count
        #expect(returningTexts > 0 && returningTexts < 40)

        // More visible demos than slots must never allocate an extra WKWebView.
        let stack = NSStackView()
        stack.orientation = .vertical
        window.contentView = stack
        var demos: [DemoWebHost] = []
        var heights: [CGFloat] = []
        for index in 0..<5 {
            let demo = DemoWebHost(frame: NSRect(x: 0, y: 0, width: 500, height: 80))
            demo.heightAnchor.constraint(equalToConstant: 80).isActive = true
            stack.addArrangedSubview(demo)
            demo.configure(identity: "test-\(index)", html: AnswerDocument.page(fragment: "<button>\(index)</button>", text: "#111", surface: "#fff", accent: "#00f"), file: nil, visible: true, onHeight: { heights.append($0) })
            demos.append(demo)
        }
        stack.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        #expect(DemoWebPool.shared.instanceCount == DemoWebPool.limit)
        #expect(DemoWebPool.shared.activeCount <= DemoWebPool.limit)
        #expect(!heights.isEmpty)
        let web = try #require(descendants(stack).compactMap { $0 as? WKWebView }.first { !$0.isHidden && !$0.isLoading })
        let reported = try await web.evaluateJavaScript("document.body.style.paddingBottom = '240px'; document.body.scrollHeight")
        print("CHAT_PERF: resized HTML = \(String(describing: reported)), heights before = \(heights)")
        try await Task.sleep(for: .milliseconds(250))
        print("CHAT_PERF: heights after = \(heights)")
        #expect(heights.contains { $0 > 240 }, "交互导致的高度增长不能被首次测量锁住")
        for demo in demos { demo.deactivate() }
        try await Task.sleep(for: .milliseconds(650))
        #expect(DemoWebPool.shared.activeCount == 0)
    }
}
