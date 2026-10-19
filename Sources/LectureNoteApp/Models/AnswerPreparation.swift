import Foundation

/// Structure and exported files only. AppKit text decoration stays on the main actor.
struct PreparedAnswer: Sendable {
    var source: String
    var pieces: [AnswerDocument.Piece]
    var files: ChatFiles.Export
    var filesReady = true
}

@MainActor
enum AnswerPreparation {
    private final class Entry: NSObject {
        let value: PreparedAnswer
        init(_ value: PreparedAnswer) { self.value = value }
    }
    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 64
        cache.totalCostLimit = 8 * 1_024 * 1_024
        return cache
    }()
    private static let worker = AnswerPreparationWorker()

    static func cached(_ source: String) -> PreparedAnswer? {
        cache.object(forKey: source as NSString)?.value
    }

    /// Layout must have real text on its first pass. Neighbour prefetch normally
    /// supplies this; a cold visible row parses structure once, without file I/O.
    static func display(_ source: String) -> PreparedAnswer {
        if let ready = cached(source) { return ready }
        let value = PreparedAnswer(source: source, pieces: AnswerDocument.pieces(in: source), files: .init(), filesReady: false)
        cache.setObject(Entry(value), forKey: source as NSString, cost: source.utf8.count * 3)
        return value
    }

    /// Only parse data; do not create historical text views or hidden WebKit pages.
    static func prewarm(_ sources: [String]) async {
        for source in sources {
            guard !Task.isCancelled else { return }
            if !source.isEmpty, cached(source)?.filesReady != true {
                _ = await prepare(source, streaming: false, priority: .utility)
            }
        }
    }

    /// A cold row must show readable content immediately, never a blank spinner.
    /// Generated HTML is deliberately omitted rather than flashing raw scripts.
    static func preview(_ source: String) -> String {
        var lines: [String] = []
        var fenced = false
        var length = 0
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                fenced.toggle()
                continue
            }
            if !fenced {
                lines.append(String(line))
                length += line.count
                if length >= 4_000 { break }
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func prepare(_ source: String, streaming: Bool, priority: TaskPriority = .userInitiated) async -> PreparedAnswer? {
        if !streaming, let value = cached(source), value.filesReady { return value }
        let pieces = !streaming ? cached(source)?.pieces : nil
        let task = Task.detached(priority: priority) { [worker] in
            try await worker.prepare(source, streaming: streaming, pieces: pieces)
        }
        let result = await withTaskCancellationHandler {
            try? await task.value
        } onCancel: {
            task.cancel()
        }
        guard !Task.isCancelled, let result else { return nil }
        // Streaming prefixes would evict useful finished answers after just a few seconds.
        if !streaming {
            cache.setObject(Entry(result), forKey: source as NSString, cost: source.utf8.count * 3)
        }
        return result
    }
}

/// A slow parse must not create a growing set of concurrent token-prefix jobs.
private actor AnswerPreparationWorker {
    func prepare(_ source: String, streaming: Bool, pieces ready: [AnswerDocument.Piece]?) throws -> PreparedAnswer {
        try Task.checkCancellation()
        let pieces = ready ?? AnswerDocument.pieces(in: source, streaming: streaming)
        try Task.checkCancellation()
        let files = ChatFiles.export(pieces: pieces)
        try Task.checkCancellation()
        return PreparedAnswer(source: source, pieces: pieces, files: files)
    }
}
