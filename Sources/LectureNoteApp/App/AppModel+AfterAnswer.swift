import Foundation

/// Quiet work after an answer: first the chat's running summary, then the memory pass.
/// One job runs at a time, so a local model never runs two background generations, and a
/// question never waits for more than the job that is already generating.
extension AppModel {
    /// One summary pass, prepared when an answer finishes.
    struct SummaryJob {
        var chatID: UUID
        var turns: [ChatTurn]
        var previous: ChatSummary?
        var mode: LLMMode
        var profile: LLMAPIProfile?
        var modelName: String
        var system: String
        var prompt: String
        var limit: Int
    }

    var canRunBackgroundWork: Bool {
        llmConfiguration.mode == .api ? llmConfiguration.activeProfile != nil : engine is LocalEngine
    }

    /// Called when an answer finishes. Work found now runs once the app is quiet; a running
    /// queue picks up anything new after the next answer.
    func scheduleAfterAnswerWork(chatID: UUID?) {
        guard afterAnswerTask == nil else { return }
        let summary = chatID.flatMap { summaryJob(for: $0) }
        let memory = memoryJob()
        guard summary != nil || memory != nil else { return }
        let local = llmConfiguration.mode == .local
        afterAnswerTask = Task { [weak self] in
            // A local model has one chat worker, so the work waits for a quiet moment. A new question cancels the wait.
            if local { try? await Task.sleep(for: .seconds(30)) }
            guard let self else { return }
            defer {
                self.afterAnswerTask = nil
                self.afterAnswerGenerating = false
            }
            if let summary, self.mayStartBackgroundJob(local: local) {
                await self.runSummary(summary)
                self.afterAnswerGenerating = false
            }
            if let memory, self.memoryEnabled, self.mayStartBackgroundJob(local: local) {
                await self.runMemory(memory)
            }
        }
    }

    /// A local question goes first: background work that is waiting is dropped, and a job that is
    /// generating is stopped within about a token. Either way it runs again after a later answer.
    func waitForAfterAnswerWork() async {
        guard let task = afterAnswerTask else { return }
        task.cancel()
        if afterAnswerGenerating {
            await (engine as? LocalEngine)?.cancelBackgroundGeneration()
            await task.value
        }
    }

    /// True for the errors a stopped background reply ends with, which are not failures.
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func mayStartBackgroundJob(local: Bool) -> Bool {
        guard !Task.isCancelled else { return false }
        return !local || (!isChatAnswering && !assistantIsBusy && !questionWorkGenerating)
    }

    /// The summary pass a chat needs now, or nil.
    func summaryJob(for chatID: UUID) -> SummaryJob? {
        guard canRunBackgroundWork, (summaryFailures[chatID] ?? 0) < ChatSummaries.maxFailures,
              let chat = chats.first(where: { $0.id == chatID }) else { return nil }
        let mode = llmConfiguration.mode
        let profile = llmConfiguration.activeProfile
        let budget = ContextBudget.current(mode: mode, profile: profile)
        guard let turns = ChatSummaries.pending(chat.turns, summary: chat.summary, budget: budget) else { return nil }
        let limit = ChatSummaries.limit(for: mode)
        return SummaryJob(
            chatID: chatID,
            turns: turns,
            previous: chat.summary,
            mode: mode,
            profile: profile,
            modelName: assistantModelName,
            system: ChatSummaries.system(language: prompts.modelLanguageName, limit: limit),
            prompt: ChatSummaries.prompt(previous: chat.summary, turns: turns, budget: budget),
            limit: limit
        )
    }

    func runSummary(_ job: SummaryJob) async {
        afterAnswerGenerating = true
        guard let last = job.turns.last else { return }
        let reply: String
        do {
            reply = try await backgroundReply(mode: job.mode, profile: job.profile, system: job.system, prompt: job.prompt, maxTokens: 500)
        } catch {
            if !Self.isCancellation(error) { summaryFailures[job.chatID, default: 0] += 1 }
            return
        }
        guard let text = ChatSummaries.cleaned(reply, limit: job.limit) else {
            summaryFailures[job.chatID, default: 0] += 1
            return
        }
        summaryFailures[job.chatID] = nil
        // The chat may have been deleted, or summarized further by a newer pass, while this one ran.
        guard let index = chats.firstIndex(where: { $0.id == job.chatID }),
              chats[index].summary?.throughTurnID == job.previous?.throughTurnID else { return }
        chats[index].summary = ChatSummary(
            text: text,
            throughTurnID: last.id,
            throughDate: last.createdAt,
            coveredTurns: (job.previous?.coveredTurns ?? 0) + job.turns.count,
            modelName: job.modelName,
            updatedAt: .now
        )
        // Saved without touching updatedAt, so the chat does not jump to the top of history.
        guard chatsReady else { return }
        let message = tr("无法保存对话。")
        ChatStore.saveInBackground(chats[index]) { [weak self] in
            Task { @MainActor in self?.chatError = message }
        }
    }

    /// A short reply from the selected model for background work. Local replies are marked as
    /// background, so they do not make the assistant look busy.
    func backgroundReply(mode: LLMMode, profile: LLMAPIProfile?, system: String, prompt: String, maxTokens: Int) async throws -> String {
        if mode == .api {
            guard let profile else { throw llmError(tr("请先在设置中选择 API 配置。")) }
            let key = try LLMKeychain.read(profile)
            return try await RemoteLLMClient.generate(profile: profile, key: key, system: system, prompt: prompt) { _ in }
        }
        guard let engine = engine as? LocalEngine else { throw llmError(tr("本地引擎未启动。")) }
        return try await engine.generate(system: system, prompt: prompt, maxTokens: maxTokens, background: true) { _ in }
    }
}
