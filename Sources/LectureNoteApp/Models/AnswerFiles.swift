import AppKit
import CryptoKit
import Foundation
import SwiftUI

/// A generated demonstration saved on disk, so it can be opened, saved, and revealed like a file.
enum ChatFiles {
    struct Export: Equatable, Sendable {
        var named: [String: URL] = [:]
        var widgets: [URL] = []
    }

    static func export(_ source: String, directory: URL = defaultDirectory) -> Export {
        export(pieces: AnswerDocument.pieces(in: source), directory: directory)
    }

    static func export(pieces: [AnswerDocument.Piece], directory: URL = defaultDirectory) -> Export {
        var html: [(title: String, fragment: String)] = []
        for piece in pieces {
            if case .widget(let title, let fragment) = piece {
                html.append((title, fragment))
            }
        }
        guard !html.isEmpty else { return Export() }
        let names = inlineHTMLNames(in: pieces)
        var export = Export()
        for (index, widget) in html.enumerated() {
            let name = index < names.count ? names[index] : fallbackName(title: widget.title, index: index)
            let document = standalonePage(fragment: widget.fragment, title: widget.title)
            guard let url = store(name: name, contents: document, directory: directory) else { continue }
            export.widgets.append(url)
            if index < names.count {
                export.named[names[index]] = url
            }
        }
        return export
    }

