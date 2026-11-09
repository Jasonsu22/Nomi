import Foundation
import Testing
@testable import LectureNoteApp

/// One suite, run in order: each test points the shared key file somewhere else.
@Suite(.serialized)
struct LocalSecretsTests {
    @Test func keysStayPrivateAndSurviveARelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("secrets.json")
        LocalSecrets.use(file)
        defer {
            LocalSecrets.use(nil)
            try? FileManager.default.removeItem(at: directory)
        }

        #expect(LocalSecrets.get(service: "llm", account: "a") == nil)
        try LocalSecrets.set("sk-one", service: "llm", account: "a")
        try LocalSecrets.set("tv-two", service: "search", account: "a")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)

        // A new launch reads the file again instead of the in-memory copy.
        LocalSecrets.use(file)
        #expect(LocalSecrets.get(service: "llm", account: "a") == "sk-one")
        #expect(LocalSecrets.get(service: "search", account: "a") == "tv-two")

        try LocalSecrets.remove(service: "llm", account: "a")
        LocalSecrets.use(file)
        #expect(LocalSecrets.get(service: "llm", account: "a") == nil)
        #expect(LocalSecrets.get(service: "search", account: "a") == "tv-two")
    }

    @Test func keysAreSavedReadAndDeletedInNomisOwnFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("secrets.json")
        LocalSecrets.use(file)
        defer {
            LocalSecrets.use(nil)
            try? FileManager.default.removeItem(at: directory)
        }
        // A service name no keychain holds, so nothing old is found or moved.
        let service = "local.nomi.test-\(UUID().uuidString)"

        #expect(try APIKeyStore.read(service: service, account: "a") == "")
        #expect(!APIKeyStore.contains(service: service, account: "a"))

        try APIKeyStore.save(service: service, account: "a", secret: "sk-one")
        #expect(APIKeyStore.contains(service: service, account: "a"))
        LocalSecrets.use(file)  // as after a relaunch
        #expect(try APIKeyStore.read(service: service, account: "a") == "sk-one")

        try APIKeyStore.save(service: service, account: "a", secret: "")
        #expect(!APIKeyStore.contains(service: service, account: "a"), "saving an empty key removes it")

        try APIKeyStore.save(service: service, account: "b", secret: "sk-two")
        try APIKeyStore.delete(service: service, account: "b")
        #expect(try APIKeyStore.read(service: service, account: "b") == "")
    }
}
