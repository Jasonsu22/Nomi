import AppKit
import SwiftUI
import WebKit

/// One answer, drawn as a single web page (AnswerWeb/answer.html): Markdown through markdown-it,
/// formulas through KaTeX. The whole answer is one piece of text, so a selection can run from the
/// first line to the last. Demo cards run inside the same page, each in its own sandboxed frame.
struct AnswerBody: View {
    var source: String
    var streaming = false
    var citations: [ChatCitation] = []
    var onOpenCitation: (ChatCitation) -> Void = { _ in }
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let prepared = streaming
            ? Self.prepare(source, streaming: true, citations: citations)
            : AnswerPreparedCache.prepared(source, citations: citations) {
                Self.prepare(source, streaming: false, citations: citations)
            }
        AnswerWebView(
            payload: payload(prepared),
            heightKey: source,
            citations: citations,
            onOpen: open
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Parses the answer once and derives its files and citation numbers from that one pass.
    static func prepare(_ source: String, streaming: Bool, citations: [ChatCitation]) -> AnswerPrepared {
        let pieces = AnswerDocument.pieces(in: source, streaming: streaming)
        // Streaming keeps the existing parser mode for partially completed fences.
        // Finished answers reuse the pieces above instead of parsing the whole answer twice.
        let export = streaming ? ChatFiles.export(source) : ChatFiles.export(pieces)
        return AnswerPrepared(
            rows: rows(pieces, widgets: export.widgets),
            export: export,
            citations: ChatContext.linkedCitations(in: source, citations: citations)
        )
    }

    /// Everything the page needs to draw this answer, as plain values for JavaScript.
    private func payload(_ prepared: AnswerPrepared) -> [String: Any] {
        let dark = colorScheme == .dark
        var widgets: [[String: String]] = []
        for row in prepared.rows {
            guard case .widget(let title, let html) = row.piece else { continue }
            widgets.append([
                "title": title,
                "page": AnswerDocument.page(
                    fragment: html,
                    text: dark ? "#E6E8EB" : "#111418",
                    surface: dark ? "#1F242B" : "#EBF0F6",
                    accent: dark ? "#7CC4F2" : "#004A77"
                ),
                "file": row.file?.absoluteString ?? "",
            ])
        }
        return [
            "markdown": source,
            "streaming": streaming,
            "dark": dark,
            "citations": Self.citationChips(prepared.citations),
            "sources": streaming ? [] : Self.sourceRow(prepared.citations),
            "sourcesLabel": trf("来自 %d 个来源", Self.sourceRow(prepared.citations).count),
            "files": prepared.export.named.mapValues(\.absoluteString),
            "widgets": widgets,
            "fenceRoles": AnswerDocument.fenceRoles(in: source, streaming: streaming).map(\.rawValue),
            "preparing": tr("正在准备图示…"),
            "cardTitle": tr("互动图示"),
        ]
    }

    /// The chip for each citation number. When every source is from one meeting, chips name the
    /// moment (8:41) instead of repeating the meeting title, as AnswerInline does.
    static func citationChips(_ citations: [Int: ChatCitation]) -> [String: [String: String]] {
        let meetings = Set(citations.values.compactMap(\.meetingID))
        let oneMeeting = meetings.count == 1 && citations.values.allSatisfy { $0.meetingID != nil }
        var chips: [String: [String: String]] = [:]
        for (number, citation) in citations {
            guard !citation.inlineLabel.isEmpty, let url = citation.inlineURL else { continue }
            let moment = citation.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            chips[String(number)] = [
                "label": oneMeeting && !moment.isEmpty ? moment : citation.inlineLabel,
                "key": AnswerInline.citationSourceKey(citation),
                "url": url.absoluteString,
                "kind": chipKind(citation),
            ]
        }
        return chips
    }

    /// The icon a citation chip shows, named for the page's stylesheet.
    static func chipKind(_ citation: ChatCitation) -> String {
        switch CitationKind.of(citation) {
        case .lecture: "lecture"
        case .summary: "summary"
        case .pdf, .document, .missing: "doc"
        case .slides: "slides"
        case .picture: "photo"
        case .web: "web"
        case .chat: "chat"
        }
    }

    /// Each distinct source the answer cites, in the order first cited, for the row above it.
    /// Shown when an answer draws on two or more.
    static func sourceRow(_ citations: [Int: ChatCitation]) -> [[String: String]] {
        var seen = Set<String>()
        var row: [[String: String]] = []
        for number in citations.keys.sorted() {
            guard let citation = citations[number], let url = citation.inlineURL else { continue }
            let key = AnswerInline.citationSourceKey(citation)
            guard seen.insert(key).inserted else { continue }
            let label: String
            switch CitationKind.of(citation) {
            case .lecture, .summary: label = citation.title
            case .chat: label = trf("对话 · %@", citation.title)
            case .web, .missing: label = url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? citation.inlineLabel
            default: label = citation.title
            }
            // The row names whole sources, so a meeting shows as a lecture even when its summary was cited.
            let kind = CitationKind.of(citation) == .summary ? "lecture" : chipKind(citation)
            row.append(["url": url.absoluteString, "kind": kind, "label": label.isEmpty ? citation.inlineLabel : label])
        }
        return row.count >= 2 ? row : []
    }

    private func open(_ url: URL) {
        let scheme = url.scheme?.lowercased()
        if scheme == "nomi-cite" {
            let token = url.host ?? String(url.path.drop(while: { $0 == "/" }))
            if let id = UUID(uuidString: token), let citation = citations.first(where: { $0.id == id }) {
                onOpenCitation(citation)
            }
            return
        }
        if url.isFileURL {
            AnswerLinkActions.openFile(url)
            return
        }
        if scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
        }
    }

