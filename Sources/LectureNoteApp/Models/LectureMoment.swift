import Foundation

/// The exact spoken sentences a lecture citation points to.
///
/// A library search hands the model a chunk of several paragraphs, each followed by its translation,
/// and the citation only keeps the chunk's opening time. So the time, the words, the translation,
/// the jump and the audio all have to be found again from the transcript itself.
///
/// The recognizer times its output in pieces cut at pauses (commits), often two or three sentences
/// and up to half a minute long, with no time for each sentence. So the best commits are found
/// first, then the sentence inside them, with its time estimated from where its words fall in the
/// commit: a sentence a third of the way through the text starts about a third of the way through
/// the commit's time.
struct LectureMoment: Equatable {
    /// Index of the paragraph in the meeting.
    var paragraph: Int
    /// The commits that hold the quoted sentences.
    var commits: Range<Int>
    /// When the quoted words start and end, estimated within their commits.
    var at: TimeInterval
    var end: TimeInterval
    /// The quoted sentences in the original language, as they appear in the paragraph.
    var source: String
    /// The same sentences' translation, as it appears in the paragraph's translation.
    var translation: String
}

enum LectureMoments {
    /// About how much text a library chunk holds (`LibrarySearch.meetingDocuments` cuts at 700
    /// characters of original plus translation); a little more so the last sentence is not missed.
    static let chunkReach = 1_000

    /// One sentence of a commit, where it sits in the commit's text, and its estimated time.
    struct Piece: Equatable {
        var commit: Int
        var range: Range<Int>
        var text: String
        var start: TimeInterval
        var end: TimeInterval
    }

    private static let enders: Set<Character> = ["。", "！", "？", "；", ".", "!", "?", ";", "\n"]

