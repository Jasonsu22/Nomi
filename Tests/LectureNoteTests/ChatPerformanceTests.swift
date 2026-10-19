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
        let renderOutput = ProcessInfo.processInfo.environment["NOMI_CHAT_PERF_OUTPUT"].map { URL(fileURLWithPath: $0) }
        if let renderOutput { try FileManager.default.createDirectory(at: renderOutput, withIntermediateDirectories: true) }
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
                checkTextHeights(in: host)
                if let renderOutput {
                    let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false)
                    let visible = descendants(host).compactMap { $0 as? NSTextView }.filter { !($0 is SubmitTextView) && !$0.visibleRect.isEmpty }
                    let diagnostic = "table=\(table.frame) visible=\(table.visibleRect) row=\(table.rect(ofRow: index)) cell=\(String(describing: cell?.frame))\n" + visible.map { text in
                        let container = text.textContainer!
                        return "text=\(text.string.prefix(35)) frame=\(text.frame) container=\(container.containerSize) used=\(text.layoutManager!.usedRect(for: container)) visible=\(text.visibleRect) window=\(text.convert(text.bounds, to: nil))"
                    }.joined(separator: "\n")
                    let stem = "\(file.deletingPathExtension().lastPathComponent)-\(index)"
                    try diagnostic.write(to: renderOutput.appendingPathComponent(stem + ".txt"), atomically: true, encoding: .utf8)
                    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        try bitmap.representation(using: .png, properties: [:])?.write(to: renderOutput.appendingPathComponent(stem + ".png"))
                    }
                }
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
        var turns = (0..<200).map { index in
            ChatTurn(question: "问题 \(index)", answer: "# 回答 \(index)\n\n" + paragraph, modelName: "Test")
        }
        turns[197].answer += "\n\n```html\n<div style=\"height:220px\">Preloaded chart</div>\n```"
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
        checkTextHeights(in: host)
        #expect(descendants(host).compactMap { ($0 as? NSTextView)?.string }.contains { $0.contains("回答 199") })
        print("CHAT_PERF: 200 turns, \(nativeTexts) mounted answer text views after \(start.duration(to: .now)) (includes 700 ms settle)")
        let table = try #require(descendants(host).compactMap { $0 as? ChatTableView }.first)
        let coordinator = try #require(table.delegate as? ChatTranscript.Coordinator)
        let firstVisible = table.rows(in: table.visibleRect).location
        let preceding = Array(max(0, firstVisible - 6)..<firstVisible)
        func ready(_ row: Int) -> Bool {
            coordinator.preloadedRowIDs.contains(session.turns[row].id) || table.view(atColumn: 0, row: row, makeIfNecessary: false)?.window != nil
        }
        #expect(!preceding.isEmpty)
        // WebKit's first process launch is asynchronous. Wait for the offscreen
        // page, without scrolling it into view to trigger loading.
        let webDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < webDeadline {
            if preceding.allSatisfy(ready), descendants(table).compactMap({ $0 as? DemoWebHost }).contains(where: { demo in
                demo.html.contains("Preloaded chart") && demo.active && demo.bounds.height > 200 && descendants(demo).contains { ($0 as? WKWebView)?.isLoading == false }
            }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(preceding.allSatisfy(ready), "上方六轮应在进入视口前完成视图准备")
        #expect(coordinator.preloadedRowIDs.count <= 8)
        let upcomingDemo = try #require(descendants(table).compactMap { $0 as? DemoWebHost }.first { $0.html.contains("Preloaded chart") })
        #expect(!upcomingDemo.convert(upcomingDemo.bounds, to: table).intersects(table.visibleRect))
        #expect(upcomingDemo.active && upcomingDemo.bounds.height > 200, "下一轮的 HTML 应在进入视口前加载并确定高度")
        #expect(descendants(upcomingDemo).contains { ($0 as? WKWebView)?.isLoading == false })
        for row in max(0, firstVisible - 6)..<firstVisible {
            #expect(table.rect(ofRow: row).height > 160, "预加载必须提前测量行高，而不只是缓存 Markdown")
        }
        let clip = try #require(table.enclosingScrollView?.contentView)
        func position() -> (row: Int, offset: CGFloat) {
            let y = clip.bounds.minY
            let row = table.row(at: NSPoint(x: 0, y: y))
            return (row, y - table.rect(ofRow: row).minY)
        }
        // A small upward movement used to snap back because "within 80 pt of
        // bottom" was mistaken for the user still following the newest answer.
        for distance in [CGFloat(40)] + Array(repeating: CGFloat(180), count: 8) {
            let y = max(0, clip.bounds.minY - distance)
            let entering = table.row(at: NSPoint(x: 0, y: y))
            if entering >= 0, entering < session.turns.count {
                #expect(ready(entering),
                        "进入下一段之前应已有排版好的视图")
            }
            clip.scroll(to: NSPoint(x: 0, y: y))
            table.enclosingScrollView?.reflectScrolledClipView(clip)
            host.layoutSubtreeIfNeeded()
            #expect(descendants(table).compactMap { $0 as? NSTextView }.contains { text in
                guard let layout = text.layoutManager, let container = text.textContainer else { return false }
                let glyphs = layout.usedRect(for: container).offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y)
                return text.convert(glyphs, to: table).intersects(table.visibleRect)
            }, "上滑后的首帧就应有正文，不能等下一次异步排版")
            let before = position()
            try await Task.sleep(for: .milliseconds(100))
            let after = position()
            #expect(after.row == before.row && abs(after.offset - before.offset) <= 2,
                    "预加载行高更新不能把阅读位置往下推：\(before) → \(after)")
            if entering >= 0, entering < session.turns.count {
                let row = try #require(table.view(atColumn: 0, row: entering, makeIfNecessary: false))
                let rowTexts = descendants(row).compactMap { ($0 as? NSTextView)?.string }
                #expect(rowTexts.contains("回答 \(entering)"),
                        "预备视图交接后仍应显示当前轮次，不能被清除或复用成另一轮")
            }
            checkTextHeights(in: host)
        }
        window.setContentSize(NSSize(width: 860, height: 720))
        try await Task.sleep(for: .milliseconds(200))
        checkTextHeights(in: host)
        for index in [0, 140, 30, 190, 0] {
            table.scrollRowToVisible(index)
            try await Task.sleep(for: .milliseconds(80))
            host.layoutSubtreeIfNeeded()
            let visibleText = descendants(host).compactMap { $0 as? NSTextView }.filter {
                guard !($0 is SubmitTextView), let layout = $0.layoutManager, let container = $0.textContainer else { return false }
                layout.ensureLayout(for: container)
                let glyphs = layout.usedRect(for: container).offsetBy(dx: $0.textContainerOrigin.x, dy: $0.textContainerOrigin.y)
                return $0.convert(glyphs, to: table).intersects(table.visibleRect)
            }
            #expect(!visibleText.isEmpty, "快速跳到历史的第 \(index) 轮不能整屏空白")
            checkTextHeights(in: host)
            #expect(coordinator.cachedRowCount <= 16, "反复翻阅不能积累整份历史的视图")
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

    @MainActor private func checkTextHeights(in root: NSView, sourceLocation: SourceLocation = #_sourceLocation) {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for text in descendants(root).compactMap({ $0 as? NSTextView }) where !(text is SubmitTextView) && !text.string.isEmpty && text.bounds.width > 1 {
            // Fresh TextKit layout is independent of the live view and SwiftUI's
            // width probes. Merely checking visibleRect was a false positive:
            // NSHostingView can propagate a visible rect outside the text bounds.
            let storage = NSTextStorage(attributedString: text.attributedString())
            let layout = NSLayoutManager()
            let container = NSTextContainer(size: NSSize(width: text.bounds.width, height: CGFloat.greatestFiniteMagnitude))
            container.lineFragmentPadding = text.textContainer?.lineFragmentPadding ?? 0
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            let expected = max(1, ceil(layout.usedRect(for: container).height))
            #expect(abs(text.bounds.height - expected) <= 2,
                    "文本实际行高 \(expected)，却占位 \(text.bounds.height)，会留下大块空白", sourceLocation: sourceLocation)
        }
    }
}
