import AppKit
import SwiftUI
import WebKit

struct AnswerBody: View {
    var source: String
    var streaming = false
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
                    Text(source)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                        pieceView(piece)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func pieceView(_ piece: AnswerDocument.Piece) -> some View {
        switch piece {
        case .heading(let level, let text):
            Text(AnswerInline.render(text, size: level == 1 ? 17 : (level == 2 ? 15 : 13), weight: .semibold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let text):
            Text(AnswerInline.render(text))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: Space.s1) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textSecondary)
                        Text(AnswerInline.render(item))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        Text(AnswerInline.render(cell, size: 13, weight: .semibold))
                            .textSelection(.enabled)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(AnswerInline.render(cell, size: 13))
                                .textSelection(.enabled)
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
