import Foundation

extension AppModel {
    var assistantIsBusy: Bool {
        chatGeneratingID != nil || assistantStates.values.contains { $0.isGenerating } || (engine as? LocalEngine)?.isGenerating == true
    }

    /// Chat runs during a recording too: API models are remote, and the local engine
    /// gives the chat its own worker at a lower priority than live transcription.
    var canGenerateAssistant: Bool {
        guard !assistantIsBusy,
              localModels.switchingID == nil, localModels.deletingID == nil else { return false }
        if llmConfiguration.mode == .api { return llmConfiguration.activeProfile != nil }
        return engine is LocalEngine && engine.readiness != .preparing
            && LocalModelFiles.isComplete(LocalModelDefinition.selected(for: .assistant))
    }

    var assistantModelName: String {
        if llmConfiguration.mode == .api {
            guard let profile = llmConfiguration.activeProfile else { return tr("未配置 API") }
            return "\(profile.name) · \(profile.modelID)"
        }
        return LocalModelDefinition.selected(for: .assistant).name
    }

    func generateAssistant(for meetingID: UUID, question: String? = nil) {
        guard canGenerateAssistant, let meeting = meetings.first(where: { $0.id == meetingID }).map(current) else { return }
        let state: MeetingAssistantState
        if let existing = assistantStates[meetingID] { state = existing }
        else { state = MeetingAssistantState(record: meeting.assistant); assistantStates[meetingID] = state }
        let lines = meeting.paragraphs.compactMap { paragraph -> String? in
            let text = paragraph.renderedSource(language: meeting.sourceLanguage).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : "[\(formatClock(paragraph.openedAt))] \(text)"
        }
        guard !lines.isEmpty else {
            state.error = tr("这场会议还没有转写内容。")
            return
        }
        let transcriptEnd = meeting.paragraphs.map(\.openedAt).max() ?? 0
        let summary = question == nil
        let language = prompts.modelLanguageName
        let system = ChatContext.composedSystemPrompt(
            override: prompts.systemOverride,
            language: language,
            allowsWeb: false,
            hasPassages: true,
            skills: prompts.skills,
            memory: question.map { memoryPrompt(for: $0) } ?? memoryPrompt(for: meeting.title, kinds: [.style, .preference])
        )
        let mode = llmConfiguration.mode
        let profile = llmConfiguration.activeProfile
        let budget = ContextBudget.current(mode: mode, profile: profile)
        let summaryTask = "Summarize the main ideas, key terms, conclusions and any stated action items. Organize with short headings and cite timestamps."
        // A long lecture is summarized in pieces, then the pieces are combined. A local model
        // reads at most four evenly spaced pieces; an API model up to eight.
        let pieces = summary
            ? TranscriptSelection.chunks(lines, budget: budget.sidePanelTranscript, maxChunks: mode == .local ? 4 : 8)
            : (chunks: [TranscriptSelection.pick(lines, query: question ?? "", budget: budget.sidePanelTranscript)], skipped: false)
        let earlier = state.answers.map { ChatTurn(question: $0.question, answer: $0.answer, modelName: $0.modelName, createdAt: $0.createdAt) }
        let history = ChatHistory.window(earlier, budget: budget, dated: false)
        let name = assistantModelName
        state.isGenerating = true
        state.generatingSummary = summary
        state.draft = ""
        state.error = nil
        state.task = Task { [weak self, weak state] in
            guard let self, let state else { return }
            defer { state.isGenerating = false; state.draft = ""; state.task = nil }
            do {
                let show: @MainActor (String) -> Void = { [weak state] partial in state?.draft = partial }
                if mode == .local {
                    await self.waitForAfterAnswerWork()
                    await self.waitForQuestionWork()
                }
                @MainActor func generate(_ prompt: String, _ onUpdate: @escaping @MainActor (String) -> Void) async throws -> String {
                    if mode == .api {
                        guard let profile else { throw llmError(tr("请先在设置中选择 API 配置。")) }
                        let key = try LLMKeychain.read(profile)
                        guard profile.isLoopback || !key.isEmpty else { throw llmError(tr("请输入 API 密钥。")) }
                        return try await RemoteLLMClient.generate(profile: profile, key: key, system: system, prompt: prompt, onUpdate: onUpdate)
                    }
                    guard let engine = self.engine as? LocalEngine else { throw llmError(tr("本地引擎未启动。")) }
                    return try await engine.generate(system: system, prompt: prompt, onUpdate: onUpdate)
                }
                let text: String
                if summary, pieces.chunks.count > 1 {
                    var partials: [String] = []
                    for (index, chunk) in pieces.chunks.enumerated() {
                        try Task.checkCancellation()
                        state.draft = trf("正在整理第 %d/%d 段…", index + 1, pieces.chunks.count)
                        let part = "This is part \(index + 1) of \(pieces.chunks.count) of one lecture transcript. Summarize this part in at most 800 characters, keeping the timestamps of the main points."
                        partials.append(try await generate("\(part)\n\nMeeting title: \(meeting.title)\n<transcript>\n\(chunk.joined(separator: "\n"))\n</transcript>", { _ in }))
                    }
                    let note = pieces.skipped
                        ? " The parts are evenly spaced samples of a long transcript, not all of it; begin with one line saying so."
                        : ""
                    let combined = partials.enumerated().map { "Part \($0.offset + 1):\n\($0.element)" }.joined(separator: "\n\n")
                    text = try await generate("Combine these partial summaries of one lecture into one summary. \(summaryTask)\(note)\n\nMeeting title: \(meeting.title)\n<partial_summaries>\n\(combined)\n</partial_summaries>", show)
                } else {
                    let transcript = pieces.chunks.first?.joined(separator: "\n") ?? ""
                    let task = summary
                        ? summaryTask
                        : "Answer this question: \(question ?? "")" + (history.text.isEmpty ? "" : "\n\n" + history.text)
                    text = try await generate("\(task)\n\nMeeting title: \(meeting.title)\n<transcript>\n\(transcript)\n</transcript>", show)
                }
                let now = Date()
                if summary {
                    state.summary = text
                    state.summaryModelName = name
                    self.updateAssistantRecord(meetingID) { record in
                        record.summary = text
                        record.summaryModelName = name
                        record.summaryAt = now
                        record.summaryCoversUntil = transcriptEnd
                    }
                } else {
                    let answer = MeetingAssistantAnswer(question: question ?? "", answer: text, modelName: name, createdAt: now)
                    state.answers.append(answer)
                    self.updateAssistantRecord(meetingID) { record in
                        record.append(.init(id: answer.id, question: answer.question, answer: text, modelName: name, createdAt: now))
                    }
                }
            } catch { state.error = error.localizedDescription }
        }
    }

    /// Saves the side panel's result with the meeting; changing `meetings` schedules the save.
    private func updateAssistantRecord(_ meetingID: UUID, _ change: (inout MeetingAssistantRecord) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == meetingID }) else { return }
        var record = meetings[index].assistant ?? MeetingAssistantRecord()
        change(&record)
        meetings[index].assistant = record
    }
}
