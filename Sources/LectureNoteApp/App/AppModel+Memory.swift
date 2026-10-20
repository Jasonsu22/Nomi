import Foundation

extension AppModel {
    /// Finished turns the memory pass has not read yet, oldest first, at most the last eight.
    func unlearnedTurns() -> [ChatTurn] {
        let since = memory.learnedThrough ?? .distantPast
        let turns = chats.flatMap(\.turns).filter { turn in
            turn.createdAt > since && turn.error == nil && !turn.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return Array(turns.sorted { $0.createdAt < $1.createdAt }.suffix(8))
    }

    /// Whether memory is on for the model in use (see `UserMemory.isEnabled(for:)`).
    var memoryEnabled: Bool {
        memory.isEnabled(for: llmConfiguration.mode)
    }

    /// One learning pass, prepared when an answer finishes and run by the after-answer queue.
    struct MemoryJob {
        var mode: LLMMode
        var profile: LLMAPIProfile?
        var system: String
        var prompt: String
        var known: [MemoryItem]
        var last: ChatTurn
    }

    /// A learning pass once a few new turns have finished, or nil. After a failure it waits for three
    /// more turns, and after three failures in a row it moves past those turns, so a broken model or
    /// key does not resend the same conversation after every answer.
    func memoryJob() -> MemoryJob? {
        guard memoryEnabled, canRunBackgroundWork else { return nil }
        let turns = unlearnedTurns()
        let needed = min(MemoryLearning.batch + 3 * memoryFailures, 8)
        guard turns.count >= needed, let last = turns.last else { return nil }
        let known = memory.items
        return MemoryJob(
            mode: llmConfiguration.mode,
            profile: llmConfiguration.activeProfile,
            system: MemoryLearning.system(language: prompts.modelLanguageName),
            prompt: MemoryLearning.prompt(items: known, turns: turns),
            known: known,
            last: last
        )
    }

    func runMemory(_ job: MemoryJob) async {
        afterAnswerGenerating = true
        let reply: String
        do {
            reply = try await backgroundReply(mode: job.mode, profile: job.profile, system: job.system, prompt: job.prompt, maxTokens: 300)
        } catch {
            // A pass stopped for a question is not a failure; the same turns are read again later.
            guard !Self.isCancellation(error) else { return }
            memoryFailures += 1
            if memoryFailures >= 3 {
                memory.skip(through: job.last.createdAt)
                memoryFailures = 0
            }
            return
        }
        memoryFailures = 0
        let changes = MemoryLearning.parse(reply, known: job.known)
        let learned = memory.learn(changes, through: job.last.createdAt)
        if !learned.isEmpty { noteMemory(learned, onTurn: job.last.id) }
    }

    /// Shows what was learned under the answer that triggered the pass, without moving the chat up in history.
    private func noteMemory(_ learned: [String], onTurn turnID: UUID) {
        guard let chatIndex = chats.firstIndex(where: { $0.turns.contains { $0.id == turnID } }),
              let turnIndex = chats[chatIndex].turns.firstIndex(where: { $0.id == turnID }) else { return }
        chats[chatIndex].turns[turnIndex].memoryNote = learned
        guard chatsReady else { return }
        let message = tr("无法保存对话。")
        ChatStore.saveInBackground(chats[chatIndex]) { [weak self] in
            Task { @MainActor in self?.chatError = message }
        }
    }

    func showMemorySettings() {
        revealMemorySettings = true
        page = .settings
    }

    /// The facts about the student to place in this question's system prompt. `kinds` limits which
    /// facts are used; a meeting summary only takes how the student likes answers written.
    func memoryPrompt(for question: String, kinds: Set<MemoryItem.Kind>? = nil) -> String {
        guard memoryEnabled else { return "" }
        let items = kinds.map { kinds in memory.items.filter { kinds.contains($0.kind) } } ?? memory.items
        return MemoryLearning.promptBlock(MemoryLearning.selected(items, question: question))
    }
}
