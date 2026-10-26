import Foundation

/// Tools the main answer can call. The call itself is removed before the text is shown.
enum ChatTools {
    static let webSearch = "web_search"
    static let searchLibrary = "search_library"
    static let createDemo = "create_demo"

    /// Tools whose results the model needs before it can go on, so the reply pauses at the call.
    static let lookups: Set<String> = [webSearch, searchLibrary]

    struct Call: Equatable {
        var name: String
        var body: String
    }

    struct Parsed: Equatable {
        var visible: String
        var calls: [Call]
    }

    /// With `stopAtSearch`, text and other calls after the first lookup (web_search or search_library) are dropped,
    /// because the model has not seen the results yet. Further lookup calls are still collected.
    static func parse(_ raw: String, streaming: Bool, stopAtSearch: Bool = false) -> Parsed {
        var visible = ""
        var calls: [Call] = []
        var searching = false
        var index = raw.startIndex
        while index < raw.endIndex {
            guard let start = raw.range(of: "<tool", options: .caseInsensitive, range: index..<raw.endIndex) else {
                if !searching { visible += raw[index...] }
                break
            }
            if !searching { visible += raw[index..<start.lowerBound] }
            guard let openEnd = raw[start.upperBound...].firstIndex(of: ">") else {
                if !streaming, !searching { visible += raw[start.lowerBound...] }
                break
            }
            let open = raw[start.lowerBound...openEnd]
            let name = attribute("name", in: String(open))?.lowercased() ?? ""
            let bodyStart = raw.index(after: openEnd)
            let bodyEnd: String.Index
            if let close = raw.range(of: "</tool>", options: .caseInsensitive, range: bodyStart..<raw.endIndex) {
                bodyEnd = close.lowerBound
                index = close.upperBound
            } else {
                // While streaming, the closing tag may still be coming.
                if streaming { break }
                // Small local models often leave the tag open. The call then ends at the next code fence,
                // blank line or tool tag, or at the end of the reply, and is hidden instead of shown as raw text.
                let rest = bodyStart..<raw.endIndex
                bodyEnd = ["```", "\n\n", "<tool"].compactMap { raw.range(of: $0, options: .caseInsensitive, range: rest)?.lowerBound }.min() ?? raw.endIndex
                index = bodyEnd
            }
            let body = String(raw[bodyStart..<bodyEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !body.isEmpty, !searching || lookups.contains(name) {
                calls.append(Call(name: name, body: body))
            }
            if stopAtSearch, lookups.contains(name), !body.isEmpty { searching = true }
        }
        if streaming { visible = droppingOpenTag(visible) }
        return Parsed(visible: visible, calls: calls)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let folded = tag.lowercased()
        let key = name.lowercased()
        guard let found = folded.range(of: key) else { return nil }
        var index = found.upperBound
        while index < tag.endIndex, tag[index].isWhitespace || tag[index] == "=" { index = tag.index(after: index) }
        guard index < tag.endIndex else { return nil }
        let quote = tag[index]
        guard quote == "\"" || quote == "'" else { return nil }
        let valueStart = tag.index(after: index)
        guard let valueEnd = tag[valueStart...].firstIndex(of: quote) else { return nil }
        let value = String(tag[valueStart..<valueEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Hides the beginning of a tool tag that has not finished arriving.
    private static func droppingOpenTag(_ text: String) -> String {
        let marker = "<tool"
        let lower = text.lowercased()
        for count in stride(from: marker.count, through: 1, by: -1) {
            let suffix = String(marker.prefix(count))
            if lower.hasSuffix(suffix) {
                return String(text.dropLast(count))
            }
        }
        return text
    }
}
