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

    private var canLearnMemory: Bool {
        llmConfiguration.mode == .api ? llmConfiguration.activeProfile != nil : engine is LocalEngine
    }

    /// Learns from recent chats once a few new turns have finished. It runs quietly in the background.
    /// After a failure it waits for three more turns, and after three failures in a row it moves past
    /// those turns, so a broken model or key does not resend the same conversation after every answer.
    func scheduleMemoryLearning() {
        guard memoryEnabled, memoryTask == nil, canLearnMemory else { return }
        let turns = unlearnedTurns()
        let needed = min(MemoryLearning.batch + 3 * memoryFailures, 8)
        guard turns.count >= needed, let last = turns.last else { return }
        let mode = llmConfiguration.mode
        let profile = llmConfiguration.activeProfile
        let system = MemoryLearning.system(language: prompts.modelLanguageName)
        let known = memory.items
        let prompt = MemoryLearning.prompt(items: known, turns: turns)
        memoryTask = Task { [weak self] in
            // A local model has one chat worker, so the pass waits for a quiet moment. A new question cancels the wait.
            if mode == .local { try? await Task.sleep(for: .seconds(30)) }
            guard let self else { return }
            defer {
                self.memoryTask = nil
                self.memoryGenerating = false
            }
            guard !Task.isCancelled, self.memoryEnabled else { return }
            if mode == .local, self.chatGeneratingID != nil || self.assistantIsBusy { return }
            self.memoryGenerating = true
            guard let reply = try? await self.memoryReply(mode: mode, profile: profile, system: system, prompt: prompt) else {
                self.memoryFailures += 1
                if self.memoryFailures >= 3 {
                    self.memory.skip(through: last.createdAt)
                    self.memoryFailures = 0
                }
                return
            }
            self.memoryFailures = 0
            let changes = MemoryLearning.parse(reply, known: known)
            let learned = self.memory.learn(changes, through: last.createdAt)
            if !learned.isEmpty { self.noteMemory(learned, onTurn: last.id) }
        }
    }

    /// A local reply waits for a running memory pass, and cancels one that is only waiting for a quiet moment.
    func waitForMemory() async {
        guard let task = memoryTask else { return }
        if memoryGenerating {
            await task.value
        } else {
            task.cancel()
        }
    }

    private func memoryReply(mode: LLMMode, profile: LLMAPIProfile?, system: String, prompt: String) async throws -> String {
        if mode == .api {
            guard let profile else { throw llmError(tr("请先在设置中选择 API 配置。")) }
            let key = try LLMKeychain.read(profile)
            return try await RemoteLLMClient.generate(profile: profile, key: key, system: system, prompt: prompt) { _ in }
        }
        guard let engine = engine as? LocalEngine else { throw llmError(tr("本地引擎未启动。")) }
        return try await engine.generate(system: system, prompt: prompt, maxTokens: 300, background: true) { _ in }
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
