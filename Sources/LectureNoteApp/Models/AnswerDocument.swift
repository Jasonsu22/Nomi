import AppKit
import Foundation
import SwiftUI

enum AnswerDocument {
    enum Piece: Equatable {
        case heading(Int, String)
        case paragraph(String)
        case list(ordered: Bool, items: [String])
        case code(String)
        case table(header: [String], rows: [[String]])
        case math(String)
        case widget(title: String, html: String)
        case preparing
    }

    static func pieces(in source: String, streaming: Bool = false) -> [Piece] {
        var result: [Piece] = []
        for region in regions(in: source) {
            switch region.kind {
            case .text:
                result.append(contentsOf: markdown(region.body, streaming: streaming))
            case .fence:
                let body = region.body
                if streaming, !region.closed, isDisplayFence(region.info, body: body) {
                    result.append(.preparing)
                    continue
                }
                guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let ready = region.closed || finishedDocument(body)
                if ready,
                   let title = widgetTitle(info: region.info, body: body),
                   let fragment = widgetFragment(from: body) {
                    let name = title.isEmpty ? (documentTitle(body) ?? "") : title
                    result.append(.widget(title: name, html: fragment))
                } else {
                    result.append(.code(body))
                }
            }
        }
        return result
    }

    /// A fragment, or a complete page reduced to the styles, inline scripts, and body.
    static func widgetFragment(from html: String) -> String? {
        guard passesSafety(html) else { return nil }
        let fragment = unwrapDocument(html)
        guard allowsWidget(fragment) else { return nil }
        return fragment
    }

