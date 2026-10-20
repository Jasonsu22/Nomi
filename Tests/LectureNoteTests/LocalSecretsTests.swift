#if DEBUG
import Foundation
import Testing
@testable import LectureNoteApp

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
}
#endif
