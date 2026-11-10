import AppKit
import LinkPresentation
import PDFKit
import SwiftUI

/// The card shown while the pointer rests on a citation. Each kind of source shows what it is:
/// a lecture the words spoken at that moment, a PDF the page and the passage, a web page its site,
/// title and snippet, an earlier chat the question and answer. The cited words are marked.
struct CitationCard: View {
    var details: CitationDetails
    var citation: ChatCitation?
    var onOpen: () -> Void
    var onInside: (Bool) -> Void

    @State private var loadedExcerpt: String?
    @State private var picture: NSImage?
    @State private var icon: NSImage?
    @State private var playing = false
    @State private var copied = false

    static let width: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            content
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(AppColor.separator, lineWidth: 1)
        }
        .onHover(perform: onInside)
        .task(id: details.origin + details.place) { await load() }
        .onDisappear { if playing { MomentPlayer.shared.stop() } }
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            } else {
                Image(systemName: details.kind.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(details.kind == .missing ? AppColor.textSecondary : AppColor.accent)
                    .frame(width: 16)
            }
            (Text(details.origin).foregroundStyle(AppColor.textSecondary)
             + Text(details.place.isEmpty ? "" : " · ").foregroundStyle(AppColor.textSecondary)
             + Text(details.place).foregroundStyle(AppColor.accent).fontWeight(.semibold))
                .font(AppFont.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 6)
            if details.kind != .missing {
                Button(action: onOpen) {
                    HStack(spacing: 3) {
                        Text(details.kind == .lecture ? tr("跳到这一刻") : tr("打开"))
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                    }
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(AppColor.accent)
                }
                .buttonStyle(.plain.clicking())
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch details.kind {
        case .missing:
            Text(details.missing ?? "")
                .font(AppFont.secondary)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .lecture:
            passage(quoted: true)
            if !details.translation.isEmpty {
                Text(details.translation)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(3)
            }
            HStack(spacing: 8) {
                if details.hasAudio, let id = details.meetingID, let at = details.at {
                    smallButton(playing ? tr("正在播放…") : tr("播放这一刻"), symbol: playing ? "speaker.wave.2.fill" : "play.fill") {
                        if playing {
                            MomentPlayer.shared.stop()
                            playing = false
                        } else {
                            CitationLookup.playMoment?(id, at)
                            playing = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(MomentPlayer.clipSeconds))
                                playing = false
                            }
                        }
                    }
                }
                copyButton
            }
        case .pdf, .slides:
            HStack(alignment: .top, spacing: 10) {
                if let picture {
                    Image(nsImage: picture)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: details.kind == .slides ? 112 : 74)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(AppColor.outline.opacity(0.6), lineWidth: 0.5) }
                }
                passage(quoted: false)
            }
            copyButton
        case .picture:
            if let picture {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            passage(quoted: false)
        case .web:
            if let picture {
                Image(nsImage: picture)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.width - 28, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if !details.title.isEmpty {
                Text(details.title)
                    .font(AppFont.secondary.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
            }
            passage(quoted: false)
        case .chat:
            if !details.title.isEmpty {
                Text(details.title)
                    .font(AppFont.secondary.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(2)
            }
            passage(quoted: false)
        case .summary, .document:
            passage(quoted: false)
            if details.kind == .document { copyButton }
        }
    }

    /// The excerpt with the cited words marked; a lecture's words in quotation marks.
    @ViewBuilder
    private func passage(quoted: Bool) -> some View {
        let excerpt = details.excerpt.isEmpty ? (loadedExcerpt ?? "") : details.excerpt
        let text = excerpt.isEmpty ? details.quote : excerpt
        if !text.isEmpty {
            Text(Self.marked(text, quote: details.quote, quoted: quoted))
                .font(.system(size: 13))
                .lineSpacing(2)
                .lineLimit(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    static func marked(_ text: String, quote: String, quoted: Bool) -> AttributedString {
        var result = AttributedString(quoted ? "“\(text)”" : text)
        result.foregroundColor = AppColor.textPrimary
        let needle = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, needle.count < text.count || quoted, let range = result.range(of: needle) else { return result }
        result[range].backgroundColor = AppColor.selection
        result[range].foregroundColor = AppColor.textPrimary
        return result
    }

    private var copyButton: some View {
        let text = details.quote.isEmpty ? (details.excerpt.isEmpty ? loadedExcerpt ?? "" : details.excerpt) : details.quote
        return Group {
            if !text.isEmpty {
                smallButton(copied ? tr("已复制") : tr("复制引文"), symbol: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
            }
        }
    }

    private func smallButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                Text(title)
            }
            .font(.system(size: 12))
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain.clicking())
    }

    // MARK: Loading

    private func load() async {
        if details.excerpt.isEmpty, details.quote.isEmpty, let citation,
           [.pdf, .slides, .document].contains(details.kind) {
            loadedExcerpt = await CitationLookup.fileExcerpt?(citation)
        }
        switch details.kind {
        case .pdf:
            if let url = details.fileURL { picture = await PreviewImages.pdfPage(url, page: details.page ?? 1) }
        case .picture:
            if let url = details.fileURL { picture = await PreviewImages.picture(url) }
        case .slides, .document:
            if let url = details.fileURL { icon = NSWorkspace.shared.icon(forFile: url.path) }
        case .web:
            guard WebPreviews.enabled, let url = details.webURL else { return }
            let metadata = await WebPreviews.shared.metadata(for: url)
            icon = metadata?.icon
            picture = metadata?.image
        default:
            break
        }
    }
}

/// Small pictures for cards, made off the main thread and kept for the session.
enum PreviewImages {
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()  // NSCache is thread-safe.

    static func pdfPage(_ url: URL, page: Int) async -> NSImage? {
        let key = "\(url.path)#\(page)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let document = PDFDocument(url: url), let pdfPage = document.page(at: max(0, page - 1)) else { return nil }
            return pdfPage.thumbnail(of: CGSize(width: 220, height: 290), for: .cropBox)
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    static func picture(_ url: URL) async -> NSImage? {
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 640,
                  ] as CFDictionary) else { return nil }
            return NSImage(cgImage: thumb, size: NSSize(width: thumb.width / 2, height: thumb.height / 2))
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

/// A web page's icon and preview picture, through Apple's LinkPresentation. It contacts the site,
/// so it can be turned off in Settings; results are kept for the session.
@MainActor
final class WebPreviews {
    static let shared = WebPreviews()
    static let settingKey = "nomi.citations.webPreviews"

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    struct Metadata {
        var icon: NSImage?
        var image: NSImage?
    }

    private var done: [URL: Metadata] = [:]
    private var running: [URL: Task<Metadata?, Never>] = [:]

    func metadata(for url: URL) async -> Metadata? {
        if let hit = done[url] { return hit }
        if let task = running[url] { return await task.value }
        let task = Task<Metadata?, Never> { @MainActor in
            let provider = LPMetadataProvider()
            provider.timeout = 6
            guard let found = try? await provider.startFetchingMetadata(for: url) else { return nil }
            let iconProvider = found.iconProvider, imageProvider = found.imageProvider
            let icon = await Self.image(iconProvider)
            let image = await Self.image(imageProvider)
            return Metadata(icon: icon, image: image)
        }
        running[url] = task
        let result = await task.value
        running[url] = nil
        done[url] = result ?? Metadata()
        return result
    }

    private static func image(_ provider: NSItemProvider?) async -> NSImage? {
        guard let provider, provider.canLoadObject(ofClass: NSImage.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                continuation.resume(returning: object as? NSImage)
            }
        }
    }
}
