import AppKit
import SwiftUI

struct ChatPicture: NSViewRepresentable {
    var image: NSImage
    var name: String
    var fileURL: URL?
    var cornerRadius: CGFloat
    var onOpen: (() -> Void)?

    func makeNSView(context: Context) -> ChatPictureView {
        let view = ChatPictureView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        view.animates = true
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: ChatPictureView, context: Context) {
        view.image = image
        view.pictureName = name
        view.fileURL = fileURL
        view.onOpen = onOpen
        view.layer?.cornerRadius = cornerRadius
        view.setAccessibilityLabel(name.isEmpty ? tr("图片无法显示") : name)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ChatPictureView, context: Context) -> CGSize? {
        let fallback = CGSize(width: 160, height: 160)
        let width = proposal.width ?? fallback.width
        let height = proposal.height ?? fallback.height
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return fallback }
        return CGSize(width: width, height: height)
    }
}

final class ChatPictureView: NSImageView {
    var pictureName = "image.png"
    var fileURL: URL?
    var onOpen: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard event.buttonNumber == 0 else { return }
        onOpen?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let image else { return nil }
        return ChatImageActions.menu(image: image, name: pictureName, fileURL: fileURL)
    }
}

struct ChatFileImage: View {
    var url: URL
    var name: String
    var longest: CGFloat?
    var maxWidth: CGFloat?
    var cornerRadius: CGFloat = 12
    var opens: Bool = true
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                let size = Self.displaySize(image.size, longest: longest, maxWidth: maxWidth)
                ChatPicture(image: image, name: name, fileURL: url, cornerRadius: cornerRadius, onOpen: opens ? {
                    AppImagePresenter.open(image, name: name, fileURL: url)
                } : nil)
                .frame(width: size.width, height: size.height)
                .clipped()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppColor.surfaceInset)
                    .frame(width: longest ?? maxWidth ?? 120, height: longest ?? 80)
                    .overlay {
                        if failed {
                            Text(tr("图片无法显示"))
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
            }
        }
        .task(id: url) {
            if let loaded = NSImage(contentsOf: url) {
                image = loaded
                failed = false
            } else {
                failed = true
            }
        }
    }

    static func displaySize(_ size: CGSize, longest: CGFloat?, maxWidth: CGFloat?) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 120, height: 120) }
        var scale: CGFloat = 1
        if let longest {
            scale = min(scale, longest / max(size.width, size.height))
        }
        if let maxWidth, size.width * scale > maxWidth {
            scale = maxWidth / size.width
        }
        return CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
    }
}

struct ChatThumb: View {
    static let side: CGFloat = 48

    var url: URL
    var name: String
    var onRemove: (() -> Void)?
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                guard let image else { return }
                AppImagePresenter.open(image, name: name, fileURL: url)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppColor.surfaceInset)
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: Self.side, height: Self.side)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .contextMenu {
                if let image {
                    Button(tr("拷贝图片")) { ChatImageActions.copy(image, fileURL: url) }
                    Button(tr("将图片存储为…")) { ChatImageActions.save(image, name: name, fileURL: url) }
                }
            }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Color.black.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain.clicking())
                .padding(3)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .accessibilityLabel(tr("移走图片"))
            }
        }
        .frame(width: Self.side, height: Self.side)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .task(id: url) {
            image = ChatImages.displayCopy(of: url) ?? NSImage(contentsOf: url)
        }
    }
}

struct ChatThumbRow: View {
    struct Item {
        var id: UUID
        var url: URL
        var name: String
        var isFile = false
    }

    var images: [Item]
    var trailing = false
    var onRemove: ((UUID) -> Void)?

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(images, id: \.id) { item in
                        let remove = onRemove.map { remove in { remove(item.id) } }
                        if item.isFile {
                            ChatFileChip(url: item.url, name: item.name, onRemove: remove)
                        } else {
                            ChatThumb(url: item.url, name: item.name, onRemove: remove)
                        }
                    }
                }
                .frame(minWidth: geo.size.width, alignment: trailing ? .trailing : .leading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .frame(height: ChatThumb.side)
    }
}

struct ChatImageStrip: View {
    var items: [ChatImageDraft]
    /// True above a sent question, so the images sit over its bubble on the right.
    var trailing = false
    var onRemove: ((ChatImageDraft) -> Void)?

    var body: some View {
        ChatThumbRow(
            images: items.map { .init(id: $0.id, url: $0.fileURL, name: $0.name, isFile: $0.isFile) },
            trailing: trailing,
            onRemove: onRemove.map { remove in
                { id in
                    guard let item = items.first(where: { $0.id == id }) else { return }
                    remove(item)
                }
            }
        )
    }
}

struct StoredImageStrip: View {
    var images: [ChatImage]
    var files: [ChatFileRef] = []

