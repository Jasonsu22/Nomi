import AppKit
import Foundation
import PDFKit
import Vision

enum SourceText {
    /// Read as text, with the encoding guessed.
    static let plainExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "csv", "tsv", "json", "xml", "yaml", "yml", "tex", "bib", "srt", "vtt", "log",
        "py", "swift", "js", "mjs", "ts", "tsx", "jsx", "java", "kt", "c", "cc", "cpp", "h", "hpp", "m", "mm", "cs",
        "go", "rs", "rb", "php", "sh", "zsh", "sql", "r", "scala", "lua", "css", "scss", "ipynb",
    ]
    /// Read through the system's document reader (the one TextEdit uses).
    static let documentExtensions: Set<String> = ["doc", "docx", "rtf", "rtfd", "odt"]
    static let pageExtensions: Set<String> = ["html", "htm", "xhtml", "webarchive"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "webp", "tif", "tiff"]
    /// Formats macOS has no reader for. They are turned away with a note to export them first.
    static let unreadableExtensions: Set<String> = ["key", "pages", "numbers", "ppt", "xls"]

    /// Every type Nomi can read, for the Sources page and the chat box alike.
    static var readableExtensions: Set<String> {
        plainExtensions.union(documentExtensions).union(pageExtensions).union(imageExtensions)
            .union(["pdf", "pptx", "xlsx", "epub"])
    }

    static func canRead(_ url: URL) -> Bool {
        readableExtensions.contains(url.pathExtension.lowercased())
    }

    /// Why a file was turned away, for the Sources page and the chat box.
    static func refusal(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if unreadableExtensions.contains(ext) {
            return trf("Nomi 读不了 .%@ 文件，请先导出成 PDF 或新版 Office 格式。", ext)
        }
        return tr("Nomi 还读不了这种文件。")
    }

    static func blocks(url: URL, title: String, sourceID: UUID) -> [ContextBlock] {
        let ext = url.pathExtension.lowercased()
        if plainExtensions.contains(ext) {
            return chunk(readPlain(url), title: title, sourceID: sourceID)
        }
        if ext == "docx" {
            return wordDocument(url: url, title: title, sourceID: sourceID)
        }
        if documentExtensions.contains(ext) {
            return chunk(readDocument(url), title: title, sourceID: sourceID)
        }
        if pageExtensions.contains(ext) {
            return chunk(readPage(url), title: title, sourceID: sourceID)
        }
        if imageExtensions.contains(ext) {
            return chunk(recognize(url: url), title: title, sourceID: sourceID)
        }
        switch ext {
        case "pdf":
            return pdfBlocks(url: url, title: title, sourceID: sourceID)
        case "pptx":
            return slides(url: url, title: title, sourceID: sourceID)
        case "xlsx":
            return sheets(url: url, title: title, sourceID: sourceID)
        case "epub":
            return book(url: url, title: title, sourceID: sourceID)
        default:
            return []
        }
    }

    /// Long text becomes several passages, so a question can use the parts that match it.
    static let passageLength = 4_000
    static let passageLimit = 300

    private static func chunk(_ text: String, title: String, detail: String = "", sourceID: UUID) -> [ContextBlock] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let parts = passages(trimmed)
        if parts.count == 1 {
            return [ContextBlock(title: title, detail: detail, body: parts[0], sourceID: sourceID)]
        }
        return parts.enumerated().map { index, body in
            let part = trf("第 %d 部分", index + 1)
            return ContextBlock(title: title, detail: detail.isEmpty ? part : "\(detail) · \(part)", body: body, sourceID: sourceID)
        }
    }

    /// Splits at paragraph breaks where possible, each piece at most `passageLength` characters.
    static func passages(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n") {
            if current.count + paragraph.count + 1 > passageLength, !current.isEmpty {
                result.append(current)
                current = ""
                if result.count >= passageLimit { return result }
            }
            if paragraph.count > passageLength {
                var rest = Substring(paragraph)
                while rest.count > passageLength {
                    result.append(String(rest.prefix(passageLength)))
                    rest = rest.dropFirst(passageLength)
                    if result.count >= passageLimit { return result }
                }
                current = String(rest)
            } else {
                current += current.isEmpty ? paragraph : "\n" + paragraph
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty, result.count < passageLimit { result.append(tail) }
        return result
    }

    /// UTF-8 and UTF-16 first, then GB18030 for older Chinese files, then Latin-1, which reads anything.
    static func readPlain(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        if let text = String(data: data, encoding: .utf8) { return text }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) { return text }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let text = String(data: data, encoding: gb18030) { return text }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Web pages are reduced to their text here rather than through the system HTML reader, which needs
    /// the main thread. Scripts and styles are dropped; block tags become line breaks.
    static func readPage(_ url: URL) -> String {
        let html: String
        if url.pathExtension.lowercased() == "webarchive" {
            guard let data = try? Data(contentsOf: url),
                  let archive = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let main = archive["WebMainResource"] as? [String: Any],
                  let body = main["WebResourceData"] as? Data else { return "" }
            html = String(data: body, encoding: .utf8) ?? String(data: body, encoding: .isoLatin1) ?? ""
        } else {
            html = readPlain(url)
        }
        return text(html: html)
    }

    static func text(html: String) -> String {
        var source = html
        for tag in ["script", "style", "head", "noscript", "svg"] {
            source = source.replacingOccurrences(of: "<\(tag)\\b[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        source = source.replacingOccurrences(of: "<(br|/p|/div|/li|/h[1-6]|/tr|/section|/article)\\b[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        source = source.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (entity, value) in entities { source = source.replacingOccurrences(of: entity, with: value) }
        return source.components(separatedBy: "\n")
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func readDocument(_ url: URL) -> String {
        let type: NSAttributedString.DocumentType
        switch url.pathExtension.lowercased() {
        case "doc": type = .docFormat
        case "rtf": type = .rtf
        case "rtfd": type = .rtfd
        case "odt": type = .openDocument
        default: type = .officeOpenXML
        }
        guard let text = try? NSAttributedString(
            url: url,
            options: [.documentType: type],
            documentAttributes: nil
        ) else { return "" }
        return text.string
    }

    private static func pdfBlocks(url: URL, title: String, sourceID: UUID) -> [ContextBlock] {
        guard let document = PDFDocument(url: url) else { return [] }
        var blocks: [ContextBlock] = []
        var scanned = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            var text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.count < 8, scanned < 8 {
                scanned += 1
                text = recognize(page: page)
            }
            guard !text.isEmpty else { continue }
            blocks.append(ContextBlock(
                title: title,
                detail: trf("第 %d 页", index + 1),
                body: String(text.prefix(4_000)),
                sourceID: sourceID,
                page: index + 1
            ))
        }
        return blocks
    }

    /// Office files and e-books are zip archives of XML; this unpacks one into a temporary folder.
    private static func unzipped(_ url: URL, _ body: (URL) -> [ContextBlock]) -> [ContextBlock] {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("nomi-unzip-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", url.path, temp.path]
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return body(temp)
    }

    private static func numbered(_ folder: URL, prefix: String) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "xml" && $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { slideNumber($0) < slideNumber($1) }
    }

    /// Most pictures in a document or slide are screenshots of text; at most this many are read per file.
    static let pictureLimit = 40

    /// The document's text, then the text in its pictures, in the order they appear.
    private static func wordDocument(url: URL, title: String, sourceID: UUID) -> [ContextBlock] {
        var blocks = chunk(readDocument(url), title: title, sourceID: sourceID)
        blocks += unzipped(url) { root in
            let pictures = pictures(in: root.appendingPathComponent("word/document.xml"), relations: root.appendingPathComponent("word/_rels/document.xml.rels"))
            return pictures.prefix(pictureLimit).enumerated().flatMap { index, picture in
                chunk(recognize(url: picture), title: title, detail: trf("第 %d 张图片", index + 1), sourceID: sourceID)
            }
        }
        return blocks
    }

    /// The image files an Office XML part shows, in order, found through its relationship file.
    private static func pictures(in part: URL, relations: URL) -> [URL] {
        guard let xml = try? String(contentsOf: part, encoding: .utf8),
              let rels = try? String(contentsOf: relations, encoding: .utf8) else { return [] }
        var targets: [String: String] = [:]
        for relation in matches(rels, #"<Relationship\b([^>]*)/?>"#) {
            if let id = matches(relation, #"\bId="([^"]+)""#).first, let target = matches(relation, #"\bTarget="([^"]+)""#).first {
                targets[id] = target
            }
        }
        var seen = Set<String>()
        return matches(xml, #"r:embed="([^"]+)""#).compactMap { id in
            guard let target = targets[id], seen.insert(target).inserted else { return nil }
            let url = relations.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(target).standardizedFileURL
            return imageExtensions.contains(url.pathExtension.lowercased()) ? url : nil
        }
    }

    /// One passage per slide, with the speaker notes after the slide's own text.
    private static func slides(url: URL, title: String, sourceID: UUID) -> [ContextBlock] {
        unzipped(url) { root in
            let notes = numbered(root.appendingPathComponent("ppt/notesSlides"), prefix: "notesSlide")
            let notesByNumber = Dictionary(notes.map { (slideNumber($0), $0) }, uniquingKeysWith: { first, _ in first })
            return numbered(root.appendingPathComponent("ppt/slides"), prefix: "slide")
                .enumerated()
                .compactMap { offset, file in
                    guard let xml = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                    var text = plain(xml: xml).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let noteFile = notesByNumber[slideNumber(file)], let noteXML = try? String(contentsOf: noteFile, encoding: .utf8) {
                        let note = plain(xml: noteXML).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !note.isEmpty { text += "\n" + note }
                    }
                    // A slide that is mostly a picture (a screenshot, a scanned page) is read from the picture.
                    if text.count < 200, offset < pictureLimit {
                        let relations = file.deletingLastPathComponent().appendingPathComponent("_rels/\(file.lastPathComponent).rels")
                        let read = pictures(in: file, relations: relations).prefix(3).map(recognize(url:)).joined(separator: "\n")
                        if !read.isEmpty { text += (text.isEmpty ? "" : "\n") + read }
                    }
                    guard !text.isEmpty else { return nil }
                    return ContextBlock(title: title, detail: trf("第 %d 页", offset + 1), body: String(text.prefix(passageLength)), sourceID: sourceID)
                }
        }
    }

    /// One or more passages per sheet, each row as its cells joined by " | ".
    private static func sheets(url: URL, title: String, sourceID: UUID) -> [ContextBlock] {
        unzipped(url) { root in
            let shared = (try? String(contentsOf: root.appendingPathComponent("xl/sharedStrings.xml"), encoding: .utf8))
                .map { xml in matches(xml, #"<si\b[^>]*>([\s\S]*?)</si>"#).map { plain(xml: $0) } } ?? []
            let workbook = (try? String(contentsOf: root.appendingPathComponent("xl/workbook.xml"), encoding: .utf8)) ?? ""
            let names = matches(workbook, #"<sheet\b[^>]*\bname="([^"]*)""#)
            return numbered(root.appendingPathComponent("xl/worksheets"), prefix: "sheet").enumerated().flatMap { offset, file -> [ContextBlock] in
                guard let xml = try? String(contentsOf: file, encoding: .utf8) else { return [] }
                let rows = matches(xml, #"<row\b[^>]*>([\s\S]*?)</row>"#).map { row in
                    matches(row, #"<c\b([^>]*?)(?:/>|>([\s\S]*?)</c>)"#, groups: 2).compactMap { cell -> String? in
                        let attributes = cell[0], inner = cell[1]
                        if attributes.contains("t=\"s\""), let value = matches(inner, #"<v>([^<]*)</v>"#).first, let index = Int(value), index < shared.count {
                            return shared[index]
                        }
                        if attributes.contains("t=\"inlineStr\"") { return plain(xml: inner) }
                        return matches(inner, #"<v>([^<]*)</v>"#).first
                    }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " | ")
                }
                .filter { !$0.isEmpty }
                let name = offset < names.count ? decode(names[offset]) : trf("工作表 %d", offset + 1)
                return chunk(rows.joined(separator: "\n"), title: title, detail: name, sourceID: sourceID)
            }
        }
    }

    /// The chapters in reading order, as the book's own table of contents (its spine) lists them.
    private static func book(url: URL, title: String, sourceID: UUID) -> [ContextBlock] {
        unzipped(url) { root in
            guard let container = try? String(contentsOf: root.appendingPathComponent("META-INF/container.xml"), encoding: .utf8),
                  let opfPath = matches(container, #"full-path="([^"]+)""#).first,
                  let opf = try? String(contentsOf: root.appendingPathComponent(opfPath), encoding: .utf8) else { return [] }
            let base = root.appendingPathComponent(opfPath).deletingLastPathComponent()
            var manifest: [String: String] = [:]
            for item in matches(opf, #"<item\b([^>]*)/?>"#) {
                if let id = matches(item, #"\bid="([^"]+)""#).first, let href = matches(item, #"\bhref="([^"]+)""#).first {
                    manifest[id] = href.removingPercentEncoding ?? href
                }
            }
            let chapters = matches(opf, #"<itemref\b[^>]*\bidref="([^"]+)""#).compactMap { manifest[$0] }
            var blocks: [ContextBlock] = []
            for (index, href) in chapters.enumerated() where blocks.count < passageLimit {
                guard let html = try? String(contentsOf: base.appendingPathComponent(href), encoding: .utf8) else { continue }
                blocks += chunk(text(html: html), title: title, detail: trf("第 %d 章", index + 1), sourceID: sourceID)
            }
            return Array(blocks.prefix(passageLimit))
        }
    }

    private static func matches(_ text: String, _ pattern: String) -> [String] {
        matches(text, pattern, groups: 1).map { $0[0] }
    }

    /// Each match's capture groups, an empty string for a group that did not take part.
    private static func matches(_ text: String, _ pattern: String, groups: Int) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (1...groups).map { group in
                guard group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return "" }
                return String(text[range])
            }
        }
    }

    private static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
    }

    private static func slideNumber(_ url: URL) -> Int {
        Int(url.deletingPathExtension().lastPathComponent.filter(\.isNumber)) ?? 0
    }

    private static func plain(xml: String) -> String {
        var result = ""
        var inTag = false
        for character in xml {
            if character == "<" { inTag = true; continue }
            if character == ">" {
                inTag = false
                result.append(" ")
                continue
            }
            if !inTag { result.append(character) }
        }
        let decoded = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return decoded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func recognize(url: URL) -> String {
        let request = textRequest()
        let handler = VNImageRequestHandler(url: url, options: [:])
        try? handler.perform([request])
        return join(request)
    }

    private static func recognize(page: PDFPage) -> String {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 32, height > 32, width < 4000, height < 4000 else { return "" }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return "" }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { return "" }
        let request = textRequest()
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return join(request)
    }

    private static func textRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        return request
    }

    private static func join(_ request: VNRecognizeTextRequest) -> String {
        (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
