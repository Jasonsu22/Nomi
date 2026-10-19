import AppKit
import Foundation
import PDFKit
import Vision

enum SourceText {
    static func blocks(url: URL, title: String, sourceID: UUID) -> [ContextBlock] {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "txt", "md":
            return chunk(readPlain(url), title: title, detail: "", sourceID: sourceID)
        case "pdf":
            return pdfBlocks(url: url, title: title, sourceID: sourceID)
        case "doc", "docx":
            return chunk(readDocument(url), title: title, detail: "", sourceID: sourceID)
        case "pptx":
            return slides(url: url, title: title, sourceID: sourceID)
        case "png", "jpg", "jpeg", "heic":
            return chunk(recognize(url: url), title: title, detail: "", sourceID: sourceID)
        default:
            return []
        }
    }

    private static func chunk(_ text: String, title: String, detail: String, sourceID: UUID) -> [ContextBlock] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [ContextBlock(title: title, detail: detail, body: String(trimmed.prefix(20_000)), sourceID: sourceID)]
    }

    private static func readPlain(_ url: URL) -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        if let text = try? String(contentsOf: url, encoding: .utf16) { return text }
        return ""
    }

    private static func readDocument(_ url: URL) -> String {
        let type: NSAttributedString.DocumentType = url.pathExtension.lowercased() == "doc" ? .docFormat : .officeOpenXML
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
                sourceID: sourceID
            ))
        }
        return blocks
    }

    private static func slides(url: URL, title: String, sourceID: UUID) -> [ContextBlock] {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("nomi-pptx-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", url.path, temp.path]
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let slides = temp.appendingPathComponent("ppt/slides", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: slides, includingPropertiesForKeys: nil) else { return [] }
        return urls
            .filter { $0.pathExtension == "xml" && $0.lastPathComponent.hasPrefix("slide") }
            .sorted { slideNumber($0) < slideNumber($1) }
            .enumerated()
            .compactMap { offset, file in
                guard let xml = try? String(contentsOf: file, encoding: .utf8) else { return nil }
                let text = plain(xml: xml).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return ContextBlock(
                    title: title,
                    detail: trf("第 %d 页", offset + 1),
                    body: String(text.prefix(4_000)),
                    sourceID: sourceID
                )
            }
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
