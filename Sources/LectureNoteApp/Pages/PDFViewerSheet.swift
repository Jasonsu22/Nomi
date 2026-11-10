import AppKit
import PDFKit
import SwiftUI

/// A cited PDF, opened at the cited page with the quoted words marked. Preview and other apps can't
/// be told a page, so Nomi shows it itself and offers the default app next to it.
struct PDFViewerRequest: Identifiable, Equatable {
    var id = UUID()
    var url: URL
    var page: Int?
    var quote: String?
}

extension AppModel {
    func showPDF(_ url: URL, page: Int?, quote: String?) {
        pdfViewer = PDFViewerRequest(url: url, page: page, quote: quote)
    }
}

struct PDFViewerSheet: View {
    var request: PDFViewerRequest
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.s2) {
                Image(systemName: "doc.richtext").foregroundStyle(AppColor.accent)
                Text(request.url.lastPathComponent)
                    .font(AppFont.sectionTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let page = request.page {
                    Text(trf("第 %d 页", page))
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                Button(tr("在默认应用中打开")) { NSWorkspace.shared.open(request.url) }
                    .buttonStyle(.bordered.clicking())
                Button(tr("完成"), action: onClose)
                    .buttonStyle(.borderedProminent.clicking())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Space.s4)
            Divider()
            PDFPageView(request: request)
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 560, idealHeight: 820)
        .background(AppColor.surface)
    }
}

private struct PDFPageView: NSViewRepresentable {
    var request: PDFViewerRequest

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = NSColor.windowBackgroundColor
        guard let document = PDFDocument(url: request.url) else { return view }
        view.document = document
        if let number = request.page, let page = document.page(at: max(0, number - 1)) {
            // After layout, or the view scrolls back to the first page.
            DispatchQueue.main.async {
                view.go(to: page)
                if let selection = Self.find(request.quote, in: document, on: page) {
                    selection.color = NSColor.systemYellow.withAlphaComponent(0.45)
                    view.highlightedSelections = [selection]
                    view.go(to: selection)
                }
            }
        }
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}

    /// The quote on its page, or its first words when the PDF's text differs a little from the quote.
    private static func find(_ quote: String?, in document: PDFDocument, on page: PDFPage) -> PDFSelection? {
        guard let quote = quote?.trimmingCharacters(in: .whitespacesAndNewlines), !quote.isEmpty else { return nil }
        for candidate in [quote, String(quote.prefix(60)), String(quote.prefix(24))] where candidate.count >= 6 {
            if let hit = document.findString(candidate, withOptions: [.caseInsensitive]).first(where: { $0.pages.contains(page) }) {
                return hit
            }
        }
        return nil
    }
}