    var body: some View {
        ChatThumbRow(
            images: images.map { .init(id: $0.id, url: $0.fileURL(), name: $0.name) }
                + files.map { .init(id: $0.sourceID, url: SourceStore.fileURL(id: $0.sourceID, fileName: $0.name), name: $0.name, isFile: true) },
            trailing: true
        )
    }
}

/// A document attached to a question: its icon, name and size. Click opens it, right-click gives the
/// file menu, and it can be dragged out to Finder or another app.
struct ChatFileChip: View {
    var url: URL
    var name: String
    var onRemove: (() -> Void)?
    @State private var hovering = false

    private var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    var body: some View {
        let present = exists
        ZStack(alignment: .topTrailing) {
            Button {
                if present { AnswerLinkActions.openFile(url) }
            } label: {
                HStack(spacing: Space.s2) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: present ? url.path : "/System/Library/CoreServices/Finder.app"))
                        .resizable()
                        .frame(width: 30, height: 30)
                        .opacity(present ? 1 : 0.4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .font(AppFont.secondary.weight(.medium))
                            .foregroundStyle(present ? AppColor.textPrimary : AppColor.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(present ? Self.detail(url) : tr("文件已从资料中移除"))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, Space.s2)
                .frame(maxWidth: 240, minHeight: ChatThumb.side, maxHeight: ChatThumb.side, alignment: .leading)
                .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                // Darker the whole time the pointer is on the chip, so it reads as something to open.
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(hovering && present ? 0.22 : 0))
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain.clicking())
            .help(name)
            .contextMenu {
                if present { AnswerFileMenu(url: url) }
            }
            .onDrag { (present ? NSItemProvider(contentsOf: url) : nil) ?? NSItemProvider() }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Color.black.opacity(0.72), in: Circle())
                }
                .buttonStyle(.plain.clicking())
                .padding(3)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .accessibilityLabel(tr("移走文件"))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private static func detail(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let kind = url.pathExtension.uppercased()
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        return kind.isEmpty ? bytes : "\(kind) · \(bytes)"
    }
}

struct RemoteAnswerImage: View {
    var address: String
    var caption: String
    @State private var image: NSImage?
    @State private var fileURL: URL?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            if let image {
                let size = ChatFileImage.displaySize(image.size, longest: nil, maxWidth: 680)
                ChatPicture(image: image, name: caption.isEmpty ? "image.png" : caption, fileURL: fileURL, cornerRadius: 16) {
                    AppImagePresenter.open(image, name: fileName, fileURL: fileURL)
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColor.surfaceInset)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .overlay {
                        if failed {
                            Text(caption.isEmpty ? tr("图片无法显示") : caption)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
            }
            if image != nil, !caption.isEmpty {
                Text(caption)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
        .task(id: address) { await load() }
    }

    private var fileName: String {
        let leaf = URL(string: address)?.lastPathComponent ?? ""
        return leaf.isEmpty ? "image.png" : leaf
    }

    private func load() async {
        guard let remote = URL(string: address), remote.scheme?.lowercased() == "https" else {
            failed = true
            return
        }
        let cache = ChatImages.remoteCacheURL(remote)
        if let cached = NSImage(contentsOf: cache) {
            fileURL = cache
            image = cached
            return
        }
        do {
            var request = URLRequest(url: remote)
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let final = response.url ?? remote
            guard final.scheme?.lowercased() == "https",
                  let http, (200..<300).contains(http.statusCode),
                  data.count <= 20 * 1024 * 1024,
                  NSImage(data: data) != nil else {
                failed = true
                return
            }
            try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: cache, options: .atomic)
            fileURL = cache
            image = NSImage(data: data)
        } catch {
            failed = true
        }
    }
}

struct ChatImageLightbox: View {
    var image: NSImage
    var name: String
    var fileURL: URL?
    var reduceMotion: Bool
    var onClose: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .scaledToFit()
                .padding(48)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contextMenu {
                    Button(tr("拷贝图片")) { ChatImageActions.copy(image, fileURL: fileURL) }
                    Button(tr("将图片存储为…")) { ChatImageActions.save(image, name: name, fileURL: fileURL) }
                }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain.clicking())
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(tr("关闭"))
            .padding(16)
        }
        .scaleEffect(shown ? 1 : 0.86)
        .opacity(shown ? 1 : 0)
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else {
                shown = true
                return
            }
            withAnimation(.smooth(duration: 0.2)) { shown = true }
        }
    }

    private func close() {
        guard shown else { return }
        guard !reduceMotion else {
            onClose()
            return
        }
        withAnimation(.smooth(duration: 0.16), completionCriteria: .logicallyComplete) {
            shown = false
        } completion: {
            onClose()
        }
    }
}

enum AppImagePresenter {
    @MainActor static func open(_ image: NSImage, name: String, fileURL: URL?) {
        NotificationCenter.default.post(
            name: .nomiEnlargeImage,
            object: nil,
            userInfo: ["image": image, "name": name, "url": fileURL as Any]
        )
    }
}

extension Notification.Name {
    static let nomiEnlargeImage = Notification.Name("nomiEnlargeImage")
}
