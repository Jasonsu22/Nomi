import Foundation

/// A short hint for the speech model while recording: the meeting title, its course, and the
/// terms that recur in its linked slides, so course words ("modularity", "节点") are heard right.
enum TranscriptionTopic {
    static let maxTerms = 30

    static func text(title: String, course: String?, terms: [String]) -> String {
        var parts: [String] = []
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title != tr("未命名会议") { parts.append("Lecture: \(title).") }
        if let course = course?.trimmingCharacters(in: .whitespacesAndNewlines), !course.isEmpty {
            parts.append("Course: \(course).")
        }
        if !terms.isEmpty { parts.append("Terms: \(terms.joined(separator: ", ")).") }
        return parts.joined(separator: " ")
    }

    /// The words and phrases that recur in slide text: English words of four letters or more that
    /// are not everyday words, acronyms, and Chinese two- to four-character terms. Most frequent first.
    static func terms(in text: String, limit: Int = maxTerms) -> [String] {
        var counts: [String: Int] = [:]
        var shown: [String: String] = [:]
        let latin = try! NSRegularExpression(pattern: #"\b[A-Z]{2,}[0-9]*\b|[A-Za-z][A-Za-z\-]{3,}"#)
        let range = NSRange(text.startIndex..., in: text)
        for match in latin.matches(in: text, range: range) {
            guard let span = Range(match.range, in: text) else { continue }
            let word = String(text[span]).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let key = word.lowercased()
            let acronym = word.count >= 2 && word == word.uppercased()
            guard acronym || key.count >= 4, !stopWords.contains(key) else { continue }
            counts[key, default: 0] += 1
            // An acronym keeps its capitals; other words are shown as written most often (first seen).
            if shown[key] == nil || word == word.uppercased() { shown[key] = word }
        }
        for run in text.split(whereSeparator: { !isHan($0) }) where run.count >= 2 {
            let chars = Array(run)
            for size in 2...4 where chars.count >= size {
                for start in 0...(chars.count - size) {
                    let term = String(chars[start..<start + size])
                    guard !term.contains(where: { functionHan.contains($0) }) else { continue }
                    counts[term, default: 0] += 1
                    shown[term] = term
                }
            }
        }
        let recurring = counts.filter { term, count in
            count >= (term.first.map(isHan) == true ? 3 : 2)
        }
        let ranked = recurring.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        // A Chinese term inside a longer one that is just as frequent says nothing new.
        let kept = ranked.filter { term in
            !ranked.contains { other in other != term && other.contains(term) && counts[other] == counts[term] }
        }
        return Array(kept.prefix(limit)).compactMap { shown[$0] }
    }

    private static func isHan(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
    }

    private static let functionHan: Set<Character> = Set("的了是在和与及或等这那一个我你他她它们也就都而被把从对为以之其")

    private static let stopWords: Set<String> = [
        "this", "that", "with", "from", "have", "they", "will", "your", "what", "when", "which", "there",
        "their", "about", "would", "these", "those", "into", "than", "then", "them", "were", "been", "more",
        "some", "such", "only", "also", "each", "other", "many", "most", "much", "very", "just", "like",
        "over", "here", "where", "after", "before", "because", "between", "through", "while", "does", "make",
        "used", "using", "use", "example", "examples", "page", "slide", "slides", "figure", "table", "note",
        "chapter", "section", "lecture", "week", "today", "question", "questions", "answer", "first", "second",
        "next", "last", "same", "different", "know", "need", "want", "show", "shows", "shown", "good", "well",
        "http", "https", "www", "com", "html", "should", "could", "must", "can't", "don't", "it's", "how",
    ]
}
