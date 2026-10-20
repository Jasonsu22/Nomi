import Foundation

/// Fits a long transcript into a model's budget, line by line, keeping time order.
enum TranscriptSelection {
    /// All lines when they fit. Otherwise the lines most relevant to `query`, each with its
    /// neighbours when there is room, because a point often runs across paragraphs. With no
    /// relevant line at all, the transcript from its start.
    static func pick(_ lines: [String], query: String, budget: Int) -> [String] {
        guard size(of: lines) > budget else { return lines }
        let scores = LibrarySearch.relevance(of: lines, to: query)
        var chosen = Set<Int>()
        var used = 0
        func take(_ index: Int) -> Bool {
            guard lines.indices.contains(index), !chosen.contains(index) else { return true }
            let cost = lines[index].count + 1
            guard used + cost <= budget else { return false }
            chosen.insert(index)
            used += cost
            return true
        }
        if scores.allSatisfy({ $0 == 0 }) {
            for index in lines.indices where take(index) == false { break }
        } else {
            let ranked = scores.indices.filter { scores[$0] > 0 }.sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
            for index in ranked {
                guard take(index) else { continue }
                _ = take(index - 1)
                _ = take(index + 1)
            }
        }
        return chosen.sorted().map { lines[$0] }
    }

    /// Consecutive pieces of at most `budget` characters. With `maxChunks`, a longer transcript
    /// keeps that many evenly spaced pieces and reports that it skipped the rest.
    static func chunks(_ lines: [String], budget: Int, maxChunks: Int? = nil) -> (chunks: [[String]], skipped: Bool) {
        var all: [[String]] = []
        var current: [String] = []
        var used = 0
        for line in lines {
            let cost = line.count + 1
            if !current.isEmpty, used + cost > budget {
                all.append(current)
                current = []
                used = 0
            }
            current.append(line.count > budget ? String(line.prefix(budget)) : line)
            used += min(cost, budget)
        }
        if !current.isEmpty { all.append(current) }
        guard let maxChunks, maxChunks > 0, all.count > maxChunks else { return (all, false) }
        guard maxChunks > 1 else { return ([all[0]], true) }
        let picked = (0..<maxChunks).map { all[Int((Double($0) * Double(all.count - 1) / Double(maxChunks - 1)).rounded())] }
        return (picked, true)
    }

    static func size(of lines: [String]) -> Int {
        lines.reduce(0) { $0 + $1.count + 1 }
    }
}
