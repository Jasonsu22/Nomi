import Foundation
import Testing
@testable import LectureNoteApp

struct MemoryTests {
    private func item(_ text: String, kind: MemoryItem.Kind = .preference, pinned: Bool = false, age: TimeInterval = 0) -> MemoryItem {
        let date = Date(timeIntervalSince1970: 1_800_000_000 - age)
        return MemoryItem(text: text, kind: kind, createdAt: date, updatedAt: date, pinned: pinned)
    }

    @Test func aLearningReplyBecomesSafeLimitedChanges() {
        let language = item("Prefers answers in English")
        let course = item("Takes BIOL 101", kind: .course)
        let reply = """
        Sure, here is the update:
        {"add": [
            {"text": "Midterm for BIOL 101 is on 2026-11-03", "kind": "goal"},
            {"text": "Takes BIOL 101", "kind": "course"},
            {"text": "API key is sk-abcdefghijklmnop1234", "kind": "other"},
            {"text": "Phone is +1 617 555 0199", "kind": "other"},
            {"text": "Likes interactive demos", "kind": "style"},
            {"text": "Wants short answers", "kind": "nonsense"}
         ],
         "update": [{"id": "\(language.id.uuidString)", "text": "Prefers answers in Chinese with English terms"},
                    {"id": "\(UUID().uuidString)", "text": "unknown item"}],
         "remove": []}
        """
        let changes = MemoryLearning.parse(reply, known: [language, course])
        #expect(changes.update == [language.id: "Prefers answers in Chinese with English terms"])
        // Three changes at most: the update, then the first two safe new facts. The duplicate, the key and the phone number are dropped.
        #expect(changes.add.map(\.text) == ["Midterm for BIOL 101 is on 2026-11-03", "Likes interactive demos"])
        #expect(changes.add.first?.kind == .goal)

        let applied = MemoryLearning.apply(changes, to: [language, course])
        #expect(applied.count == 4)
        #expect(applied.first { $0.id == language.id }?.text == "Prefers answers in Chinese with English terms")
    }

    @Test func aReplyWithoutJSONChangesNothing() {
        #expect(MemoryLearning.parse("Nothing to remember.", known: []).isEmpty)
        #expect(MemoryLearning.parse("{}", known: []).isEmpty)
        #expect(MemoryLearning.parse("{\"add\": \"oops\"}", known: []).isEmpty)
    }

    @Test func secretsAreRejectedButDatesAreKept() {
        #expect(MemoryLearning.isSafe("Final exam on 2026-12-14"))
        #expect(MemoryLearning.isSafe("期中考试在 2026-11-03"))
        #expect(!MemoryLearning.isSafe("My password is hunter2"))
        #expect(!MemoryLearning.isSafe("邮箱 student@example.edu"))
        #expect(!MemoryLearning.isSafe("电话 138 0013 8000"))
        #expect(!MemoryLearning.isSafe("token ghp_abcdefghijklmnopqrstuvwxyz0123"))
    }

    @Test func studyTopicsAboutTokensAreKeptButCredentialsAndLinksAreNot() {
        #expect(MemoryLearning.isSafe("Finds tokenization in NLP hard"))
        #expect(MemoryLearning.isSafe("Studies the token economy in ECON 210"))
        #expect(!MemoryLearning.isSafe("access token is abc123"))
        #expect(!MemoryLearning.isSafe("token: 9f8e7d"))
        #expect(!MemoryLearning.isSafe("Prefers sources from https://example.com"))
        #expect(!MemoryLearning.isSafe("Reads www.example.com daily"))
    }

    @MainActor @Test func memoryIsOnForLocalModelsAndWaitsForTheStudentWithAPIModels() {
        let key = "nomi.memory.enabled"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)

        let memory = UserMemory(file: nil)
        #expect(memory.isEnabled(for: .local))
        #expect(!memory.isEnabled(for: .api))
        memory.setEnabled(true)
        #expect(memory.isEnabled(for: .api))
        #expect(UserMemory(file: nil).isEnabled(for: .api))
        memory.setEnabled(false)
        #expect(!memory.isEnabled(for: .local))
    }

    @MainActor @Test func skippedTurnsAreNotLearnedAgain() {
        let memory = UserMemory(file: nil)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        memory.skip(through: date)
        #expect(memory.learnedThrough == date)
        memory.skip(through: date.addingTimeInterval(-60))
        #expect(memory.learnedThrough == date)
        #expect(memory.items.isEmpty)
    }

    @Test func thePromptGetsPinnedAndRelevantFactsWithinBudget() {
        let pinned = item("Answer in Chinese", pinned: true, age: 900)
        let biology = item("Struggles with cell respiration in BIOL 101", kind: .course, age: 500)
        let recent = item("Likes short summaries", age: 1)
        let picked = MemoryLearning.selected([recent, biology, pinned], question: "Explain cell respiration again")
        #expect(picked.map(\.text) == [pinned.text, biology.text, recent.text])

        let tight = MemoryLearning.selected([recent, biology, pinned], question: "hi", budget: 40)
        #expect(tight.map(\.text) == [pinned.text, recent.text])

        let block = MemoryLearning.promptBlock(picked)
        #expect(block.contains("- Answer in Chinese"))
        #expect(MemoryLearning.promptBlock([]).isEmpty)

        let system = ChatContext.composedSystemPrompt(override: nil, language: "English", allowsWeb: false, hasPassages: false, skills: [], memory: block)
        #expect(system.contains("What you know about this student"))
    }

    @MainActor @Test func memoryIsSavedAndReadBack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("memory.json")
        let through = Date(timeIntervalSince1970: 1_700_000_000)

        let memory = UserMemory(file: file)
        let learned = memory.learn(MemoryChanges(add: [.init(text: "Takes ECON 201", kind: .course)]), through: through)
        #expect(learned == ["Takes ECON 201"])
        let id = try #require(memory.items.first?.id)
        memory.togglePin(id)
        memory.update(id, text: "Takes ECON 201 and ECON 210")
        memory.flush()

        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)

        let reloaded = UserMemory(file: file)
        #expect(reloaded.items.map(\.text) == ["Takes ECON 201 and ECON 210"])
        #expect(reloaded.items.first?.pinned == true)
        #expect(reloaded.learnedThrough == through)

        reloaded.update(id, text: "   ")
        #expect(reloaded.items.isEmpty)
        reloaded.clear()
        #expect(reloaded.learnedThrough.map { $0 > through } == true)
    }

    @Test func olderChatsWithoutAMemoryNoteStillLoad() throws {
        let json = #"{"id": "\#(UUID().uuidString)", "question": "Hi", "answer": "Hello", "modelName": "m", "createdAt": 0, "citations": [], "images": []}"#
        let turn = try JSONDecoder().decode(ChatTurn.self, from: Data(json.utf8))
        #expect(turn.memoryNote == nil)
        var noted = turn
        noted.memoryNote = ["Likes demos"]
        let roundTrip = try JSONDecoder().decode(ChatTurn.self, from: JSONEncoder().encode(noted))
        #expect(roundTrip.memoryNote == ["Likes demos"])
    }
}
