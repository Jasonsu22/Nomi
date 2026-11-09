import Foundation

/// Speech models sometimes fall into a loop on silence or noise and write the same word or phrase
/// hundreds of times ("Okay. Okay. Okay. …"). The engine now stops these as they happen; this cleans
/// transcripts saved before that, and anything that still slips through. It follows the engine's
/// rules (voice-core `repeats.rs`): a phrase of up to 12 words (or Chinese characters) repeated 4
/// times in a row covering 12 words or more, or one word 8 times, is kept once. Ordinary emphasis is shorter and stays.
enum RepeatCleanup {
    static let longestPhrase = 12
    /// The same short line, phrase after phrase: up to this many in a row are kept.
    static let allowedSameLines = 3
    static let shortLineCharacters = 24

    /// One word 8 times, or a longer phrase 4 times covering 12 words or more.
    static func isLoop(_ phraseUnits: Int, _ count: Int) -> Bool {
        phraseUnits == 1 ? count >= 8 : count >= 4 && count * phraseUnits >= 12
    }

    private struct Unit {
        var text: Substring
        var key: String
    }

    private static func isCJK(_ c: Character) -> Bool {
        c.unicodeScalars.contains {
            switch $0.value {
            case 0x3040...0x30ff, 0x3400...0x9fff, 0xac00...0xd7af, 0xf900...0xfaff, 0x20000...0x323af: true
            default: false
            }
        }
    }

    private static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "'" || c == "’"
    }

    /// One word, or one Chinese or Japanese character, with the punctuation and space after it.
    private static func units(_ text: String) -> [Unit] {
        var result: [Unit] = []
        var start = text.startIndex
        var inCore = false
        var coreDone = false
        var key = ""
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            let word = isWordCharacter(c)
            let startsNew = word && (coreDone || (inCore && (isCJK(c) || key.last.map(isCJK) == true)))
            if startsNew && index > start {
                result.append(Unit(text: text[start..<index], key: key))
                key = ""
                start = index
                coreDone = false
            }
            if word {
                inCore = true
                key += c.lowercased()
            } else if inCore {
                coreDone = true
            }
            index = text.index(after: index)
        }
        if start < text.endIndex {
            result.append(Unit(text: text[start...], key: key))
        }
        return result
    }

    /// The text with every loop of a repeated word or phrase cut back to its first time.
    static func collapse(_ text: String) -> String {
        let units = units(text)
        func same(_ a: Int, _ b: Int, _ length: Int) -> Bool {
            (0..<length).allSatisfy { !units[a + $0].key.isEmpty && units[a + $0].key == units[b + $0].key }
        }
        var kept = ""
        var changed = false
        var index = 0
        while index < units.count {
            var best: (length: Int, count: Int)?
            for length in 1...longestPhrase {
                guard index + length * 2 <= units.count else { break }
                var count = 1
                while index + (count + 1) * length <= units.count && same(index, index + count * length, length) {
                    count += 1
                }
                if isLoop(length, count), count * length > (best.map { $0.length * $0.count } ?? 0) {
                    best = (length, count)
                }
            }
            if let best {
                units[index..<index + best.length].forEach { kept += $0.text }
                index += best.length * best.count
                changed = true
            } else {
                kept += units[index].text
                index += 1
            }
        }
        guard changed else { return text }
        return String(kept.reversed().drop(while: \.isWhitespace).reversed())
    }

    private static func lineKey(_ text: String) -> String {
        String(text.filter { $0.isLetter || $0.isNumber }).lowercased()
    }

    /// The paragraphs with loops cut inside each line, and the same short line repeated more than
    /// `allowedSameLines` times in a row dropped. Nil when nothing needed cleaning.
    static func cleaned(_ paragraphs: [Paragraph]) -> [Paragraph]? {
        var changed = false
        var lastKey = ""
        var sameCount = 0
        let result = paragraphs.map { paragraph -> Paragraph in
            var paragraph = paragraph
            paragraph.commits = paragraph.commits.compactMap { commit in
                var commit = commit
                let source = collapse(commit.source)
                if source != commit.source {
                    commit.source = source
                    commit.translation = collapse(commit.translation)
                    changed = true
                }
                let key = lineKey(source)
                guard !key.isEmpty else { return commit }
                if key == lastKey && key.count <= shortLineCharacters {
                    sameCount += 1
                } else {
                    lastKey = key
                    sameCount = 1
                }
                if sameCount > allowedSameLines {
                    changed = true
                    return nil
                }
                return commit
            }
            return paragraph
        }
        return changed ? result.filter { !$0.commits.isEmpty || !$0.tail.isEmpty } : nil
    }
}
