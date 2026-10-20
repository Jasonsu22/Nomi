import Foundation

// Development builds only. Release builds leave this out unless built with
// NOMI_DEV_KEYS=1, so an app given to others keeps its keys in the keychain alone.
#if DEBUG || NOMI_DEV_KEYS

/// API keys kept in a file that only this user account can read (mode 0600).
///
/// The login keychain remembers "Always Allow" per build hash when the app has no
/// Team ID, so every rebuild asked for the password again. In development builds
/// keys are read from the keychain once, then kept here, and rebuilds stay quiet.
/// Other programs running as this user can read the file, so release builds do not use it.
enum LocalSecrets {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var location = defaultLocation
    nonisolated(unsafe) private static var values: [String: String]?

    private static var defaultLocation: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nomi", isDirectory: true)
            .appendingPathComponent("secrets.json")
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
            throw llmError(tr("无法保存 API 密钥到钥匙串。"))
        }
        guard rename(temporary.path, location.path) == 0 else {
            try? manager.removeItem(at: temporary)
            throw llmError(tr("无法保存 API 密钥到钥匙串。"))
        }
    }
}

#endif
