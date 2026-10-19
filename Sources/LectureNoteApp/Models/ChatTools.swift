import Foundation

/// Tools the main answer can call. The call itself is removed before the text is shown.
enum ChatTools {
    static let webSearch = "web_search"
    static let createDemo = "create_demo"

    struct Call: Equatable {
        var name: String
        var body: String
    }

    struct Parsed: Equatable {
        var visible: String
        var calls: [Call]
    }

    static func parse(_ raw: String, streaming: Bool) -> Parsed {
        var visible = ""
        var calls: [Call] = []
        var index = raw.startIndex
        while index < raw.endIndex {
            guard let start = raw.range(of: "<tool", options: .caseInsensitive, range: index..<raw.endIndex) else {
                visible += raw[index...]
                break
            }
            visible += raw[index..<start.lowerBound]
            guard let openEnd = raw[start.upperBound...].firstIndex(of: ">") else {
                if !streaming { visible += raw[start.lowerBound...] }
                break
            }
            let open = raw[start.lowerBound...openEnd]
            let name = attribute("name", in: String(open))?.lowercased() ?? ""
            let bodyStart = raw.index(after: openEnd)
            guard let close = raw.range(of: "</tool>", options: .caseInsensitive, range: bodyStart..<raw.endIndex) else {
                if !streaming { visible += raw[start.lowerBound...] }
                break
            }
            let body = String(raw[bodyStart..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !body.isEmpty {
                calls.append(Call(name: name, body: body))
            }
            index = close.upperBound
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
