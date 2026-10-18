import Foundation

struct FixtureEvent {
    var time: TimeInterval
    var kind: Kind

    enum Kind {
        case tail(text: String, start: TimeInterval, revision: Int)
        case commit(Commit, tail: String)
    }
}

enum FixtureError: Error, CustomStringConvertible {
    case missing
    case invalidLine(Int)

    var description: String {
        switch self {
        case .missing:
            "找不到示例回放。"
        case .invalidLine(let line):
            "示例回放第 \(line) 行无法读取。"
        }
    }
}

enum SampleLecture {
    static func load() throws -> [FixtureEvent] {
        guard let url = locate() else { throw FixtureError.missing }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parse(text)
    }

    static func parse(_ text: String) throws -> [FixtureEvent] {
        var events: [FixtureEvent] = []
        for (offset, raw) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let data = line.data(using: .utf8),
                  let row = try? JSONDecoder().decode(Row.self, from: data)
            else { throw FixtureError.invalidLine(offset + 1) }
            events.append(try row.event(line: offset + 1))
        }
        return events.sorted { $0.time < $1.time }
    }

    private static func locate() -> URL? {
        let bundle = Bundle.module
        return bundle.url(forResource: "sample-lecture", withExtension: "jsonl", subdirectory: "Fixtures")
            ?? bundle.url(forResource: "sample-lecture", withExtension: "jsonl")
    }
}

private struct Row: Decodable {
    var t: Double
    var type: String
    var text: String?
    var start: Double?
    var revision: Int?
    var id: Int?
    var source: String?
    var translation: String?
    var end: Double?
    var tail: String?

    func event(line: Int) throws -> FixtureEvent {
        switch type {
        case "tail":
            guard let text, let start else { throw FixtureError.invalidLine(line) }
            return FixtureEvent(
                time: t,
                kind: .tail(text: text, start: start, revision: revision ?? 0)
            )
        case "commit":
            guard let id, let source, let start, let end else { throw FixtureError.invalidLine(line) }
            let commit = Commit(
                id: id,
                source: source,
                translation: translation ?? "",
                start: start,
                end: end
            )
            return FixtureEvent(time: t, kind: .commit(commit, tail: tail ?? ""))
        default:
            throw FixtureError.invalidLine(line)
        }
    }
}
