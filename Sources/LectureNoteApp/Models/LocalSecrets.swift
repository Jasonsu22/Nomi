import Foundation

/// API keys kept in a file that only this user account can read (mode 0600), in
/// ~/Library/Application Support/Nomi/api-keys.json.
///
/// Nomi has no Team ID, so the keychain asked for the login password after every update
/// and often on every launch. Keys live here instead. Other programs running as this
/// user could read the file, which is the trade for never being asked.
enum LocalSecrets {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var location = defaultLocation
    nonisolated(unsafe) private static var values: [String: String]?

    private static var defaultLocation: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nomi", isDirectory: true)
            .appendingPathComponent("api-keys.json")
    }

    /// The copy development builds kept before release builds stopped using the keychain.
    /// It may be older than the keychain, so it is only a fallback when the keychain cannot be read.
    static func developmentCopy(service: String, account: String) -> String? {
        let file = defaultLocation.deletingLastPathComponent().appendingPathComponent("secrets.json")
        guard let data = try? Data(contentsOf: file),
              let values = try? JSONDecoder().decode([String: String].self, from: data),
              let secret = values[key(service, account)], !secret.isEmpty else { return nil }
        return secret
    }

    static func get(service: String, account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return loaded()[key(service, account)]
    }

    static func set(_ secret: String, service: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var next = loaded()
        next[key(service, account)] = secret
        try write(next)
        values = next
    }

    static func remove(service: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var next = loaded()
        guard next.removeValue(forKey: key(service, account)) != nil else { return }
        try write(next)
        values = next
    }

    /// Points the store at another file. Tests only.
    static func use(_ url: URL?) {
        lock.lock()
        location = url ?? defaultLocation
        values = nil
        lock.unlock()
    }

    private static func key(_ service: String, _ account: String) -> String {
        "\(service)\n\(account)"
    }

    private static func loaded() -> [String: String] {
        if let values { return values }
        let read = (try? Data(contentsOf: location))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        values = read
        return read
    }

    /// Writes a private temporary file and renames it over the old one, so the secret
    /// is never readable by others and a crash leaves either the old or the new file.
    private static func write(_ secrets: [String: String]) throws {
        let manager = FileManager.default
        let directory = location.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(secrets)
        let temporary = directory.appendingPathComponent(".secrets-\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw llmError(tr("无法保存 API 密钥。"))
        }
        guard rename(temporary.path, location.path) == 0 else {
            try? manager.removeItem(at: temporary)
            throw llmError(tr("无法保存 API 密钥。"))
        }
    }
}
