import Foundation
import Security

/// Reads try a silent keychain lookup first and only show the dialog when it fails.
///
/// Without a Team ID the login keychain keeps "Always Allow" per binary hash, so
/// each new build asks once per key. Release builds accept that one approval per
/// version. Development builds (NOMI_DEV_KEYS) copy each key into `LocalSecrets`
/// after that first read, so rebuilding does not ask again.
enum KeychainTrust {
    private enum Outcome {
        case value(String)
        case missing
        case needsPrompt
        case failed
    }

    static func read(service: String, account: String) throws -> String {
        #if NOMI_DEV_KEYS
        if let stored = LocalSecrets.get(service: service, account: account) { return stored }
        let secret = try readKeychain(service: service, account: account)
        if !secret.isEmpty { try? LocalSecrets.set(secret, service: service, account: account) }
        return secret
        #else
        return try readKeychain(service: service, account: account)
        #endif
    }

    private static func readKeychain(service: String, account: String) throws -> String {
        let first = attempt(service: service, account: account, allowPrompt: false)
        let outcome: Outcome
        if case .needsPrompt = first {
            outcome = attempt(service: service, account: account, allowPrompt: true)
        } else {
            outcome = first
        }
        switch outcome {
        case .value(let secret):
            return secret
        case .missing:
            return ""
        case .needsPrompt, .failed:
            throw llmError(tr("无法读取钥匙串中的 API 密钥。"))
        }
    }

    static func save(service: String, account: String, secret: String) throws {
        #if NOMI_DEV_KEYS
        try LocalSecrets.set(secret, service: service, account: account)
        // Keep the keychain copy current for release builds; a rebuilt binary may not be allowed to.
        try? saveKeychain(service: service, account: account, secret: secret)
        #else
        try saveKeychain(service: service, account: account, secret: secret)
        #endif
    }

    private static func saveKeychain(service: String, account: String, secret: String) throws {
        let query = operation(attributes(service: service, account: account), allowPrompt: false)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(secret.utf8)] as CFDictionary)
        if status == errSecSuccess { return }
        if status != errSecItemNotFound { throw llmError(tr("无法保存 API 密钥到钥匙串。")) }
        var item = attributes(service: service, account: account)
        item[kSecValueData as String] = Data(secret.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if let access = makeAccess(label: service) {
            item[kSecAttrAccess as String] = access
        }
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw llmError(tr("无法保存 API 密钥到钥匙串。"))
        }
    }

    static func delete(service: String, account: String) throws {
        #if NOMI_DEV_KEYS
        try LocalSecrets.remove(service: service, account: account)
        // The keychain copy must go too, or the next read would bring the key back.
        let query = operation(attributes(service: service, account: account), allowPrompt: true)
        #else
        let query = operation(attributes(service: service, account: account), allowPrompt: false)
        #endif
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw llmError(tr("无法删除钥匙串中的 API 密钥。"))
        }
    }

    private static func attributes(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func operation(_ attributes: [String: Any], allowPrompt: Bool) -> [String: Any] {
        var query = attributes
        if !allowPrompt {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        }
        return query
    }

    private static func attempt(service: String, account: String, allowPrompt: Bool) -> Outcome {
        var request = operation(attributes(service: service, account: account), allowPrompt: allowPrompt)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return .missing }
        if status == errSecInteractionNotAllowed { return .needsPrompt }
        guard status == errSecSuccess, let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            return .failed
        }
        return .value(secret)
    }

    /// New entries trust this certificate. Updating an existing entry's access
    /// list raises the keychain dialog, so only creation uses this.
    private static func makeAccess(label: String) -> SecAccess? {
        var trusted: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath(nil, &trusted) == errSecSuccess, let trusted else { return nil }
        var access: SecAccess?
        guard SecAccessCreate(label as CFString, [trusted] as CFArray, &access) == errSecSuccess else { return nil }
        return access
    }
}
