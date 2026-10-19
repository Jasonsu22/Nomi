import AppKit
import SwiftUI
import WebKit

struct AnswerBody: View {
    var source: String
    var streaming = false
    var citations: [ChatCitation] = []
    var onOpenCitation: (ChatCitation) -> Void = { _ in }
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if streaming {
                ForEach(Array(AnswerDocument.streamingPieces(in: source).enumerated()), id: \.offset) { _, piece in
                    switch piece {
                    case .text(let text):
                        Text(text)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .preparing:
                        Text(tr("正在准备图示…"))
                            .font(AppFont.secondary)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            } else {
                let pieces = AnswerDocument.pieces(in: source)
                if pieces.isEmpty {
                    answerText(AnswerInline.render(source, citations: linkedCitations))
                } else {
                    ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                        pieceView(piece)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var linkedCitations: [Int: ChatCitation] {
        ChatContext.linkedCitations(in: source, citations: citations)
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
        if scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
        }
    }

    /// The marker and the sentence share one text view, so their baselines match.
    private func listText(ordered: Bool, items: [String]) -> AttributedString {
        let font = NSFont.systemFont(ofSize: 15)
        let widest = ordered ? "\(max(items.count, 1))." : "•"
        let indent = ceil((widest as NSString).size(withAttributes: [.font: font]).width) + 8
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
        style.defaultTabInterval = indent
        style.headIndent = indent
        style.paragraphSpacing = 4
        let text = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            var marker = AttributedString(ordered ? "\(index + 1).\t" : "•\t")
            marker.font = Font.system(size: 15)
            marker.foregroundColor = AppColor.textSecondary
            text.append(NSAttributedString(marker))
            text.append(NSAttributedString(AnswerInline.render(item, citations: linkedCitations)))
            if index + 1 < items.count {
                text.append(NSAttributedString(string: "\n"))
            }
        }
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        return AttributedString(text)
    }

    private func answerText(_ text: AttributedString) -> some View {
        CiteText(attributed: text, citations: citations, colorScheme: colorScheme, onOpen: open)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pieceView(_ piece: AnswerDocument.Piece) -> some View {
        switch piece {
        case .heading(let level, let text):
            answerText(AnswerInline.render(text, size: level == 1 ? 17 : (level == 2 ? 15 : 13), weight: .semibold, citations: linkedCitations))
        case .paragraph(let text):
            answerText(AnswerInline.render(text, citations: linkedCitations))
        case .list(let ordered, let items):
            answerText(listText(ordered: ordered, items: items))
        case .code(let code):
            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(AppColor.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s2)
                .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: Radius.tag, style: .continuous))
        case .table(let header, let rows):
            Grid(alignment: .leading, horizontalSpacing: Space.s3, verticalSpacing: Space.s1) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        answerText(AnswerInline.render(cell, size: 13, weight: .semibold, citations: linkedCitations))
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            answerText(AnswerInline.render(cell, size: 13, citations: linkedCitations))
                        }
                    }
                }
            }
        case .widget(let title, let html):
            HtmlAnswerCard(
                title: title,
                html: AnswerDocument.page(
                    fragment: html,
                    text: colorScheme == .dark ? "#E6E8EB" : "#111418",
                    surface: colorScheme == .dark ? "#1F242B" : "#EBF0F6",
                    accent: colorScheme == .dark ? "#7CC4F2" : "#004A77"
                )
            )
        }
    }
}

private struct HtmlAnswerCard: View {
    var title: String
    var html: String
    @State private var height: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title.isEmpty ? tr("互动图示") : title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            HtmlAnswerWebView(html: html) { reported in
                height = reported
            }
            .frame(height: min(max(height, 44), 480))
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title.isEmpty ? tr("互动图示") : title)
    }
}

