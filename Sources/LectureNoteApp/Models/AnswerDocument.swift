import Foundation
import SwiftUI

enum AnswerDocument {
    static let widgetLimit = 2
    static let widgetByteLimit = 24 * 1024

    enum Piece: Equatable {
        case heading(Int, String)
        case paragraph(String)
        case list(ordered: Bool, items: [String])
        case code(String)
        case table(header: [String], rows: [[String]])
        case widget(title: String, html: String)
    }

    enum StreamPiece: Equatable {
        case text(String)
        case preparing
    }

    static func pieces(in source: String) -> [Piece] {
        var result: [Piece] = []
        var widgets = 0
        for region in regions(in: source) {
            switch region.kind {
            case .text:
                result.append(contentsOf: markdown(region.body))
            case .fence:
                let body = region.body
                guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                if let title = htmlTitle(region.info),
                   region.closed,
                   body.utf8.count <= widgetByteLimit,
                   widgets < widgetLimit,
                   allowsWidget(body) {
                    widgets += 1
                    result.append(.widget(title: title, html: body))
                } else {
                    result.append(.code(body))
                }
            }
        }
        return result
    }

    static func streamingPieces(in source: String) -> [StreamPiece] {
        var pieces: [StreamPiece] = []
        var text: [String] = []
        func flush() {
            guard !text.isEmpty else { return }
            pieces.append(.text(text.joined(separator: "\n")))
            text.removeAll()
        }
        for region in regions(in: source) {
            switch region.kind {
            case .text:
                text.append(region.body)
            case .fence:
                if htmlTitle(region.info) != nil {
                    flush()
                    pieces.append(.preparing)
                } else {
                    var block = "```" + region.info
                    if !region.body.isEmpty { block += "\n" + region.body }
                    if region.closed { block += "\n```" }
                    text.append(block)
                }
            }
        }
        flush()
        return pieces
    }

    static func allowsWidget(_ html: String) -> Bool {
        let folded = html.lowercased()
        let banned = [
            "</body", "</html", "</head", "<!doctype", "<html", "<head", "<body",
            "<iframe", "<object", "<embed", "<link", "<base", "<meta", "<form",
            "<img", "<image", "<video", "<audio", "<source", "<track",
            "<frame", "<frameset", "<applet", "<foreignobject",
            "javascript:", "@import", "formaction",
        ]
        if banned.contains(where: { folded.contains($0) }) { return false }
        if scriptHasSource(folded) { return false }
        if hasExternalAddress(folded) { return false }
        if hasBlockedInput(folded) { return false }
        return true
    }

