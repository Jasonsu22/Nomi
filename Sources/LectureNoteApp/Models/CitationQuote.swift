import Foundation

/// Finds the words in a cited passage that the answer's sentence actually relies on, so a citation's
/// preview can show and mark them, the way NotebookLM shows the quoted text.
enum CitationQuote {
    static let excerptLimit = 520
    static let quoteLimit = 320

    private static let enders: Set<Character> = ["。", "！", "？", "；", ".", "!", "?", ";", "\n"]

    /// The passage cut into sentences, keeping their end marks.
    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if enders.contains(character) {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { result.append(piece) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    /// The answer's own words just before a citation marker: the sentence or list item it ends.
    static func claim(in answer: String, before marker: String.Index) -> String {
        let head = answer[..<marker]
        var start = head.startIndex
        var index = head.endIndex
        // Step back over the marker run itself ([1][2]) and spaces, then to the previous sentence end.
        while index > head.startIndex {
            let previous = head.index(before: index)
            let character = head[previous]
            if enders.contains(character), head.distance(from: previous, to: head.endIndex) > 3 {
                start = index
                break
            }
            index = previous
        }
        let text = String(head[start...])
            .replacingOccurrences(of: #"[\[【]\d+[\]】]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[*_`#>|]"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lowercased words in Latin script and two-character pieces of Chinese or Japanese.
    static func tokens(_ text: String) -> Set<String> {
        var result = Set<String>()
        var word = ""
        var previousCJK: Character?
        func flush() {
            if word.count >= 2, !stopWords.contains(word) { result.insert(word) }
            word = ""
        }
        for character in text.lowercased() {
            if isCJK(character) {
                flush()
                if let previous = previousCJK { result.insert(String([previous, character])) }
                previousCJK = character
            } else {
                previousCJK = nil
                if character.isLetter || character.isNumber { word.append(character) } else { flush() }
            }
        }
        flush()
        return result
    }

    /// The best one or two sentences of `body` for `claim`, and a short excerpt around them.
    /// With nothing in common, the passage's opening is used.
    static func pick(in body: String, for claim: String) -> (quote: String, excerpt: String) {
        let parts = sentences(body)
        guard !parts.isEmpty else { return ("", "") }
        let wanted = tokens(claim)
        var best = 0
        var bestScore = 0.0
        for (index, sentence) in parts.enumerated() {
            let have = tokens(sentence)
            guard !have.isEmpty else { continue }
            let shared = Double(have.intersection(wanted).count)
            // Favours sentences that share many words without rewarding sheer length.
            let score = shared / sqrt(Double(have.count))
            if score > bestScore {
                bestScore = score
                best = index
            }
        }
        var quote = parts[best]
        var last = best
        if quote.count < 40, best + 1 < parts.count {
            quote += " " + parts[best + 1]
            last = best + 1
        }
        quote = clipped(quote, quoteLimit)
        var excerpt = quote
        if best > 0 { excerpt = parts[best - 1] + " " + excerpt }
        if last + 1 < parts.count { excerpt += " " + parts[last + 1] }
        return (quote, clipped(excerpt, excerptLimit))
    }

    private static func clipped(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            switch $0.value {
            case 0x3040...0x30ff, 0x3400...0x9fff, 0xf900...0xfaff: true
            default: false
            }
        }
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "that", "this", "with", "from", "are", "was", "were", "you", "your", "its", "it's",
        "but", "not", "can", "will", "has", "have", "had", "they", "them", "their", "there", "which", "what", "when",
        "about", "into", "than", "then", "also", "more", "most", "such", "very", "just", "only", "one", "all",
    ]

    /// "31:20" or "1:02:05" at the end of a passage's detail ("2026-11-08 · 31:20"), in seconds.
    static func clockSeconds(in detail: String) -> TimeInterval? {
        guard let match = detail.matches(of: /(\d{1,2}):(\d{2})(?::(\d{2}))?/).last else { return nil }
        let first = Double(match.1) ?? 0, second = Double(match.2) ?? 0
        if let third = match.3.flatMap({ Double($0) }) { return first * 3600 + second * 60 + third }
        return first * 60 + second
    }

    /// "第 3 页", "Page 3", "p. 3", "Slide 12" or "第 12 张" in a detail, as a number.
    static func pageNumber(in detail: String) -> Int? {
        if let match = detail.firstMatch(of: /第\s*(\d+)\s*[页张]/) { return Int(match.1) }
        if let match = detail.firstMatch(of: /(?i)(?:page|p\.|slide)\s*(\d+)/) { return Int(match.1) }
        return nil
    }
}
