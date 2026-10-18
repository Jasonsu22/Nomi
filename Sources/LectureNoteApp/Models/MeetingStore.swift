import Foundation

enum MeetingStore {
    struct Snapshot: Codable, Sendable {
        var meetings: [Meeting]
        var categories: [MeetingCategory]
    }

    private static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nomi")
    }

    private static var file: URL { root.appendingPathComponent("meetings.json") }

    static func audioDirectory(for meetingID: UUID) -> URL {
        root.appendingPathComponent("meetings/\(meetingID.uuidString)", isDirectory: true)
    }

    // One serial queue for every write, so a delayed background save can never
    // land after (and overwrite) a newer synchronous save.
    private static let queue = DispatchQueue(label: "local.nomi.meeting-store", qos: .utility)

    static func load() throws -> Snapshot? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
    }

    static func save(_ snapshot: Snapshot) throws {
        try queue.sync { try write(snapshot) }
    }

    static func saveInBackground(_ snapshot: Snapshot, onFailure: @escaping @Sendable () -> Void) {
        queue.async {
            do { try write(snapshot) } catch { onFailure() }
        }
    }

    private static func write(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
    }
}