    static func page(fragment: String, text: String, surface: String, accent: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'none'; connect-src 'none'; frame-src 'none'; font-src 'none'; media-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
        <style>
        :root { color-scheme: light dark; --nomi-text: \(text); --nomi-surface: \(surface); --nomi-accent: \(accent); }
        html, body { margin: 0; background: var(--nomi-surface); color: var(--nomi-text); font: 13px -apple-system, BlinkMacSystemFont, sans-serif; }
        body { padding: 8px; box-sizing: border-box; }
        button, input { font: inherit; color: inherit; }
        </style>
        </head>
        <body>
        \(fragment)
        </body>
        </html>
        """
    }

    private struct Region {
        enum Kind { case text, fence }
        var kind: Kind
        var info: String
        var body: String
        var closed: Bool
    }

    private static func regions(in source: String) -> [Region] {
        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var regions: [Region] = []
        var text: [String] = []
        func flushText() {
            guard !text.isEmpty else { return }
            regions.append(Region(kind: .text, info: "", body: text.joined(separator: "\n"), closed: true))
            text.removeAll()
        }
        var index = 0
        while index < lines.count {
            if let info = openingInfo(lines[index]) {
                flushText()
                index += 1
                var body: [String] = []
                var closed = false
                while index < lines.count {
                    if isClosingFence(lines[index]) {
                        closed = true
                        index += 1
                        break
                    }
                    body.append(lines[index])
                    index += 1
                }
                regions.append(Region(kind: .fence, info: info, body: body.joined(separator: "\n"), closed: closed))
            } else {
                text.append(lines[index])
                index += 1
            }
        }
        flushText()
        return regions
    }

    private static func openingInfo(_ line: String) -> String? {
        let spaces = line.prefix { $0 == " " }.count
        guard spaces <= 3 else { return nil }
        let trimmed = line.dropFirst(spaces)
        guard trimmed.hasPrefix("```") else { return nil }
        return String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
    }

    private static func isClosingFence(_ line: String) -> Bool {
        let spaces = line.prefix { $0 == " " }.count
        guard spaces <= 3 else { return false }
        let core = line.dropFirst(spaces).trimmingCharacters(in: .whitespaces)
        return core.count >= 3 && core.allSatisfy { $0 == "`" }
    }

    private static func htmlTitle(_ info: String) -> String? {
        let trimmed = info.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        guard lower == "html" || lower.hasPrefix("html ") || lower.hasPrefix("html\t") else { return nil }
        return String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
    }

    private static func markdown(_ source: String) -> [Piece] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var pieces: [Piece] = []
        var paragraph: [String] = []
        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { pieces.append(.paragraph(text)) }
            paragraph.removeAll()
        }
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
                index += 1
                continue
            }
            if let heading = heading(line) {
                flushParagraph()
                pieces.append(heading)
                index += 1
                continue
            }
            if isTableStart(lines, index) {
                flushParagraph()
                pieces.append(readTable(lines, from: &index))
                continue
            }
            if listItem(line) != nil {
                flushParagraph()
                pieces.append(readList(lines, from: &index))
                continue
            }
            paragraph.append(line)
            index += 1
        }
        flushParagraph()
        return pieces
    }

    private static func heading(_ line: String) -> Piece? {
        let spaces = line.prefix { $0 == " " }.count
        guard spaces <= 3 else { return nil }
        let trimmed = line.dropFirst(spaces)
        var count = 0
        for character in trimmed {
            if character == "#" { count += 1 } else { break }
        }
        guard (1...6).contains(count) else { return nil }
        let rest = trimmed.dropFirst(count)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .heading(min(count, 3), text)
    }

    private static func listItem(_ line: String) -> (ordered: Bool, text: String)? {
        let spaces = line.prefix { $0 == " " }.count
        guard spaces <= 3 else { return nil }
        let trimmed = line.dropFirst(spaces)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return (false, String(trimmed.dropFirst(2)))
        }
        var digits = 0
        for character in trimmed {
            if character.isNumber { digits += 1 } else { break }
        }
        guard (1...4).contains(digits) else { return nil }
        let after = trimmed.dropFirst(digits)
        guard after.hasPrefix(". ") else { return nil }
        return (true, String(after.dropFirst(2)))
    }

    private static func readList(_ lines: [String], from index: inout Int) -> Piece {
        let ordered = listItem(lines[index])?.ordered ?? false
        var items: [String] = []
        while index < lines.count, let item = listItem(lines[index]), item.ordered == ordered {
            items.append(item.text)
            index += 1
        }
        return .list(ordered: ordered, items: items)
    }

    private static func isTableStart(_ lines: [String], _ index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        return isTableLine(lines[index]) && isSeparator(lines[index + 1])
    }

    private static func isTableLine(_ line: String) -> Bool {
        line.contains("|")
    }

    private static func isSeparator(_ line: String) -> Bool {
        let parts = cells(line)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= 3 && trimmed.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func cells(_ line: String) -> [String] {
        var parts = line.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if parts.first?.isEmpty == true { parts.removeFirst() }
        if parts.last?.isEmpty == true { parts.removeLast() }
        return parts
    }

    private static func readTable(_ lines: [String], from index: inout Int) -> Piece {
        let header = cells(lines[index])
        index += 2
        var rows: [[String]] = []
        while index < lines.count, isTableLine(lines[index]), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            rows.append(cells(lines[index]))
            index += 1
        }
        return .table(header: header, rows: rows)
    }

    private static func scriptHasSource(_ folded: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"<script\b[^>]*\ssrc\s*="#, options: [.caseInsensitive]) else { return false }
        let range = NSRange(folded.startIndex..., in: folded)
        return regex.firstMatch(in: folded, range: range) != nil
    }

    private static func hasExternalAddress(_ folded: String) -> Bool {
        let patterns = [
            ##"\b(?:src|href|xlink:href)\s*=\s*['"]?\s*(?:https?:|//)"##,
            ##"url\(\s*['"]?\s*(?:https?:|//|data:)"##,
            ##"\bhref\s*=\s*['"](?!#)[^'"]+['"]"##,
            ##"\bhref\s*=\s*(?!['"#\s])\S+"##,
        ]
        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
            return regex.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)) != nil
        }
    }

    private static func hasBlockedInput(_ folded: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"type\s*=\s*['"]?(?:file|password)\b"#, options: [.caseInsensitive]) else { return false }
        return regex.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)) != nil
    }
}

enum AnswerInline {
    static func render(_ source: String, size: CGFloat = 15, weight: Font.Weight = .regular) -> AttributedString {
        var result = AttributedString()
        var index = source.startIndex
        while index < source.endIndex {
            if source[index...].hasPrefix("**"),
               let end = closing(source, from: source.index(index, offsetBy: 2), marker: "**") {
                result.append(styled(String(source[source.index(index, offsetBy: 2)..<end]), size: size, weight: .semibold))
                index = source.index(end, offsetBy: 2)
                continue
            }
            if source[index...].hasPrefix("__"),
               let end = closing(source, from: source.index(index, offsetBy: 2), marker: "__") {
                result.append(styled(String(source[source.index(index, offsetBy: 2)..<end]), size: size, weight: .semibold))
                index = source.index(end, offsetBy: 2)
                continue
            }
            if source[index] == "`", let end = source[source.index(after: index)...].firstIndex(of: "`") {
                result.append(styled(String(source[source.index(after: index)..<end]), size: size - 2, weight: weight, code: true))
                index = source.index(after: end)
                continue
            }
            if source[index] == "*", !source[index...].hasPrefix("**"),
               let end = closing(source, from: source.index(after: index), marker: "*") {
                result.append(styled(String(source[source.index(after: index)..<end]), size: size, weight: weight, italic: true))
                index = source.index(after: end)
                continue
            }
            if source[index] == "[", let linked = link(source, from: index, size: size, weight: weight) {
                result.append(linked.text)
                index = linked.next
                continue
            }
            result.append(styled(String(source[index]), size: size, weight: weight))
            index = source.index(after: index)
        }
        return result
    }

    private static func closing(_ source: String, from start: String.Index, marker: String) -> String.Index? {
        var index = start
        while index < source.endIndex {
            if source[index...].hasPrefix(marker) { return index }
            index = source.index(after: index)
        }
        return nil
    }

    private static func link(_ source: String, from start: String.Index, size: CGFloat, weight: Font.Weight) -> (text: AttributedString, next: String.Index)? {
        guard let labelEnd = source[source.index(after: start)...].firstIndex(of: "]") else { return nil }
        let open = source.index(after: labelEnd)
        guard open < source.endIndex, source[open] == "(", let urlEnd = source[source.index(after: open)...].firstIndex(of: ")") else { return nil }
        let label = String(source[source.index(after: start)..<labelEnd])
        let urlString = String(source[source.index(after: open)..<urlEnd])
        var text = styled(label.isEmpty ? urlString : label, size: size, weight: weight)
        if let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            text.link = url
            text.foregroundColor = AppColor.accent
        }
        return (text, source.index(after: urlEnd))
    }

    private static func styled(_ text: String, size: CGFloat, weight: Font.Weight, italic: Bool = false, code: Bool = false) -> AttributedString {
        var part = AttributedString(text)
        var attributes = AttributeContainer()
        if code {
            attributes.font = .system(size: size, design: .monospaced)
            attributes.foregroundColor = AppColor.textSecondary
        } else {
            var font = Font.system(size: size, weight: weight)
            if italic { font = font.italic() }
            attributes.font = font
            attributes.foregroundColor = AppColor.textPrimary
        }
        part.mergeAttributes(attributes)
        return part
    }
}
