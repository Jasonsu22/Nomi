import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ChatImage: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var mime: String
    var relativePath: String

    func fileURL() -> URL {
        ChatImages.root.appendingPathComponent(relativePath)
    }
}

struct ChatImageDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var mime: String
    var fileURL: URL
}

struct ModelImage: Equatable, Sendable {
    var mime: String
    var base64: String
}

enum ChatImages {
    static let countLimit = 8
    static let byteLimit = 10 * 1024 * 1024
    private static let longestSide = 2048

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nomi/chat-images", isDirectory: true)
    }

    static var temporaryRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("nomi-chat-images", isDirectory: true)
    }

    static func seesImages(mode: LLMMode, modelID: String) -> Bool {
        guard mode == .api else { return false }
        return !modelID.lowercased().contains("minimax-m2")
    }

    static func intake(urls: [URL], existing: Int) -> (drafts: [ChatImageDraft], notice: String?) {
        var drafts: [ChatImageDraft] = []
        var notice: String?
        var count = existing
        func note(_ text: String) {
            if notice == nil { notice = text }
        }
        for url in urls {
            if count >= countLimit {
                note(tr("一次最多 8 张图片。"))
                break
            }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let mime = mimeType(for: url) else {
                note(tr("只能加入图片。"))
                continue
            }
            guard let data = try? Data(contentsOf: url) else {
                note(tr("这张图片无法读取。"))
                continue
            }
            guard let draft = store(data: data, name: url.lastPathComponent, mime: mime, note: note) else { continue }
            drafts.append(draft)
            count += 1
        }
        return (drafts, notice)
    }

    static func containsImage(_ pasteboard: NSPasteboard) -> Bool {
        let urls = fileURLs(pasteboard)
        if urls.contains(where: { mimeType(for: $0) != nil }) { return true }
        if hasBitmapType(pasteboard) { return true }
        let hasString = pasteboard.string(forType: .string)?.isEmpty == false
        if hasString || !urls.isEmpty { return false }
        return pasteboard.canReadObject(forClasses: [NSImage.self])
    }

    /// Nil when the pasteboard has no image, so the text field can paste normally.
    static func intake(pasteboard: NSPasteboard, existing: Int) -> (drafts: [ChatImageDraft], notice: String?)? {
        let urls = fileURLs(pasteboard)
        if !urls.isEmpty {
            var seen = Set<String>()
            let images = urls.filter { url in
                guard mimeType(for: url) != nil else { return false }
                return seen.insert(url.standardizedFileURL.path).inserted
            }
            if !images.isEmpty { return intake(urls: images, existing: existing) }
            if bitmapPayload(pasteboard) == nil { return ([], tr("只能加入图片。")) }
        }
        guard let payload = bitmapPayload(pasteboard) else { return nil }
        if existing >= countLimit { return ([], tr("一次最多 8 张图片。")) }
        var notice: String?
        guard let draft = store(data: payload.data, name: payload.name, mime: payload.mime, note: { notice = $0 }) else {
            return ([], notice ?? tr("这张图片无法读取。"))
        }
        return ([draft], notice)
    }

    private static func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ]) as? [URL], !urls.isEmpty {
            return urls
        }
        if let string = pasteboard.string(forType: .fileURL), let url = URL(string: string), url.isFileURL {
            return [url]
        }
        return []
    }

    private static let bitmapTypes: [NSPasteboard.PasteboardType] = [
        .png,
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        NSPasteboard.PasteboardType(UTType.gif.identifier),
        NSPasteboard.PasteboardType(UTType.webP.identifier),
        NSPasteboard.PasteboardType(UTType.heic.identifier),
        .tiff,
    ]

    private static func hasBitmapType(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        if bitmapTypes.contains(where: { types.contains($0) }) { return true }
        return types.contains { UTType($0.rawValue)?.conforms(to: .image) == true }
    }

    private static func bitmapPayload(_ pasteboard: NSPasteboard) -> (data: Data, mime: String, name: String)? {
        let typed: [(NSPasteboard.PasteboardType, String, String)] = [
            (.png, "image/png", "image.png"),
            (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "image/jpeg", "image.jpg"),
            (NSPasteboard.PasteboardType(UTType.gif.identifier), "image/gif", "image.gif"),
            (NSPasteboard.PasteboardType(UTType.webP.identifier), "image/webp", "image.webp"),
            (NSPasteboard.PasteboardType(UTType.heic.identifier), "image/heic", "image.heic"),
            (.tiff, "image/tiff", "image.png"),
        ]
        for (type, mime, name) in typed {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                return (data, mime, name)
            }
        }
        guard let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation, !tiff.isEmpty else { return nil }
        return (tiff, "image/tiff", "image.png")
    }

    /// A screen-sized bitmap so opening the photo does not decode the original on the first animation frame.
    static func displayCopy(of url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func discard(_ draft: ChatImageDraft) {
        try? FileManager.default.removeItem(at: draft.fileURL.deletingLastPathComponent())
    }

    static func removeTemporary() {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    static func promote(_ draft: ChatImageDraft) -> ChatImage? {
        let folder = root.appendingPathComponent(draft.id.uuidString, isDirectory: true)
        let filename = fileName(draft.name, mime: draft.mime)
        let destination = folder.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: draft.fileURL, to: destination)
            try? FileManager.default.removeItem(at: draft.fileURL.deletingLastPathComponent())
            return ChatImage(id: draft.id, name: draft.name, mime: draft.mime, relativePath: "\(draft.id.uuidString)/\(filename)")
        } catch {
            return nil
        }
    }

    static func delete(_ images: [ChatImage]) {
        for image in images {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(image.id.uuidString, isDirectory: true))
        }
    }

    static func payload(url: URL, mime: String) -> ModelImage? {
        guard let data = try? Data(contentsOf: url), let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let long = max(image.width, image.height)
        if long <= longestSide, ["image/jpeg", "image/png", "image/gif", "image/webp"].contains(mime) {
            return ModelImage(mime: mime, base64: data.base64EncodedString())
        }
        let scale = long > longestSide ? Double(longestSide) / Double(long) : 1
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        let output = mime == "image/jpeg" ? jpegData(scaled) : pngData(scaled)
        let outputMime = mime == "image/jpeg" ? "image/jpeg" : "image/png"
        guard let output else { return nil }
        return ModelImage(mime: outputMime, base64: output.base64EncodedString())
    }

    static func remoteCacheURL(_ remote: URL) -> URL {
        let digest = SHA256.hash(data: Data(remote.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("remote", isDirectory: true).appendingPathComponent(digest)
    }

    private static func store(data: Data, name: String, mime: String, note: (String) -> Void) -> ChatImageDraft? {
        guard data.count <= byteLimit else {
            note(tr("单张图片不能超过 10 MB。"))
            return nil
        }
        guard CGImageSourceCreateWithData(data as CFData, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) != nil else {
            note(tr("这张图片无法读取。"))
            return nil
        }
        let storedMime: String
        let storedData: Data
        if mime == "image/heic" || mime == "image/heif" || mime == "image/tiff" {
            guard let image = CGImageSourceCreateWithData(data as CFData, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }),
                  let png = pngData(image) else {
                note(tr("这张图片无法读取。"))
                return nil
            }
            storedMime = "image/png"
            storedData = png
        } else {
            storedMime = mime
            storedData = data
        }
        let id = UUID()
        let folder = temporaryRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let filename = fileName(name, mime: storedMime)
        let url = folder.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try storedData.write(to: url, options: .atomic)
        } catch {
            note(tr("这张图片无法读取。"))
            return nil
        }
        return ChatImageDraft(id: id, name: filename, mime: storedMime, fileURL: url)
    }

    static func mimeType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "heic", "heif": "image/heic"
        case "tif", "tiff": "image/tiff"
        default: nil
        }
    }

    private static func fileName(_ original: String, mime: String) -> String {
        let leaf = URL(fileURLWithPath: original).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: ".-_ "))
        let cleaned = String(leaf.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        let stem = (cleaned as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = stem.isEmpty ? "image" : stem
        let ext: String
        switch mime {
        case "image/jpeg": ext = "jpg"
        case "image/png": ext = "png"
        case "image/gif": ext = "gif"
        case "image/webp": ext = "webp"
        default: ext = "png"
        }
        return base + "." + ext
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func jpegData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

extension ChatContext {
    static func attachedImages(history: [ChatTurn], currentCount: Int, limit: Int = ChatImages.countLimit) -> (history: [ChatImage], omittedTurnIDs: Set<UUID>, mentionsOlderImages: Bool) {
        var room = max(0, limit - min(currentCount, limit))
        var chosen: [ChatImage] = []
        var omitted = Set<UUID>()
        for turn in history.suffix(4).reversed() {
            guard !turn.images.isEmpty else { continue }
            let before = chosen.count
            for image in turn.images where room > 0 {
                chosen.append(image)
                room -= 1
            }
            if chosen.count == before { omitted.insert(turn.id) }
        }
        let older = history.dropLast(min(4, history.count)).contains { !$0.images.isEmpty }
        return (chosen, omitted, older)
    }
}

@MainActor
enum ChatImageActions {
    static func copy(_ image: NSImage, fileURL: URL?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            pasteboard.setData(data, forType: pasteboardType(fileURL))
        }
        pasteboard.writeObjects([image])
    }

    static func save(_ image: NSImage, name: String, fileURL: URL?) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = name.isEmpty ? "image.png" : name
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                if let fileURL, let data = try? Data(contentsOf: fileURL) {
                    try data.write(to: destination, options: .atomic)
                } else if let tiff = image.tiffRepresentation {
                    try tiff.write(to: destination, options: .atomic)
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = tr("无法保存文件")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    static func menu(image: NSImage, name: String, fileURL: URL?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let owner = ImageMenuOwner(image: image, name: name, fileURL: fileURL)
        objc_setAssociatedObject(menu, &ImageMenuKey.key, owner, .OBJC_ASSOCIATION_RETAIN)
        let copy = NSMenuItem(title: tr("拷贝图片"), action: #selector(ImageMenuOwner.copyImage(_:)), keyEquivalent: "")
        copy.target = owner
        copy.isEnabled = true
        let save = NSMenuItem(title: tr("将图片存储为…"), action: #selector(ImageMenuOwner.saveImage(_:)), keyEquivalent: "")
        save.target = owner
        save.isEnabled = true
        menu.addItem(copy)
        menu.addItem(save)
        return menu
    }

    private static func pasteboardType(_ url: URL) -> NSPasteboard.PasteboardType {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": NSPasteboard.PasteboardType("public.jpeg")
        case "gif": NSPasteboard.PasteboardType("com.compuserve.gif")
        case "webp": NSPasteboard.PasteboardType("org.webmproject.webp")
        case "tif", "tiff": .tiff
        default: .png
        }
    }
}

private enum ImageMenuKey {
    nonisolated(unsafe) static var key: UInt8 = 0
}

@MainActor
private final class ImageMenuOwner: NSObject {
    let image: NSImage
    let name: String
    let fileURL: URL?

    init(image: NSImage, name: String, fileURL: URL?) {
        self.image = image
        self.name = name
        self.fileURL = fileURL
    }

    @objc func copyImage(_ sender: Any?) { ChatImageActions.copy(image, fileURL: fileURL) }
    @objc func saveImage(_ sender: Any?) { ChatImageActions.save(image, name: name, fileURL: fileURL) }
}