    private static func rows(_ pieces: [AnswerDocument.Piece], widgets: [URL]) -> [AnswerPrepared.Row] {
        var index = 0
        return pieces.map { piece in
            guard case .widget = piece, index < widgets.count else { return AnswerPrepared.Row(piece: piece, file: nil) }
            let file = widgets[index]
            index += 1
            return AnswerPrepared.Row(piece: piece, file: file)
        }
    }
}

/// Heights of answers already drawn, so a row scrolled back into view starts at its real size.
@MainActor
enum AnswerHeights {
    private static var heights: [String: CGFloat] = [:]
    private static var order: [String] = []

    static func height(for key: String) -> CGFloat? { heights[key] }

    static func remember(_ height: CGFloat, for key: String) {
        if heights.updateValue(height, forKey: key) == nil {
            order.append(key)
            if order.count > 400 { heights[order.removeFirst()] = nil }
        }
    }
}

private struct AnswerWebView: View {
    var payload: [String: Any]
    var heightKey: String
    var citations: [ChatCitation]
    var onOpen: (URL) -> Void
    @State private var height: CGFloat?

    var body: some View {
        AnswerPage(payload: payload, citations: citations, onOpen: onOpen) { reported in
            height = reported
            AnswerHeights.remember(reported, for: heightKey)
        }
        .frame(height: max(height ?? AnswerHeights.height(for: heightKey) ?? 22, 22))
    }
}

/// The page never scrolls on its own: vertical scrolling moves the chat, while mostly sideways
/// gestures stay with the page for wide formulas, tables and code.
private final class AnswerWeb: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX), let next = nextResponder {
            next.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    // MARK: Selecting past the edge
    // The page is as tall as the answer, so WebKit has nothing of its own to scroll when a selection
    // drag leaves the visible chat. The chat around it scrolls instead, and keeps scrolling while the
    // pointer stays outside, with each step extending the selection.

    private var dragTimer: Timer?

    override func mouseDown(with event: NSEvent) {
        stopDragScrolling()
        // Control-click is a right-click too.
        if event.modifierFlags.contains(.control), let file = card(at: event) {
            NSMenu.popUpContextMenu(AnswerMenus.file(file), with: event, for: self)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        scrollChat(following: event)
        guard dragTimer == nil else { return }
        dragTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.continueDragScrolling() }
        }
    }

    override func mouseUp(with event: NSEvent) {
        stopDragScrolling()
        super.mouseUp(with: event)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopDragScrolling() }
        super.viewWillMove(toWindow: newWindow)
    }

    /// While the button is held with the pointer still outside, keep scrolling and extend the selection.
    private func continueDragScrolling() {
        guard NSEvent.pressedMouseButtons & 1 == 1, let window,
              let drag = NSEvent.mouseEvent(
                  with: .leftMouseDragged,
                  location: window.mouseLocationOutsideOfEventStream,
                  modifierFlags: NSEvent.modifierFlags,
                  timestamp: ProcessInfo.processInfo.systemUptime,
                  windowNumber: window.windowNumber,
                  context: nil,
                  eventNumber: 0,
                  clickCount: 1,
                  pressure: 1
              ) else {
            stopDragScrolling()
            return
        }
        if scrollChat(following: drag) { super.mouseDragged(with: drag) }
    }

    /// Scrolls the chat when the pointer is beyond its visible edge. Returns whether it moved.
    @discardableResult
    private func scrollChat(following event: NSEvent) -> Bool {
        guard let clip = enclosingScrollView?.contentView else { return false }
        let before = clip.bounds.origin
        _ = clip.autoscroll(with: event)
        guard clip.bounds.origin != before else { return false }
        enclosingScrollView?.reflectScrolledClipView(clip)
        return true
    }

    private func stopDragScrolling() {
        dragTimer?.invalidate()
        dragTimer = nil
    }

    /// Demo cards in the page and the files they were saved to, in page coordinates.
    var cards: [(rect: CGRect, file: URL)] = []

    private func card(at event: NSEvent) -> URL? {
        let point = convert(event.locationInWindow, from: nil)
        let pagePoint = CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
        return cards.first { $0.rect.contains(pagePoint) }?.file
    }

    /// Right-clicking a demo card shows the menu for its saved file. The click is caught here,
    /// before WebKit hands it to the card's sandboxed frame, which has no menu of its own.
    override func rightMouseDown(with event: NSEvent) {
        guard let file = card(at: event) else { return super.rightMouseDown(with: event) }
        NSMenu.popUpContextMenu(AnswerMenus.file(file), with: event, for: self)
    }

    /// Elsewhere, Copy, Look Up and Translate stay; page navigation items make no sense for an answer.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        let dropped = ["Reload", "GoBack", "GoForward", "OpenLinkInNewWindow", "OpenImageInNewWindow",
                       "OpenFrameInNewWindow", "DownloadImage", "DownloadLinkedFile", "OpenMediaInNewWindow"]
        for item in menu.items where dropped.contains(where: { item.identifier?.rawValue.contains($0) == true }) {
            menu.removeItem(item)
        }
        super.willOpenMenu(menu, with: event)
    }
}

