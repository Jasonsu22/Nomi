import Foundation

/// One thing Nomi does while answering: reading files, searching, thinking or writing.
/// A running step shows the leaf animation; a finished one shows what it found.
struct AnswerStep: Identifiable, Equatable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case files, library, web, thinking, writing
    }

    var id = UUID()
    var kind: Kind
    /// What it is doing, shown while it runs: "正在联网搜索「…」…".
    var title: String
    /// What it found, shown after: "找到 5 个网页". Empty steps disappear when done.
    var detail = ""
    var startedAt: Date
    var endedAt: Date?
    /// Files read, for the folded summary line.
    var count = 0
    /// The thinking, so "思考了 N 秒" can be opened to read it. Not saved with the chat.
    var thought = ""

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, detail, startedAt, endedAt, count
    }

    var isRunning: Bool { endedAt == nil }
    var seconds: Int { max(1, Int(((endedAt ?? .now).timeIntervalSince(startedAt)).rounded())) }
}

/// The folded line under a finished answer: "用时 14 秒 · 读了 1 个文件 · 搜索 2 次 · 思考了 4 秒".
enum AnswerStepSummary {
    static func line(steps: [AnswerStep], seconds: Double?) -> String {
        var parts: [String] = []
        if let seconds, seconds >= 1 { parts.append(trf("用时 %d 秒", Int(seconds.rounded()))) }
        let files = steps.filter { $0.kind == .files }.reduce(0) { $0 + $1.count }
        if files > 0 { parts.append(trf("读了 %d 个文件", files)) }
        let searches = steps.filter { $0.kind == .library || $0.kind == .web }.count
        if searches > 0 { parts.append(trf("搜索 %d 次", searches)) }
        if let thought = steps.first(where: { $0.kind == .thinking }) { parts.append(trf("思考了 %d 秒", thought.seconds)) }
        return parts.joined(separator: " · ")
    }

    /// Steps worth keeping with the turn: finished, with something to say.
    static func kept(_ steps: [AnswerStep]) -> [AnswerStep] {
        steps.filter { !$0.isRunning && !$0.detail.isEmpty }
    }

    /// A query as it reads in a step line.
    static func quoted(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.count > 40 ? String(flat.prefix(40)) + "…" : flat
    }

    /// Short names of the sites a web search found.
    static func sites(_ blocks: [ContextBlock]) -> String {
        var hosts: [String] = []
        for block in blocks {
            guard let url = block.url, let host = URL(string: url)?.host else { continue }
            let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if !hosts.contains(name) { hosts.append(name) }
        }
        return hosts.prefix(3).joined(separator: ", ")
    }
}
