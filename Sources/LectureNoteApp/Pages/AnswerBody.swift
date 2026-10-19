import AppKit
import SwiftUI
import WebKit

struct AnswerBody: View {
    var source: String
    var streaming = false
    var citations: [ChatCitation] = []
    var onOpenCitation: (ChatCitation) -> Void = { _ in }
    @Environment(\.colorScheme) private var colorScheme

    private var linked: [Int: ChatCitation] {
        ChatContext.linkedCitations(in: source, citations: citations)
    }

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
                    answerText(AnswerInline.render(source, citations: linked))
                } else {
                    ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                        pieceView(piece)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            open(url)
            return .handled
        })
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

    private func answerText(_ text: AttributedString) -> some View {
        AnswerText(attributed: text, onOpen: open)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pieceView(_ piece: AnswerDocument.Piece) -> some View {
        switch piece {
        case .heading(let level, let text):
            answerText(AnswerInline.render(text, size: level == 1 ? 17 : (level == 2 ? 15 : 13), weight: .semibold, citations: linked))
        case .paragraph(let text):
            answerText(AnswerInline.render(text, citations: linked))
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textSecondary)
                        answerText(AnswerInline.render(item, citations: linked))
                    }
                }
            }
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
                        answerText(AnswerInline.render(cell, size: 13, weight: .semibold, citations: linked))
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            answerText(AnswerInline.render(cell, size: 13, citations: linked))
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

/// Selectable answer text. Ordinary characters keep the text cursor; a link uses the pointing hand.
private struct AnswerText: NSViewRepresentable {
    var attributed: AttributedString
    var onOpen: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpen: onOpen)
    }

    func makeNSView(context: Context) -> LinkTextView {
        let view = LinkTextView()
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
        view.textStorage?.setAttributedString(NSAttributedString(attributed))
        return view
    }

    func updateNSView(_ view: LinkTextView, context: Context) {
        context.coordinator.onOpen = onOpen
        let next = NSAttributedString(attributed)
        if view.attributedString() != next {
            view.textStorage?.setAttributedString(next)
        }
        view.window?.invalidateCursorRects(for: view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LinkTextView, context: Context) -> CGSize? {
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

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onOpen: (URL) -> Void

        init(onOpen: @escaping (URL) -> Void) {
            self.onOpen = onOpen
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url: URL?
            if let value = link as? URL {
                url = value
            } else if let value = link as? String {
                url = URL(string: value)
            } else {
                url = nil
            }
            guard let url else { return false }
            onOpen(url)
            return true
        }
    }
}

private final class LinkTextView: NSTextView {
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
}