private struct AnswerPage: NSViewRepresentable {
    var payload: [String: Any]
    var citations: [ChatCitation]
    var onOpen: (URL) -> Void
    var onHeight: (CGFloat) -> Void

    static let pageURL = Bundle.module.url(forResource: "answer", withExtension: "html", subdirectory: "AnswerWeb")

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AnswerWeb {
        let content = WKUserContentController()
        content.add(context.coordinator, name: "nomi")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = content
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.suppressesIncrementalRendering = false
        let webView = AnswerWeb(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        context.coordinator.webView = webView
        update(context.coordinator)
        if let page = Self.pageURL {
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: AnswerWeb, context: Context) {
        update(context.coordinator)
        context.coordinator.render()
    }

    private func update(_ coordinator: Coordinator) {
        coordinator.payload = payload
        coordinator.citations = citations
        coordinator.onOpen = onOpen
        coordinator.onHeight = onHeight
    }

    static func dismantleNSView(_ webView: AnswerWeb, coordinator: Coordinator) {
        coordinator.closeCard()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "nomi")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: AnswerWeb?
        var payload: [String: Any] = [:]
        var citations: [ChatCitation] = []
        var onOpen: (URL) -> Void = { _ in }
        var onHeight: (CGFloat) -> Void = { _ in }
        private var ready = false
        private var rendered: NSDictionary?
        private var card: CitationCardPanel?
        private var pointerInsideCard = false
        private var closeTicket = 0

        func render() {
            guard ready, let webView else { return }
            let next = payload as NSDictionary
            if let rendered, rendered.isEqual(next) { return }
            rendered = next
            webView.callAsyncJavaScript("nomi.render(payload)", arguments: ["payload": payload], in: nil, in: .page, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // Demo cards run in frames of this page; only the page itself may talk to the app.
            guard message.name == "nomi", message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
            if body["ready"] != nil {
                ready = true
                rendered = nil
                render()
            } else if let height = (body["height"] as? NSNumber)?.doubleValue, height.isFinite, height >= 0 {
                onHeight(CGFloat(height))
            } else if let raw = body["open"] as? String, let url = URL(string: raw) {
                closeCard()
                onOpen(url)
            } else if let raw = body["hover"] as? String, let url = URL(string: raw),
                      let rect = body["rect"] as? [NSNumber], rect.count == 4 {
                showCard(url: url, label: body["label"] as? String ?? "", rect: rect.map { CGFloat($0.doubleValue) })
            } else if body["escape"] != nil {
                closeCard()
            } else if body["unhover"] != nil {
                // Moving onto another citation closes this card at once; the next waits its own turn.
                if body["now"] != nil, !pointerInsideCard { closeCard() } else { scheduleClose() }
            } else if let cards = body["cards"] as? [[Any]] {
                webView?.cards = cards.compactMap { card in
                    let values = card.prefix(4).compactMap { ($0 as? NSNumber).map { CGFloat($0.doubleValue) } }
                    guard card.count == 5, values.count == 4, let raw = card[4] as? String, let file = URL(string: raw) else { return nil }
                    return (CGRect(x: values[0], y: values[1], width: values[2], height: values[3]), file)
                }
            }
        }

        // MARK: Source preview card

        private func showCard(url: URL, label: String, rect: [CGFloat]) {
            guard let webView else { return }
            closeTicket += 1
            guard let window = webView.window else { return }
            let card = self.card ?? CitationCardPanel()
            self.card = card
            let cited = citation(for: url)
            let details = cited.flatMap { CitationLookup.details?($0) }
                ?? CitationDetails(kind: .web, origin: CiteLink.host(url), title: label == CiteLink.host(url) ? "" : label, webURL: url)
            let view = CitationCard(details: details, citation: cited, onOpen: { [weak self] in
                self?.closeCard()
                self?.onOpen(url)
            }, onInside: { [weak self] inside in
                guard let self else { return }
                self.pointerInsideCard = inside
                if inside { self.closeTicket += 1 } else { self.scheduleClose() }
            })
            // The page reports CSS pixels from its top-left corner; the web view is flipped the same way.
            let anchor = CGRect(x: rect[0], y: rect[1], width: max(rect[2], 1), height: max(rect[3], 1))
            let onScreen = window.convertToScreen(webView.convert(anchor, to: nil))
            card.show(view, under: onScreen, in: window)
        }

        private func scheduleClose() {
            closeTicket += 1
            let ticket = closeTicket
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.closeTicket == ticket, !self.pointerInsideCard else { return }
                self.closeCard()
            }
        }

        func closeCard() {
            pointerInsideCard = false
            card?.hide()
        }

        private func citation(for url: URL) -> ChatCitation? {
            if url.scheme == "nomi-cite", let id = UUID(uuidString: url.host ?? "") {
                return citations.first { $0.id == id }
            }
            return citations.first { citation in
                guard let raw = citation.url, let parsed = URL(string: raw) else { return false }
                return parsed.absoluteString == url.absoluteString
            }
        }

        // MARK: Navigation: only the answer page itself and its demo frames load

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            let url = navigationAction.request.url
            let scheme = url?.scheme?.lowercased()
            if navigationAction.targetFrame?.isMainFrame == true {
                return url?.isFileURL == true && url?.lastPathComponent == "answer.html" ? .allow : .cancel
            }
            return scheme == "data" || scheme == "about" ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }

        /// A page that was closed by the system (memory pressure) is loaded again and redrawn.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            ready = false
            if let page = AnswerPage.pageURL {
                webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
            }
        }
    }
}

