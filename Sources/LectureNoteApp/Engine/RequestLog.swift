import Foundation

/// One line per API request in `~/Library/Application Support/Nomi/logs/requests.jsonl`: how much was
/// sent, how long the first word and the whole reply took, and how many input tokens the service
/// read from its cache. Never the question, the answer or the key.
enum RequestLog {
    struct Entry {
        var profile: LLMAPIProfile
        var request: LLMRequest
        var mode: LLMAPIMode
        var options: LLMRequestBody.Options
        var started: Date
        var firstToken: Date?
        var usage: LLMUsage
        var failure: String?
    }

    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nomi/logs/requests.jsonl")
    }

    /// Kept under about a megabyte; the oldest half goes when it grows past that.
    private static let sizeLimit = 1_000_000
    private static let queue = DispatchQueue(label: "local.nomi.request-log", qos: .utility)

    static func line(_ entry: Entry, now: Date = .now) -> [String: Any] {
        let characters = entry.request.system.count + entry.request.messages.reduce(0) { $0 + $1.text.count }
        var line: [String: Any] = [
            "at": ISO8601DateFormatter().string(from: entry.started),
            "label": entry.request.label,
            "host": LLMRequestBody.host(of: entry.profile),
            "model": entry.profile.modelID,
            "api": entry.profile.format == .anthropic ? "messages" : entry.mode.rawValue,
            "thinking": entry.options.thinking ? entry.request.thinking.rawValue : "off",
            "messages": entry.request.messages.count,
            "images": entry.request.messages.reduce(0) { $0 + $1.images.count },
            "chars": characters,
            "total_ms": Int(now.timeIntervalSince(entry.started) * 1000),
        ]
        if let first = entry.firstToken { line["first_token_ms"] = Int(first.timeIntervalSince(entry.started) * 1000) }
        if let input = entry.usage.input { line["input_tokens"] = input }
        if let cached = entry.usage.cached { line["cached_tokens"] = cached }
        if let output = entry.usage.output { line["output_tokens"] = output }
        if let failure = entry.failure { line["error"] = String(failure.prefix(200)) }
        return line
    }

    static func record(_ entry: Entry) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let data = try? JSONSerialization.data(withJSONObject: line(entry), options: [.sortedKeys]) else { return }
        let url = file
        queue.async {
            let manager = FileManager.default
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data + Data("\n".utf8))
            if let size = try? handle.offset(), size > sizeLimit, let all = try? Data(contentsOf: url) {
                let half = all.suffix(from: all.count / 2)
                let rest = half.firstIndex(of: UInt8(ascii: "\n")).map { half.suffix(from: $0 + 1) } ?? half
                try? Data(rest).write(to: url, options: .atomic)
            }
        }
    }
}
