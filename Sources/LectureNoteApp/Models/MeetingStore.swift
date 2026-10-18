import Foundation

@MainActor
enum MeetingStore {
    struct Snapshot: Codable {
        var meetings: [Meeting]
        var categories: [MeetingCategory]
    }

    private static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nomi/meetings.json")
    }

    static func load() throws -> Snapshot? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
    }

    static func save(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
    }
}