private struct HtmlAnswerWebView: NSViewRepresentable {
    var html: String
    var onHeight: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeight: onHeight)
    }

    func makeNSView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        content.add(context.coordinator, name: "nomi")
        content.addUserScript(WKUserScript(source: Self.heightScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = content
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.underPageBackgroundColor = .clear
        #if DEBUG
        webView.isInspectable = true
        #endif
        context.coordinator.load(html, into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onHeight = onHeight
        context.coordinator.load(html, into: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "nomi")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    private static let heightScript = """
    (function () {
      function report() {
        var body = document.body;
        var height = body ? Math.ceil(body.scrollHeight) : 0;
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nomi) {
          window.webkit.messageHandlers.nomi.postMessage({ height: height });
        }
      }
      if (window.ResizeObserver && document.body) new ResizeObserver(report).observe(document.body);
      document.addEventListener("input", function () { requestAnimationFrame(report); });
      document.addEventListener("click", function () { requestAnimationFrame(report); });
      report();
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var onHeight: (CGFloat) -> Void
        private var loaded: String?

        init(onHeight: @escaping (CGFloat) -> Void) {
            self.onHeight = onHeight
        }

        func load(_ html: String, into webView: WKWebView) {
            guard loaded != html else { return }
            loaded = html
            webView.loadHTMLString(html, baseURL: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "nomi",
                  let body = message.body as? [String: Any],
                  let height = (body["height"] as? NSNumber)?.doubleValue,
                  height.isFinite, height > 0 else { return }
            onHeight(CGFloat(height))
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            let scheme = navigationAction.request.url?.scheme?.lowercased()
            if navigationAction.navigationType == .other, scheme == nil || scheme == "about" {
                return .allow
            }
            return .cancel
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            let scheme = navigationResponse.response.url?.scheme?.lowercased()
            return scheme == nil || scheme == "about" ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }
    }
}

private struct CitePreview: Equatable {
    var title: String
    var host: String
    var detail: String
    var symbol: String
    var url: URL
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

private struct CitePreviewCard: View {
    var preview: CitePreview
    var onOpen: () -> Void
    var onInside: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: preview.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                Text(preview.host.isEmpty ? preview.title : preview.host)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: Space.s2)
                Button(action: onOpen) {
                    HStack(spacing: 3) {
                        Text(tr("打开"))
                        Image(systemName: "arrow.up.right")
                    }
                    .font(AppFont.caption.weight(.medium))
                    .foregroundStyle(AppColor.accent)
                }
                .buttonStyle(.plain.clicking())
            }
            if !preview.host.isEmpty, preview.title != preview.host {
                Text(preview.title)
                    .font(AppFont.secondary.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
            }
            if !preview.detail.isEmpty {
                Text(preview.detail)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(Space.s3)
        .frame(width: 300, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(AppColor.separator, lineWidth: 1)
        }
        .onHover(perform: onInside)
    }
}

/// Selectable answer text. A link uses the pointing hand, and shows its card while the pointer is over it.
private struct CiteText: NSViewRepresentable {
    var attributed: AttributedString
    var citations: [ChatCitation]
    var colorScheme: ColorScheme
    var onOpen: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpen: onOpen)
    }

    func makeNSView(context: Context) -> CiteTextView {
        let view = CiteTextView()
        view.drawsBackground = false
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.importsGraphics = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.focusRingType = .none
        view.delegate = context.coordinator
        view.hover = context.coordinator
        context.coordinator.apply(attributed, citations: citations, colorScheme: colorScheme, to: view)
        return view
    }

    func updateNSView(_ view: CiteTextView, context: Context) {
        context.coordinator.onOpen = onOpen
        view.hover = context.coordinator
        context.coordinator.apply(attributed, citations: citations, colorScheme: colorScheme, to: view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CiteTextView, context: Context) -> CGSize? {
        let proposed = proposal.width ?? .infinity
        let width = proposed.isFinite ? max(proposed, 1) : 10_000
        guard let container = nsView.textContainer, let layout = nsView.layoutManager else {
            return CGSize(width: width, height: 20)
        }
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return CGSize(width: width, height: max(ceil(used.height), 1))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onOpen: (URL) -> Void
        private var citations: [ChatCitation] = []
        private var colorScheme: ColorScheme = .light
        private var source: AttributedString?
        private var underlined: NSRange?
        private var shownURL: URL?
        private var pendingURL: URL?
        private var showTicket = 0
        private var closeTicket = 0
        private var pointerInsideCard = false
        private let popover = NSPopover()
        private let host = NSHostingController(rootView: AnyView(EmptyView()))

        init(onOpen: @escaping (URL) -> Void) {
            self.onOpen = onOpen
            super.init()
            popover.behavior = .applicationDefined
            popover.animates = false
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
        }

        func apply(_ attributed: AttributedString, citations: [ChatCitation], colorScheme: ColorScheme, to view: CiteTextView) {
            self.citations = citations
            let changed = source != attributed || self.colorScheme != colorScheme
            self.colorScheme = colorScheme
            source = attributed
            let color = CiteLink.accent(colorScheme)
            view.linkTextAttributes = [
                .foregroundColor: color,
                .underlineStyle: 0,
                .cursor: NSCursor.pointingHand,
            ]
            guard changed else { return }
            underlined = nil
            view.clearUnderline()
            view.textStorage?.setAttributedString(decorated(attributed, color: color))
            view.window?.invalidateCursorRects(for: view)
        }

        func hoverMoved(_ view: CiteTextView, at point: NSPoint?) {
            guard let point, let link = view.link(at: point) else {
                NSCursor.iBeam.set()
                pendingURL = nil
                showTicket += 1
                scheduleClose(view)
                return
            }
            NSCursor.pointingHand.set()
            cancelClose()
            view.underline(link.range)
            underlined = link.range
            if shownURL == link.url, popover.isShown { return }
            if pendingURL == link.url { return }
            if popover.isShown { closeCard() }
            pendingURL = link.url
            showTicket += 1
            let ticket = showTicket
            let preview = preview(for: link.url, label: link.label)
            let rect = link.rect
            Task { @MainActor [weak self, weak view] in
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, let view, self.showTicket == ticket, self.pendingURL == link.url else { return }
                self.present(preview, url: link.url, rect: rect, in: view)
            }
        }

        func hoverExited(_ view: CiteTextView) {
            NSCursor.iBeam.set()
            scheduleClose(view)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = CiteLink.url(from: link) else { return false }
            onOpen(url)
            close(textView)
            return true
        }

        private func scheduleClose(_ view: NSTextView?) {
            closeTicket += 1
            let ticket = closeTicket
            Task { @MainActor [weak self, weak view] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.closeTicket == ticket, !self.pointerInsideCard else { return }
                self.close(view)
            }
        }

        private func cancelClose() {
            closeTicket += 1
        }

        private func present(_ preview: CitePreview, url: URL, rect: CGRect, in view: CiteTextView) {
            pendingURL = nil
            shownURL = url
            host.rootView = AnyView(CitePreviewCard(preview: preview, onOpen: { [weak self, weak view] in
                self?.onOpen(url)
                self?.close(view)
            }, onInside: { [weak self, weak view] inside in
                guard let self else { return }
                self.pointerInsideCard = inside
                if inside { self.cancelClose() } else { self.scheduleClose(view) }
            }))
            popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        }

        private func closeCard() {
            shownURL = nil
            if popover.isShown { popover.performClose(nil) }
        }

        private func close(_ view: NSTextView?) {
            pendingURL = nil
            showTicket += 1
            pointerInsideCard = false
            if let cite = view as? CiteTextView {
                cite.clearUnderline()
            }
            underlined = nil
            closeCard()
        }

        private func preview(for url: URL, label: String) -> CitePreview {
            if let citation = citation(for: url) {
                let web = url.scheme == "http" || url.scheme == "https"
                let host = web ? CiteLink.host(url) : ""
                let title = citation.title.isEmpty || citation.title == host || citation.title == citation.url ? label : citation.title
                let detail = citation.detail == title || citation.detail == host || citation.detail == citation.url ? "" : citation.detail
                return CitePreview(title: title, host: host, detail: detail, symbol: citation.symbolName, url: url)
            }
            return CitePreview(
                title: label,
                host: CiteLink.host(url),
                detail: "",
                symbol: ChatCitation.symbolName(title: label, detail: "", url: url.absoluteString),
                url: url
            )
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

        private func decorated(_ source: AttributedString, color: NSColor) -> NSAttributedString {
            let text = NSMutableAttributedString(attributedString: NSAttributedString(source))
            var ranges: [NSRange] = []
            text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
                if value != nil { ranges.append(range) }
            }
            for range in ranges.reversed() {
                guard let url = CiteLink.url(from: text.attribute(.link, at: range.location, effectiveRange: nil)) else { continue }
                let label = text.attributedSubstring(from: range).string
                let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 15)
                let icon = icon(url: url, label: label, font: font, color: color)
                let gap = leadingGap(in: text, before: range.location, font: font)
                text.insert(gap, at: range.location)
                text.insert(icon, at: range.location + gap.length)
                let whole = NSRange(location: range.location + gap.length, length: range.length + icon.length)
                text.addAttribute(.link, value: url, range: whole)
                text.addAttribute(.foregroundColor, value: color, range: whole)
                text.addAttribute(.cursor, value: NSCursor.pointingHand, range: whole)
                text.removeAttribute(.underlineStyle, range: whole)
            }
            return text
        }

        /// One ordinary space before a link that sits against the previous word. The space stays outside the link.
        private func leadingGap(in text: NSAttributedString, before index: Int, font: NSFont) -> NSAttributedString {
            guard index > 0 else { return NSAttributedString() }
            let previous = (text.string as NSString).substring(with: NSRange(location: index - 1, length: 1))
            guard previous.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return NSAttributedString() }
            let color = text.attribute(.foregroundColor, at: index - 1, effectiveRange: nil) as? NSColor ?? NSColor.labelColor
            let gapFont = text.attribute(.font, at: index - 1, effectiveRange: nil) as? NSFont ?? font
            return NSAttributedString(string: " ", attributes: [.font: gapFont, .foregroundColor: color])
        }

        private func icon(url: URL, label: String, font: NSFont, color: NSColor) -> NSAttributedString {
            let symbol = citation(for: url)?.symbolName ?? ChatCitation.symbolName(title: label, detail: "", url: url.absoluteString)
            let config = NSImage.SymbolConfiguration(pointSize: font.pointSize * 0.86, weight: .semibold)
            guard let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
                return NSAttributedString()
            }
            let image = NSImage(size: symbolImage.size, flipped: false) { rect in
                color.setFill()
                rect.fill()
                symbolImage.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
                return true
            }
            image.isTemplate = false
            let attachment = NSTextAttachment()
            attachment.image = image
            // Same vertical center as the old capsule: the symbol sits in the middle of the line, not on the baseline.
            let y = (font.ascender + font.descender - image.size.height) / 2
            attachment.bounds = CGRect(x: 0, y: y, width: image.size.width, height: image.size.height)
            let result = NSMutableAttributedString(attachment: attachment)
            result.append(NSAttributedString(string: "\u{2009}", attributes: [.font: font]))
            return result
        }
    }
}

private final class CiteTextView: NSTextView {
    weak var hover: CiteText.Coordinator?
    private var tracking: NSTrackingArea?
    private var underlined: NSRange?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
        guard let layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 else { return }
        layoutManager.ensureLayout(for: container)
        let origin = textContainerOrigin
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil, range.length > 0 else { return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphs,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { rect, _ in
                var hit = rect
                hit.origin.x += origin.x
                hit.origin.y += origin.y
                self.addCursorRect(hit, cursor: .pointingHand)
            }
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if link(at: convert(event.locationInWindow, from: nil)) == nil {
            NSCursor.iBeam.set()
        } else {
            NSCursor.pointingHand.set()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        hover?.hoverMoved(self, at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hover?.hoverExited(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawDottedUnderline()
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let container = textContainer else { return }
        if abs(container.containerSize.width - newSize.width) > 0.5 {
            container.containerSize = NSSize(width: max(newSize.width, 1), height: CGFloat.greatestFiniteMagnitude)
            layoutManager?.ensureLayout(for: container)
        }
        window?.invalidateCursorRects(for: self)
    }

    func link(at point: NSPoint) -> (range: NSRange, rect: CGRect, url: URL, label: String)? {
        guard let layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let origin = textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let index = layoutManager.characterIndex(for: local, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < storage.length else { return nil }
        var range = NSRange()
        guard let url = CiteLink.url(from: storage.attribute(.link, at: index, effectiveRange: &range)) else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var hit: CGRect?
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphs,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: container
        ) { rect, stop in
            var box = rect
            box.origin.x += origin.x
            box.origin.y += origin.y
            let padded = box.insetBy(dx: -2, dy: -1)
            if padded.contains(point) {
                hit = box
                stop.pointee = true
            }
        }
        guard let hit else { return nil }
        let label = storage.attributedSubstring(from: range).string.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespaces)
        return (range, hit, url, label)
    }

    func underline(_ range: NSRange) {
        if underlined == range { return }
        underlined = range
        needsDisplay = true
    }

    func clearUnderline() {
        guard underlined != nil else { return }
        underlined = nil
        needsDisplay = true
    }

    /// Round dots, in the same color as the link text.
    private func drawDottedUnderline() {
        guard let underlined, let layoutManager, let container = textContainer, let storage = textStorage,
              underlined.length > 0, NSMaxRange(underlined) <= storage.length else { return }
        layoutManager.ensureLayout(for: container)
        let origin = textContainerOrigin
        storage.enumerateAttribute(.attachment, in: underlined) { value, subrange, _ in
            guard value == nil, subrange.length > 0 else { return }
            let color = storage.attribute(.foregroundColor, at: subrange.location, effectiveRange: nil) as? NSColor ?? .labelColor
            let font = storage.attribute(.font, at: subrange.location, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 15)
            let glyphs = layoutManager.glyphRange(forCharacterRange: subrange, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, _, lineGlyphs, _ in
                let slice = NSIntersectionRange(glyphs, lineGlyphs)
                guard slice.length > 0 else { return }
                let bounds = layoutManager.boundingRect(forGlyphRange: slice, in: container)
                let baseline = origin.y + lineRect.minY + layoutManager.location(forGlyphAt: slice.location).y
                let drop = max(-font.underlinePosition, 1)
                color.setFill()
                self.fillDots(from: origin.x + bounds.minX, to: origin.x + bounds.maxX, centerY: baseline + drop)
            }
        }
    }

    private func fillDots(from left: CGFloat, to right: CGFloat, centerY: CGFloat) {
        let diameter: CGFloat = 1.5
        let pitch: CGFloat = 2.5
        guard right - left >= diameter * 0.6 else { return }
        var center = left + diameter / 2
        let limit = right - diameter / 2
        while center <= limit + 0.01 {
            NSBezierPath(ovalIn: NSRect(x: center - diameter / 2, y: centerY - diameter / 2, width: diameter, height: diameter)).fill()
            center += pitch
        }
    }
}