private enum CiteLink {
    static func host(_ url: URL) -> String {
        guard let host = url.host, !host.isEmpty else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func url(from value: Any?) -> URL? {
        if let url = value as? URL { return url }
        if let text = value as? String { return URL(string: text) }
        return nil
    }

    static func accent(_ scheme: ColorScheme) -> NSColor {
        scheme == .dark
            ? NSColor(srgbRed: 124 / 255, green: 196 / 255, blue: 242 / 255, alpha: 1)
            : NSColor(srgbRed: 0, green: 74 / 255, blue: 119 / 255, alpha: 1)
    }
}

/// One answer after parsing: the blocks to show, the files they open, and the citation numbers.
struct AnswerPrepared: Equatable {
    struct Row: Equatable {
        var piece: AnswerDocument.Piece
        var file: URL?
    }

    var rows: [Row]
    var export: ChatFiles.Export
    var citations: [Int: ChatCitation]
}

/// Finished answers do not change, so a chat shown again reuses its parsed form instead of
/// parsing the Markdown and checking its exported files on every view update.
@MainActor
enum AnswerPreparedCache {
    private struct Entry {
        var citations: [ChatCitation]
        var prepared: AnswerPrepared
    }

    /// Bounded by the characters of the cached answers, oldest first out.
    static let characterLimit = 4_000_000
    private static var entries: [String: Entry] = [:]
    private static var order: [String] = []
    private static var characters = 0

    static func prepared(_ source: String, citations: [ChatCitation], make: () -> AnswerPrepared) -> AnswerPrepared {
        // Exported interactive files can be removed outside the app; export again if one is gone.
        if let entry = entries[source], entry.citations == citations,
           entry.prepared.export.widgets.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
            return entry.prepared
        }
        let prepared = make()
        if entries.updateValue(Entry(citations: citations, prepared: prepared), forKey: source) == nil {
            order.append(source)
            characters += source.utf16.count
        }
        while characters > characterLimit, order.count > 1 {
            let oldest = order.removeFirst()
            entries[oldest] = nil
            characters -= oldest.utf16.count
        }
        return prepared
    }

    static var count: Int { entries.count }

    static func removeAll() {
        entries.removeAll()
        order.removeAll()
        characters = 0
    }
}