    static func symbol(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff":
            return "photo"
        case "pdf":
            return "doc.richtext"
        case "html", "htm":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc"
        }
    }

    private static var defaultDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nomi/chat-files", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func store(name: String, contents: String, directory: URL) -> URL? {
        let safe = sanitized(name)
        let digest = SHA256.hash(data: Data(contents.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let folder = directory.appendingPathComponent(digest, isDirectory: true)
        let url = folder.appendingPathComponent(safe)
        if let cached = StoredFiles.shared.url(for: url.path) { return cached }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            StoredFiles.shared.remember(url)
            return url
        } catch {
            return nil
        }
    }

    private static func inlineHTMLNames(in pieces: [AnswerDocument.Piece]) -> [String] {
        var names: [String] = []
        for piece in pieces {
            let text: String
            switch piece {
            case .paragraph(let value), .heading(_, let value):
                text = value
            case .list(_, let items):
                text = items.joined(separator: "\n")
            default:
                continue
            }
            var index = text.startIndex
            while index < text.endIndex {
                guard text[index] == "`" else {
                    index = text.index(after: index)
                    continue
                }
                let content = text.index(after: index)
                guard let end = text[content...].firstIndex(of: "`") else { break }
                let code = text[content..<end].trimmingCharacters(in: .whitespacesAndNewlines)
                if isHTMLName(code), !names.contains(code) {
                    names.append(code)
                }
                index = text.index(after: end)
            }
        }
        return names
    }

    private static func isHTMLName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 80, !name.contains("/"), !name.contains("\\") else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        guard ext == "html" || ext == "htm" else { return false }
        return !(name as NSString).deletingPathExtension.isEmpty
    }

    private static func fallbackName(title: String, index: Int) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return index == 0 ? "figure.html" : "figure-\(index + 1).html" }
        return trimmed + ".html"
    }

    private static func sanitized(_ name: String) -> String {
        let base = (name as NSString).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = base.unicodeScalars.filter { scalar in
            scalar == "-" || scalar == "_" || scalar == "." || CharacterSet.alphanumerics.contains(scalar)
        }
        var text = String(String.UnicodeScalarView(cleaned))
        while text.hasPrefix(".") { text.removeFirst() }
        if text.isEmpty || (text as NSString).pathExtension.isEmpty { return "figure.html" }
        return text
    }

    private static func standalonePage(fragment: String, title: String) -> String {
        let safeTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(safeTitle)</title>
        </head>
        <body>
        \(fragment)
        </body>
        </html>
        """
    }
}

struct AnswerApp: Hashable, Identifiable {
    var name: String
    var url: URL
    var id: URL { url }
}

@MainActor
enum AnswerLinkActions {
    static func applications(for url: URL) -> [AnswerApp] {
        NSWorkspace.shared.urlsForApplications(toOpen: url).prefix(15).map { app in
            AnswerApp(name: FileManager.default.displayName(atPath: app.path), url: app)
        }
    }

    static func defaultApplication(for url: URL) -> AnswerApp? {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        return AnswerApp(name: FileManager.default.displayName(atPath: app.path), url: app)
    }

    static func openFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func open(_ url: URL, with application: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    static func copyContents(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func copyLink(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    static func saveFile(_ url: URL) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = url.lastPathComponent
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)
            } catch {
                alert(tr("无法保存文件"), error.localizedDescription)
            }
        }
    }

    static func saveLink(_ url: URL) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let suggested = url.lastPathComponent
        panel.nameFieldStringValue = suggested.isEmpty || suggested == "/" ? "page.html" : suggested
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            Task {
                do {
                    let (downloaded, _) = try await URLSession.shared.download(from: url)
                    let data = try Data(contentsOf: downloaded)
                    try data.write(to: destination, options: .atomic)
                } catch {
                    await MainActor.run { alert(tr("无法保存链接"), error.localizedDescription) }
                }
            }
        }
    }

    static func openLink(_ url: URL, newWindow: Bool) {
        guard newWindow, let application = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            NSWorkspace.shared.open(url)
            return
        }
        if runNewWindow(url, application: application) { return }
        open(url, with: application)
    }

    private static func runNewWindow(_ url: URL, application: URL) -> Bool {
        let bundle = Bundle(url: application)?.bundleIdentifier ?? ""
        let literal = url.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "")
        guard literal.hasPrefix("http://") || literal.hasPrefix("https://") else { return false }
        let script: String
        switch bundle {
        case "com.apple.Safari":
            script = "tell application \"Safari\" to make new document with properties {URL:\"\(literal)\"}\ntell application \"Safari\" to activate"
        case "com.google.Chrome", "com.google.Chrome.canary":
            script = "tell application \"Google Chrome\"\nmake new window\nset URL of active tab of window 1 to \"\(literal)\"\nactivate\nend tell"
        case "com.microsoft.edgemac":
            script = "tell application \"Microsoft Edge\"\nmake new window\nset URL of active tab of window 1 to \"\(literal)\"\nactivate\nend tell"
        default:
            return false
        }
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil
    }

    private static func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

struct AnswerFileMenu: View {
    var url: URL

    var body: some View {
        Button(tr("打开文件")) { AnswerLinkActions.openFile(url) }
        if let app = AnswerLinkActions.defaultApplication(for: url) {
            Button(trf("在 %@ 中打开", app.name)) { AnswerLinkActions.open(url, with: app.url) }
        }
        let apps = AnswerLinkActions.applications(for: url)
        if !apps.isEmpty {
            Menu(tr("打开方式")) {
                ForEach(apps) { app in
                    Button(app.name) { AnswerLinkActions.open(url, with: app.url) }
                }
            }
        }
        Divider()
        Button(tr("存储为…")) { AnswerLinkActions.saveFile(url) }
        Button(tr("拷贝路径")) { AnswerLinkActions.copyPath(url) }
        Button(tr("拷贝文件内容")) { AnswerLinkActions.copyContents(url) }
        Button(tr("在访达中显示")) { AnswerLinkActions.reveal(url) }
    }
}

@MainActor
enum AnswerMenus {
    static func file(_ url: URL) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let owner = MenuOwner(url: url)
        retain(owner, on: menu)
        add(menu, title: tr("打开文件"), action: #selector(MenuOwner.openFile(_:)), owner: owner)
        if let app = AnswerLinkActions.defaultApplication(for: url) {
            add(menu, title: trf("在 %@ 中打开", app.name), action: #selector(MenuOwner.openInDefault(_:)), owner: owner, image: icon(app.url))
        }
        let apps = AnswerLinkActions.applications(for: url)
        if !apps.isEmpty {
            let submenu = NSMenu()
            for app in apps {
                let item = NSMenuItem(title: app.name, action: #selector(MenuOwner.openInApp(_:)), keyEquivalent: "")
                item.target = owner
                item.isEnabled = true
                item.representedObject = app.url
                item.image = icon(app.url)
                submenu.addItem(item)
            }
            let item = NSMenuItem(title: tr("打开方式"), action: nil, keyEquivalent: "")
            item.submenu = submenu
            menu.addItem(item)
        }
        menu.addItem(.separator())
        add(menu, title: tr("存储为…"), action: #selector(MenuOwner.saveFile(_:)), owner: owner)
        add(menu, title: tr("拷贝路径"), action: #selector(MenuOwner.copyPath(_:)), owner: owner)
        add(menu, title: tr("拷贝文件内容"), action: #selector(MenuOwner.copyContents(_:)), owner: owner)
        add(menu, title: tr("在访达中显示"), action: #selector(MenuOwner.reveal(_:)), owner: owner)
        return menu
    }

    static func link(_ url: URL) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let owner = MenuOwner(url: url)
        retain(owner, on: menu)
        let submenu = NSMenu()
        let tab = NSMenuItem(title: tr("新标签页"), action: #selector(MenuOwner.openTab(_:)), keyEquivalent: "")
        tab.target = owner
        tab.isEnabled = true
        let window = NSMenuItem(title: tr("新窗口"), action: #selector(MenuOwner.openWindow(_:)), keyEquivalent: "")
        window.target = owner
        window.isEnabled = true
        let browser = NSMenuItem(title: tr("默认浏览器"), action: #selector(MenuOwner.openTab(_:)), keyEquivalent: "")
        browser.target = owner
        browser.isEnabled = true
        submenu.addItem(tab)
        submenu.addItem(window)
        submenu.addItem(browser)
        let open = NSMenuItem(title: tr("打开于"), action: nil, keyEquivalent: "")
        open.submenu = submenu
        menu.addItem(open)
        menu.addItem(.separator())
        add(menu, title: tr("拷贝链接"), action: #selector(MenuOwner.copyLink(_:)), owner: owner)
        add(menu, title: tr("将链接存储为…"), action: #selector(MenuOwner.saveLink(_:)), owner: owner)
        return menu
    }

    private static func add(_ menu: NSMenu, title: String, action: Selector, owner: MenuOwner, image: NSImage? = nil) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = owner
        item.isEnabled = true
        item.image = image
        menu.addItem(item)
    }

    private static func icon(_ url: URL) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    private static func retain(_ owner: MenuOwner, on menu: NSMenu) {
        objc_setAssociatedObject(menu, &OwnerAssociation.key, owner, .OBJC_ASSOCIATION_RETAIN)
    }
}

private enum OwnerAssociation {
    nonisolated(unsafe) static var key: UInt8 = 0
}

private final class StoredFiles: @unchecked Sendable {
    static let shared = StoredFiles()
    private let lock = NSLock()
    private var urls: [String: URL] = [:]

    func url(for key: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard let url = urls[key], FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func remember(_ url: URL) {
        lock.lock()
        urls[url.path] = url
        lock.unlock()
    }
}

@MainActor
private final class MenuOwner: NSObject {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    @objc func openFile(_ sender: Any?) { AnswerLinkActions.openFile(url) }
    @objc func openInDefault(_ sender: Any?) {
        guard let app = AnswerLinkActions.defaultApplication(for: url) else { return }
        AnswerLinkActions.open(url, with: app.url)
    }
    @objc func openInApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        AnswerLinkActions.open(url, with: app)
    }
    @objc func reveal(_ sender: Any?) { AnswerLinkActions.reveal(url) }
    @objc func copyPath(_ sender: Any?) { AnswerLinkActions.copyPath(url) }
    @objc func copyContents(_ sender: Any?) { AnswerLinkActions.copyContents(url) }
    @objc func copyLink(_ sender: Any?) { AnswerLinkActions.copyLink(url) }
    @objc func saveFile(_ sender: Any?) { AnswerLinkActions.saveFile(url) }
    @objc func saveLink(_ sender: Any?) { AnswerLinkActions.saveLink(url) }
    @objc func openTab(_ sender: Any?) { AnswerLinkActions.openLink(url, newWindow: false) }
    @objc func openWindow(_ sender: Any?) { AnswerLinkActions.openLink(url, newWindow: true) }
}
