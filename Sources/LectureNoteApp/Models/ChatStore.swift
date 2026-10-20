import Foundation

enum ChatStore {
    private static let queue = DispatchQueue(label: "local.nomi.chat-store", qos: .utility)

    private static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nomi", isDirectory: true)
    }

    private static var directory: URL { root.appendingPathComponent("chats", isDirectory: true) }

    private static func file(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    static func load() throws -> [ChatSession] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return urls.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            return try? JSONDecoder().decode(ChatSession.self, from: Data(contentsOf: url))
        }
    }

    static func saveInBackground(_ session: ChatSession, onFailure: @escaping @Sendable () -> Void) {
        queue.async {
            do { try write(session) } catch { onFailure() }
        }
    }

    static func deleteInBackground(_ id: UUID) {
        queue.async { try? FileManager.default.removeItem(at: file(id)) }
    }

    /// Waits for the queued writes only while the application is terminating.
    static func flush() {
        queue.sync {}
    }

    private static func write(_ session: ChatSession) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: file(session.id), options: .atomic)
    }
}
