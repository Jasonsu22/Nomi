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
    @State private var playRun: UUID?
    @State private var copied = false

    static let width: CGFloat = 340
    /// A lecture's words and translation scroll past this height.
    static let lectureHeight: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            content
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppColor.separator, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            Scrolling(maxHeight: Self.lectureHeight) {
                VStack(alignment: .leading, spacing: 9) {
                    passage(quoted: true, lineLimit: nil)
                    if !details.translation.isEmpty {
                        Text(Self.marked(details.translation, quote: details.translationQuote, quoted: false, base: AppColor.textSecondary, markWhole: true))
                            .font(.system(size: 12))
                            .lineSpacing(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            HStack(spacing: 8) {
                if details.hasAudio, let id = details.meetingID, let at = details.at {
                    smallButton(playing ? tr("正在播放…") : tr("播放这一刻"), symbol: playing ? "speaker.wave.2.fill" : "play.fill") {
                        if playing {
                            MomentPlayer.shared.stop()
                            playing = false
                        } else if let seconds = CitationLookup.playMoment?(id, at, details.until) {
                            // Plays all the cited words; the button turns back when they end.
                            let run = UUID()
                            playRun = run
                            playing = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(seconds))
                                if playRun == run { playing = false }
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
    private func passage(quoted: Bool, lineLimit: Int? = 9) -> some View {
        let excerpt = details.excerpt.isEmpty ? (loadedExcerpt ?? "") : details.excerpt
        let text = excerpt.isEmpty ? details.quote : excerpt
        if !text.isEmpty {
            Text(Self.marked(text, quote: details.quote, quoted: quoted))
                .font(.system(size: 13))
                .lineSpacing(2)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    /// `markWhole` marks the quote even when it is all of `text`, as for a one-sentence translation.
    static func marked(_ text: String, quote: String, quoted: Bool, base: Color = AppColor.textPrimary, markWhole: Bool = false) -> AttributedString {
        var result = AttributedString(quoted ? "“\(text)”" : text)
        result.foregroundColor = base
        let needle = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, needle.count < text.count || quoted || markWhole, let range = result.range(of: needle) else { return result }
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

/// Content as tall as it needs, up to `maxHeight`; past that it scrolls. The hidden copy sets the
/// height, so the card's window is sized right on its first frame.
private struct Scrolling<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .hidden()
            .frame(maxHeight: maxHeight, alignment: .top)
            .overlay(alignment: .top) {
                ScrollView(.vertical) {
                    content
                }
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
            }
            .accessibilityElement(children: .contain)
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

/// The card's shadow, with room around it inside the panel. The card keeps to the edge that faces
/// the citation, so a part that arrives late (a site icon, a picture) grows it away from the citation
/// instead of re-centring the words, and the panel is resized to fit.
private struct CardChrome<Content: View>: View {
    var content: Content
    var pinTop: Bool
    var onSize: (CGSize) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
            .compositingGroup()
            .shadow(color: .black.opacity(dark ? 0.5 : 0.16), radius: 16, x: 0, y: 12)
            .shadow(color: .black.opacity(dark ? 0.35 : 0.08), radius: 3, x: 0, y: 2)
            .padding(CitationCardPanel.shadowRoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pinTop ? .top : .bottom)
    }
}

/// A borderless, see-through window that holds the citation card above the chat. Unlike a popover
/// it has no arrow or system frame, and it can fade and rise like the preview page
/// (`Design/Previews/citation-preview.html`): 0.14 s, rising 4 pt.
///
/// The fade and rise run in Core Animation on the layer that holds the whole card, so the card is
/// drawn once and moved as one picture. Animating it in SwiftUI instead redraws the words at every
/// in-between position, snapped to whole pixels, so they trail the box and settle a moment late.
@MainActor
final class CitationCardPanel {
    static let shadowRoom: CGFloat = 32
    static let gap: CGFloat = 8
    static let fade = 0.14
    static let rise: CGFloat = 4

    private let panel: NSPanel
    private let box = NSView()
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var hiding: Task<Void, Never>?
    private var shown = false
    /// The card is under the citation (true) or above it, which decides the edge kept still on a resize.
    private var below = true

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        box.wantsLayer = true
        host.sizingOptions = [.intrinsicContentSize]  // For `fittingSize`; the panel itself is sized by hand.
        host.autoresizingMask = [.width, .height]
        box.addSubview(host)
        panel.contentView = box
    }

    var isShown: Bool { panel.isVisible && shown }

    /// Shows `card` under `anchor` (in screen coordinates), or above it when there is no room below.
    func show(_ card: some View, under anchor: CGRect, in window: NSWindow) {
        hiding?.cancel()
        hiding = nil
        let scheme: ColorScheme = window.effectiveAppearance.isDark ? .dark : .light
        panel.appearance = window.effectiveAppearance
        func root(pinTop: Bool) -> AnyView {
            AnyView(CardChrome(content: card, pinTop: pinTop) { [weak self] size in
                DispatchQueue.main.async { self?.refit(cardHeight: size.height) }
            }.environment(\.colorScheme, scheme))
        }
        host.rootView = root(pinTop: true)
        let size = host.fittingSize
        let room = Self.shadowRoom
        let area = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        var x = anchor.midX - size.width / 2
        x = min(max(x, area.minX + 8 - room), area.maxX - size.width - 8 + room)
        // Below the citation: the card's top edge sits `gap` under it.
        var y = anchor.minY - Self.gap + room - size.height
        below = y + room >= area.minY + 8
        if !below {
            y = anchor.maxY + Self.gap - room
            host.rootView = root(pinTop: false)
        }
        let frame = CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
        panel.setFrame(frame, display: false)
        box.frame = CGRect(origin: .zero, size: frame.size)
        host.frame = box.bounds
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        if !shown, !panel.isVisible { setLayer(visible: false) }
        // Draw the card fully before it appears, so the first frame of the fade already has the words.
        host.layoutSubtreeIfNeeded()
        panel.display()
        panel.orderFront(nil)
        shown = true
        animate(visible: true)
    }

    func hide() {
        guard panel.isVisible, hiding == nil else { return }
        shown = false
        animate(visible: false)
        hiding = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(Self.fade * 1000) + 20))
            guard let self, !Task.isCancelled else { return }
            self.panel.parent?.removeChildWindow(self.panel)
            self.panel.orderOut(nil)
            self.host.rootView = AnyView(EmptyView())
            self.hiding = nil
        }
    }

    /// Fits the panel to the card when a late part changes its height, keeping the edge next to the
    /// citation where it is.
    private func refit(cardHeight: CGFloat) {
        guard shown else { return }
        let height = (cardHeight + Self.shadowRoom * 2).rounded(.up)
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        if below { frame.origin.y = frame.maxY - height }
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    private var hiddenTransform: CATransform3D {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? CATransform3DIdentity
            : CATransform3DMakeTranslation(0, -Self.rise, 0)  // Layers count y upward: this is 4 pt lower.
    }

    private func setLayer(visible: Bool) {
        guard let layer = box.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.opacity = visible ? 1 : 0
        layer.sublayerTransform = visible ? CATransform3DIdentity : hiddenTransform
        CATransaction.commit()
    }

    /// Fades and moves the whole card from wherever it is now, so a reversal mid-fade doesn't jump.
    private func animate(visible: Bool) {
        guard let layer = box.layer else { return }
        let now = layer.presentation() ?? layer
        let fromOpacity = now.opacity, fromTransform = now.sublayerTransform
        let toOpacity: Float = visible ? 1 : 0
        let toTransform = visible ? CATransform3DIdentity : hiddenTransform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = toOpacity
        layer.sublayerTransform = toTransform
        // CSS `ease`, as on the preview page.
        let timing = CAMediaTimingFunction(name: .default)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = toOpacity
        let move = CABasicAnimation(keyPath: "sublayerTransform")
        move.fromValue = NSValue(caTransform3D: fromTransform)
        move.toValue = NSValue(caTransform3D: toTransform)
        for animation in [fade, move] {
            animation.duration = Self.fade
            animation.timingFunction = timing
            layer.add(animation, forKey: animation.keyPath)
        }
        CATransaction.commit()
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}
