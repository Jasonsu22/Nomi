import Foundation
import Security

/// API keys live in Nomi's own private file (`LocalSecrets`), not in the keychain.
///
/// Without a Team ID the keychain approves each build separately, so every update and
/// often every launch asked for the login password. A key saved by an earlier version
/// moves into the file the first time it is used, which may ask for the password one
/// last time. Nothing reads the keychain at launch: even a "silent" read can wait on
/// that dialog and hold up the window.
enum APIKeyStore {
    static func read(service: String, account: String) throws -> String {
        if let stored = LocalSecrets.get(service: service, account: account) { return stored }
        let legacy: String?
        do {
            legacy = try LegacyKeychain.read(service: service, account: account, allowPrompt: true)
                ?? LocalSecrets.developmentCopy(service: service, account: account)
        } catch {
            guard let copy = LocalSecrets.developmentCopy(service: service, account: account) else { throw error }
            legacy = copy
        }
        guard let legacy else { return "" }
        try keep(legacy, service: service, account: account)
        return legacy
    }

    /// Whether a key is saved, without reading an old keychain copy (that could ask for the password).
    static func contains(service: String, account: String) -> Bool {
        LocalSecrets.get(service: service, account: account) != nil
            || LegacyKeychain.contains(service: service, account: account)
    }

    static func save(service: String, account: String, secret: String) throws {
        if secret.isEmpty {
            try LocalSecrets.remove(service: service, account: account)
        } else {
            try LocalSecrets.set(secret, service: service, account: account)
        }
        LegacyKeychain.remove(service: service, account: account)
    }

    static func delete(service: String, account: String) throws {
        try LocalSecrets.remove(service: service, account: account)
        // An old keychain copy left behind would come back on the next read.
        LegacyKeychain.remove(service: service, account: account)
    }

    private static func keep(_ secret: String, service: String, account: String) throws {
        try LocalSecrets.set(secret, service: service, account: account)
        LegacyKeychain.remove(service: service, account: account)
    }
}

/// Where earlier versions kept keys. Only read and cleared now, never written.
private enum LegacyKeychain {
    static func read(service: String, account: String, allowPrompt: Bool) throws -> String? {
        var request = query(service, account, allowPrompt: allowPrompt)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            if !allowPrompt { return nil }
            throw llmError(tr("无法读取保存的 API 密钥，请在设置里重新填写。"))
        }
        return secret.isEmpty ? nil : secret
    }

    static func contains(service: String, account: String) -> Bool {
        var request = query(service, account, allowPrompt: false)
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Never asks for the password; an entry the keychain will not let go of is simply left there.
    static func remove(service: String, account: String) {
        SecItemDelete(query(service, account, allowPrompt: false) as CFDictionary)
    }

    private static func query(_ service: String, _ account: String, allowPrompt: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if !allowPrompt { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip }
        return query
    }
}