    /// The sentences of `text`, spoken from `start` to `end`, each timed by where its characters fall.
    static func pieces(of text: String, commit: Int, start: TimeInterval, end: TimeInterval) -> [Piece] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }
        let total = Double(characters.count), span = max(0, end - start)
        var result: [Piece] = []
        var from = 0
        func close(_ upTo: Int) {
            var lower = from, upper = upTo
            while lower < upper, characters[lower].isWhitespace { lower += 1 }
            while upper > lower, characters[upper - 1].isWhitespace { upper -= 1 }
            guard upper > lower else { return }
            result.append(Piece(
                commit: commit, range: lower..<upper, text: String(characters[lower..<upper]),
                start: start + span * Double(lower) / total, end: start + span * Double(upper) / total
            ))
        }
        for (index, character) in characters.enumerated() where enders.contains(character) {
            // "3.5" or "e.g." is not a sentence end: a full stop must be followed by a space or the end.
            if character == ".", index + 1 < characters.count, !characters[index + 1].isWhitespace { continue }
            close(index + 1)
            from = index + 1
        }
        close(characters.count)
        return result
    }

    /// The sentences in `paragraphs` that best match `needle`, looking in the chunk that starts at
    /// `near`, or in the whole lecture without a time. Nil when nothing shares a word with it.
    static func locate(in paragraphs: [Paragraph], near: TimeInterval?, needle: String, sourceLanguage: String = "en", targetLanguage: String = "zh") -> LectureMoment? {
        let wanted = CitationQuote.tokens(needle)
        guard !wanted.isEmpty, !paragraphs.isEmpty else { return nil }
        var window = Array(paragraphs.indices)
        if let near {
            let first = paragraphs.lastIndex { $0.openedAt <= near + 1.5 } ?? 0
            var reach = 0
            window = []
            for index in paragraphs.indices[first...] {
                window.append(index)
                reach += paragraphs[index].renderedSource(language: sourceLanguage).count
                    + paragraphs[index].renderedTranslation(language: targetLanguage).count
                if reach >= chunkReach { break }
            }
        }
        // First the commits: one, or two or three in a row when the quote runs across them.
        var bestParagraph = -1
        var bestRun = 0..<0
        var bestScore = 0.0
        for index in window {
            let commits = paragraphs[index].commits
            for start in commits.indices {
                for length in 1...3 where start + length <= commits.count {
                    let run = commits[start..<(start + length)]
                    let score = max(
                        score(of: run.map(\.source).joined(separator: " "), against: wanted),
                        score(of: run.map(\.translation).joined(separator: " "), against: wanted)
                    )
                    // A longer run must earn its place by matching clearly more.
                    if score > bestScore * (length > 1 ? 1.25 : 1) {
                        bestScore = score
                        bestParagraph = index
                        bestRun = start..<(start + length)
                    }
                }
            }
        }
        guard bestParagraph >= 0 else { return nil }
        let paragraph = paragraphs[bestParagraph]
        let source = bestRun.flatMap { i in pieces(of: paragraph.commits[i].source, commit: i, start: paragraph.commits[i].start, end: paragraph.commits[i].end) }
        let translated = bestRun.flatMap { i in pieces(of: paragraph.commits[i].translation, commit: i, start: paragraph.commits[i].start, end: paragraph.commits[i].end) }

        // Then the sentences: the best one to three in a row, in whichever language the quote matches
        // better; the other language takes the sentences spoken at the same time.
        let fromSource = bestSpan(source, wanted)
        let fromTranslation = bestSpan(translated, wanted)
        let useSource = fromSource.score >= fromTranslation.score
        let picked = useSource ? fromSource.span : fromTranslation.span
        let lead = useSource ? source : translated
        let other = useSource ? translated : source
        guard !picked.isEmpty else { return nil }
        let from = lead[picked.lowerBound].start, to = lead[picked.upperBound - 1].end
        let matched = overlapping(other, from: from, to: to)
        let sourceSpan = useSource ? picked : matched
        let translationSpan = useSource ? matched : picked
        return LectureMoment(
            paragraph: bestParagraph,
            commits: bestRun,
            at: from,
            end: to,
            source: text(of: source, sourceSpan, in: paragraph, translation: false, language: paragraph.sourceLanguage ?? sourceLanguage),
            translation: text(of: translated, translationSpan, in: paragraph, translation: true, language: paragraph.targetLanguage ?? targetLanguage)
        )
    }

    /// The run of one to three pieces that best matches.
    private static func bestSpan(_ pieces: [Piece], _ wanted: Set<String>) -> (span: Range<Int>, score: Double) {
        var best = 0..<0, bestScore = 0.0
        for start in pieces.indices {
            for length in 1...3 where start + length <= pieces.count {
                let score = score(of: pieces[start..<(start + length)].map(\.text).joined(separator: " "), against: wanted)
                if score > bestScore * (length > 1 ? 1.15 : 1) {
                    bestScore = score
                    best = start..<(start + length)
                }
            }
        }
        return (best, bestScore)
    }

    /// The pieces spoken between `from` and `to`: those whose middle falls inside, or else the one
    /// that overlaps it most.
    private static func overlapping(_ pieces: [Piece], from: TimeInterval, to: TimeInterval) -> Range<Int> {
        let inside = pieces.indices.filter { let middle = (pieces[$0].start + pieces[$0].end) / 2; return middle >= from - 0.01 && middle <= to + 0.01 }
        if let first = inside.first, let last = inside.last { return first..<(last + 1) }
        let overlap = { (piece: Piece) in max(0, min(piece.end, to) - max(piece.start, from)) }
        guard let best = pieces.indices.max(by: { overlap(pieces[$0]) < overlap(pieces[$1]) }), overlap(pieces[best]) > 0 else { return 0..<0 }
        return best..<(best + 1)
    }

    /// The words of `span`, cut from the commits' own text so they read as in the paragraph.
    private static func text(of pieces: [Piece], _ span: Range<Int>, in paragraph: Paragraph, translation: Bool, language: String) -> String {
        guard !span.isEmpty else { return "" }
        let first = pieces[span.lowerBound], last = pieces[span.upperBound - 1]
        var parts: [String] = []
        for commit in first.commit...last.commit {
            let characters = Array(translation ? paragraph.commits[commit].translation : paragraph.commits[commit].source)
            let lower = commit == first.commit ? first.range.lowerBound : 0
            let upper = commit == last.commit ? last.range.upperBound : characters.count
            if lower < upper { parts.append(String(characters[lower..<upper])) }
        }
        return TranscriptText.join(parts, language: language)
    }

    /// Shared words, scaled so a sentence is not favoured just for being long.
    private static func score(of text: String, against wanted: Set<String>) -> Double {
        let have = CitationQuote.tokens(text)
        guard !have.isEmpty else { return 0 }
        return Double(have.intersection(wanted).count) / sqrt(Double(have.count))
    }
}