    static func allowsWidget(_ html: String) -> Bool {
        let folded = html.lowercased()
        let shell = ["body", "html", "head", "meta"]
        if shell.contains(where: { containsTag(folded, $0) || containsTag(folded, "/\($0)") }) { return false }
        if folded.contains("<!doctype") { return false }
        let banned = [
            "<iframe", "<object", "<embed", "<link", "<base", "<form",
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
        html, body { margin: 0; background: var(--nomi-surface); color: var(--nomi-text); font: 15px -apple-system, BlinkMacSystemFont, sans-serif; }
        body { padding: 8px; box-sizing: border-box; }
        button, input { font: inherit; color: inherit; }
        </style>
        </head>
        <body>
        \(fragment)
        <style>html, body { min-height: 0 !important; height: auto !important; }</style>
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

    private static func widgetTitle(info: String, body: String) -> String? {
        if let title = htmlTitle(info) { return title }
        let trimmed = info.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty else { return nil }
        let folded = body.lowercased()
        guard folded.contains("<!doctype") || containsTag(folded, "html") else { return nil }
        return ""
    }

    private static func documentTitle(_ html: String) -> String? {
        guard let inner = tagInner(html, tag: "title") else { return nil }
        let text = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Drops the page shell. The caller still rejects anything unsafe in the original text.
    private static func unwrapDocument(_ html: String) -> String {
        let folded = html.lowercased()
        let document = folded.contains("<!doctype") || containsTag(folded, "html")
            || containsTag(folded, "head") || containsTag(folded, "body")
        guard document else { return html }
        let assets = keptHead(tagInner(html, tag: "head") ?? "")
        guard let body = tagInner(html, tag: "body") else { return html }
        return (assets + "\n" + body).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func keptHead(_ head: String) -> String {
        let styles = tagBlocks(head, tag: "style").map { "<style>\($0)</style>" }
        let scripts = inlineScriptBlocks(head).map { "<script>\($0)</script>" }
        return (styles + scripts).joined(separator: "\n")
    }

    private static func tagInner(_ html: String, tag: String) -> String? {
        let folded = html.lowercased()
        guard let start = tagRange(folded, tag: tag) else { return nil }
        guard let gt = folded.range(of: ">", range: start.upperBound..<folded.endIndex) else { return nil }
        let end = tagRange(folded, tag: "/\(tag)", from: gt.upperBound)?.lowerBound ?? folded.endIndex
        return String(html[gt.upperBound..<end])
    }

    private static func containsTag(_ folded: String, _ tag: String) -> Bool {
        tagRange(folded, tag: tag) != nil
    }

    private static func tagRange(_ folded: String, tag: String, from start: String.Index? = nil) -> Range<String.Index>? {
        var rest = folded[(start ?? folded.startIndex)...]
        let needle = "<\(tag)"
        while let found = rest.range(of: needle) {
            let after = found.upperBound
            if after == folded.endIndex || isTagBoundary(folded[after]) { return found }
            guard let next = folded.index(found.lowerBound, offsetBy: 1, limitedBy: folded.endIndex) else { return nil }
            rest = folded[next...]
        }
        return nil
    }

    private static func isTagBoundary(_ character: Character) -> Bool {
        character == ">" || character == "/" || character.isWhitespace
    }

    private static func tagBlocks(_ html: String, tag: String) -> [String] {
        var result: [String] = []
        var rest = html[...]
        while let start = rest.range(of: "<\(tag)", options: .caseInsensitive) {
            let after = rest[start.upperBound...]
            guard let gt = after.range(of: ">") else { break }
            guard let end = after.range(of: "</\(tag)", options: .caseInsensitive), end.lowerBound >= gt.upperBound else { break }
            result.append(String(after[gt.upperBound..<end.lowerBound]))
            rest = after[end.upperBound...]
        }
        return result
    }

    private static func inlineScriptBlocks(_ html: String) -> [String] {
        var result: [String] = []
        var rest = html[...]
        while let start = rest.range(of: "<script", options: .caseInsensitive) {
            let after = rest[start.upperBound...]
            guard let gt = after.range(of: ">") else { break }
            let opening = after[..<gt.lowerBound]
            guard let end = after.range(of: "</script", options: .caseInsensitive), end.lowerBound >= gt.upperBound else { break }
            if opening.range(of: "src", options: .caseInsensitive) == nil {
                result.append(String(after[gt.upperBound..<end.lowerBound]))
            }
            rest = after[end.upperBound...]
        }
        return result
    }

    private static func passesSafety(_ html: String) -> Bool {
        let folded = html.lowercased()
        let banned = [
            "<iframe", "<object", "<embed", "<link", "<base", "<form",
            "<img", "<image", "<video", "<audio", "<source", "<track",
            "<frame", "<frameset", "<applet", "<foreignobject",
            "javascript:", "@import", "formaction",
        ]
        if banned.contains(where: { folded.contains($0) }) { return false }
        if scriptHasSource(folded) || hasExternalAddress(folded) || hasBlockedInput(folded) || hasUnsafeMeta(folded) {
            return false
        }
        return true
    }

    private static func hasUnsafeMeta(_ folded: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive]) else { return true }
        let range = NSRange(folded.startIndex..., in: folded)
        for match in regex.matches(in: folded, range: range) {
            guard let span = Range(match.range, in: folded) else { return true }
            let tag = String(folded[span])
            if tag.contains("refresh") { return true }
            let contentType = tag.contains("content-type")
            if tag.contains("http-equiv") && !contentType { return true }
            if !tag.contains("charset") && !tag.contains("viewport") && !contentType { return true }
        }
        return false
    }

    /// A fence the app will render, rather than show as source.
    private static func isDisplayFence(_ info: String, body: String) -> Bool {
        if htmlTitle(info) != nil { return true }
        let trimmed = info.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty else { return false }
        let folded = body.lowercased()
        return folded.contains("<!doctype") || containsTag(folded, "html")
    }

    /// An unfinished fence can still be shown once the page itself has been closed.
    private static func finishedDocument(_ html: String) -> Bool {
        let folded = html.lowercased()
        return containsTag(folded, "/body") || containsTag(folded, "/html")
    }

    private static func htmlTitle(_ info: String) -> String? {
        let trimmed = info.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        guard lower == "html" || lower.hasPrefix("html ") || lower.hasPrefix("html\t") else { return nil }
        return String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
    }

    private static func markdown(_ source: String, streaming: Bool) -> [Piece] {
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
            if streaming, index == lines.count - 1, incompleteMarker(line) {
                index += 1
                continue
            }
            if let math = displayMath(lines, from: &index, streaming: streaming) {
                flushParagraph()
                if !math.isEmpty { pieces.append(.math(math)) }
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

    /// A display formula on its own lines: `\[ ... \]` or `$$ ... $$`.
    /// Returns the latex and advances `index`. Empty means the opener is still unfinished.
    private static func displayMath(_ lines: [String], from index: inout Int, streaming: Bool) -> String? {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        let pair: (String, String)
        if trimmed.hasPrefix("\\[") {
            pair = ("\\[", "\\]")
        } else if trimmed.hasPrefix("$$") {
            pair = ("$$", "$$")
        } else {
            return nil
        }
        let first = String(trimmed.dropFirst(pair.0.count))
        if let range = first.range(of: pair.1) {
            let after = first[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard after.isEmpty else { return nil }
            index += 1
            return String(first[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var body = [first]
        var cursor = index + 1
        var closed = false
        while cursor < lines.count {
            let raw = lines[cursor]
            if let range = raw.range(of: pair.1), raw[range.upperBound...].trimmingCharacters(in: .whitespaces).isEmpty {
                body.append(String(raw[..<range.lowerBound]))
                closed = true
                cursor += 1
                break
            }
            body.append(raw)
            cursor += 1
        }
        guard closed else {
            guard streaming else { return nil }
            index = lines.count
            return ""
        }
        index = cursor
        return body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The last line of a stream that is only a heading or list marker, not yet a sentence.
    private static func incompleteMarker(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "-" || trimmed == "*" || trimmed == "+" { return true }
        var count = 0
        for character in trimmed {
            if character == "#" { count += 1 } else { break }
        }
        if (1...6).contains(count) {
            let rest = trimmed.dropFirst(count)
            if rest.isEmpty || rest.allSatisfy({ $0 == " " || $0 == "\t" }) { return true }
        }
        var digits = 0
        for character in trimmed {
            if character.isNumber { digits += 1 } else { break }
        }
        if (1...4).contains(digits) {
            let rest = trimmed.dropFirst(digits)
            if rest == "." || rest == ". " { return true }
        }
        return false
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

enum MathFormula {
    static func url(latex: String, display: Bool) -> URL? {
        let encoded = latex.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        guard !encoded.isEmpty else { return nil }
        return URL(string: "nomi-math://\(display ? "display" : "inline")/\(encoded)")
    }

    static func latex(from url: URL) -> (latex: String, display: Bool)? {
        guard url.scheme == "nomi-math" else { return nil }
        let path = url.path
        let latex = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !latex.isEmpty else { return nil }
        return (latex, url.host == "display")
    }

    static func block(_ latex: String) -> AttributedString {
        let raw = NSMutableAttributedString(string: "\u{FFFC}")
        raw.addAttribute(.font, value: NSFont.systemFont(ofSize: 18), range: NSRange(location: 0, length: raw.length))
        var text = AttributedString(raw)
        text.link = url(latex: latex, display: true)
        return text
    }
}

enum AnswerInline {
    static func render(
        _ source: String,
        size: CGFloat = 15,
        weight: Font.Weight = .regular,
        citations: [Int: ChatCitation] = [:],
        streaming: Bool = false,
        files: [String: URL] = [:]
    ) -> AttributedString {
        var result = AttributedString()
        var index = source.startIndex
        while index < source.endIndex {
            if source[index] == "`" {
                let content = source.index(after: index)
                if let end = source[content...].firstIndex(of: "`") {
                    let code = String(source[content..<end])
                    if let file = fileURL(code, files: files) {
                        var text = styled(code, size: max(size - 1, 12), weight: .medium)
                        text.link = file
                        text.foregroundColor = AppColor.accent
                        result.append(text)
                    } else {
                        result.append(styled(code, size: size - 2, weight: weight, code: true))
                    }
                    index = source.index(after: end)
                    continue
                }
                if streaming {
                    result.append(styled(String(source[content...]), size: size - 2, weight: weight, code: true))
                    break
                }
            }
            if let math = mathSpan(source, from: index, streaming: streaming) {
                if let url = math.url {
                    var text = styled("\u{FFFC}", size: size, weight: weight)
                    text.link = url
                    result.append(text)
                }
                index = math.next
                continue
            }
            if source[index] == "[" || source[index] == "【" {
                if source[index] == "[", let linked = link(source, from: index, size: size, weight: weight) {
                    result.append(linked.text)
                    index = linked.next
                    continue
                }
                if let cited = citation(source, from: index, size: size, citations: citations) {
                    result.append(cited.text)
                    index = cited.next
                    continue
                }
            }
            if let bare = bareLink(source, from: index, size: size, weight: weight) {
                result.append(bare.text)
                index = bare.next
                continue
            }
            if source[index...].hasPrefix("**") || source[index...].hasPrefix("__") {
                let marker = source[index...].hasPrefix("**") ? "**" : "__"
                let content = source.index(index, offsetBy: marker.count)
                if let end = closing(source, from: content, marker: marker) {
                    result.append(render(String(source[content..<end]), size: size, weight: .semibold, citations: citations, streaming: streaming, files: files))
                    index = source.index(end, offsetBy: marker.count)
                    continue
                }
                if streaming {
                    result.append(render(String(source[content...]), size: size, weight: .semibold, citations: citations, streaming: true, files: files))
                    break
                }
            }
            if source[index] == "*", !source[index...].hasPrefix("**") {
                let content = source.index(after: index)
                if let end = closing(source, from: content, marker: "*") {
                    result.append(withItalic(render(String(source[content..<end]), size: size, weight: weight, citations: citations, streaming: streaming, files: files), size: size, weight: weight))
                    index = source.index(after: end)
                    continue
                }
                if streaming, content < source.endIndex, source[content] != " ", source[content] != "\n" {
                    result.append(withItalic(render(String(source[content...]), size: size, weight: weight, citations: citations, streaming: true, files: files), size: size, weight: weight))
                    break
                }
            }
            result.append(styled(String(source[index]), size: size, weight: weight))
            index = source.index(after: index)
        }
        return result
    }

    private static func fileURL(_ code: String, files: [String: URL]) -> URL? {
        let name = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = files[name] { return url }
        return files.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// A finished formula, or an unfinished one while streaming (then `url` is nil and the tail is hidden).
    private static func mathSpan(
        _ source: String,
        from start: String.Index,
        streaming: Bool
    ) -> (url: URL?, next: String.Index)? {
        let pairs: [(String, String, Bool)] = [
            ("\\[", "\\]", true),
            ("$$", "$$", true),
            ("\\(", "\\)", false),
        ]
        let rest = source[start...]
        for (open, close, display) in pairs where rest.hasPrefix(open) {
            let content = source.index(start, offsetBy: open.count)
            if let range = source[content...].range(of: close) {
                let latex = String(source[content..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let url = latex.isEmpty ? nil : MathFormula.url(latex: latex, display: display)
                return (url, range.upperBound)
            }
            if streaming { return (nil, source.endIndex) }
            return nil
        }
        guard source[start] == "$", !rest.hasPrefix("$$") else { return nil }
        let content = source.index(after: start)
        guard content < source.endIndex, source[content] != " ", source[content] != "\n" else { return nil }
        var end = content
        while end < source.endIndex, source[end] != "$", source[end] != "\n" {
            end = source.index(after: end)
        }
        guard end < source.endIndex, source[end] == "$", source[source.index(before: end)] != " " else { return nil }
        let latex = String(source[content..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latex.isEmpty, let url = MathFormula.url(latex: latex, display: false) else { return nil }
        return (url, source.index(after: end))
    }

    private static func closing(_ source: String, from start: String.Index, marker: String) -> String.Index? {
        var index = start
        while index < source.endIndex {
            if source[index...].hasPrefix(marker) { return index }
            index = source.index(after: index)
        }
        return nil
    }

    private static func citation(
        _ source: String,
        from start: String.Index,
        size: CGFloat,
        citations: [Int: ChatCitation]
    ) -> (text: AttributedString, next: String.Index)? {
        let opener = source[start]
        let closer: Character = opener == "【" ? "】" : "]"
        guard opener == "[" || opener == "【" else { return nil }
        let digitsStart = source.index(after: start)
        guard digitsStart < source.endIndex else { return nil }
        var index = digitsStart
        while index < source.endIndex, source[index].isNumber {
            index = source.index(after: index)
        }
        guard index > digitsStart, index < source.endIndex, source[index] == closer else { return nil }
        let next = source.index(after: index)
        if opener == "[", next < source.endIndex, source[next] == "(" { return nil }
        guard let number = Int(source[digitsStart..<index]),
              let citation = citations[number],
              !citation.inlineLabel.isEmpty,
              let url = citation.inlineURL else { return nil }
        var text = styled(citation.inlineLabel, size: max(size - 1, 12), weight: .medium)
        text.foregroundColor = AppColor.accent
        text.link = url
        return (text, next)
    }

    private static func bareLink(
        _ source: String,
        from start: String.Index,
        size: CGFloat,
        weight: Font.Weight
    ) -> (text: AttributedString, next: String.Index)? {
        let rest = source[start...]
        guard rest.hasPrefix("https://") || rest.hasPrefix("http://") else { return nil }
        var end = start
        while end < source.endIndex, !source[end].isWhitespace, !"<>\"'".contains(source[end]) {
            end = source.index(after: end)
        }
        while end > start, ".,);]】".contains(source[source.index(before: end)]) {
            end = source.index(before: end)
        }
        let urlText = String(source[start..<end])
        guard let url = URL(string: urlText),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        var text = styled(urlText, size: size, weight: weight)
        text.link = url
        text.foregroundColor = AppColor.accent
        return (text, end)
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

    private static func withItalic(_ source: AttributedString, size: CGFloat, weight: Font.Weight) -> AttributedString {
        let text = NSMutableAttributedString(attributedString: NSAttributedString(source))
        guard text.length > 0 else { return source }
        text.addAttribute(.font, value: appFont(size: size, weight: weight, italic: true, code: false), range: NSRange(location: 0, length: text.length))
        return AttributedString(text)
    }

    /// SwiftUI fonts do not survive into the text view, which would otherwise draw the answer at 12pt.
    private static func styled(_ text: String, size: CGFloat, weight: Font.Weight, italic: Bool = false, code: Bool = false) -> AttributedString {
        let raw = NSMutableAttributedString(string: text)
        let range = NSRange(location: 0, length: raw.length)
        guard range.length > 0 else { return AttributedString(text) }
        raw.addAttribute(.font, value: appFont(size: size, weight: weight, italic: italic, code: code), range: range)
        raw.addAttribute(.foregroundColor, value: code ? AppColor.nsTextSecondary : AppColor.nsTextPrimary, range: range)
        return AttributedString(raw)
    }

    private static func appFont(size: CGFloat, weight: Font.Weight, italic: Bool, code: Bool) -> NSFont {
        if code { return NSFont.monospacedSystemFont(ofSize: size, weight: .regular) }
        let base = NSFont.systemFont(ofSize: size, weight: nsWeight(weight))
        guard italic else { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }

    private static func nsWeight(_ weight: Font.Weight) -> NSFont.Weight {
        if weight == .semibold { return .semibold }
        if weight == .bold { return .bold }
        if weight == .medium { return .medium }
        if weight == .light { return .light }
        return .regular
    }
}
