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
        guard canGenerateAssistant, let meeting = meetings.first(where: { $0.id == meetingID }) else { return }
        let state: MeetingAssistantState
        if let existing = assistantStates[meetingID] { state = existing }
        else { state = MeetingAssistantState(); assistantStates[meetingID] = state }
        let context = meeting.paragraphs.map { paragraph in
            "[\(formatClock(paragraph.openedAt))] \(paragraph.renderedSource(language: meeting.sourceLanguage))"
        }.joined(separator: "\n")
        guard meeting.paragraphs.contains(where: { !$0.renderedSource(language: meeting.sourceLanguage).isEmpty }) else {
            state.error = tr("这场会议还没有转写内容。")
            return
        }
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
        let earlier = state.answers.map { ChatTurn(question: $0.question, answer: $0.answer, modelName: $0.modelName) }
        let history = ChatHistory.window(earlier, budget: ContextBudget.current(mode: mode, profile: profile), dated: false)
        let task = summary
            ? "Summarize the main ideas, key terms, conclusions and any stated action items. Organize with short headings and cite timestamps."
            : "Answer this question: \(question ?? "")" + (history.text.isEmpty ? "" : "\n\n" + history.text)
        let prompt = "\(task)\n\nMeeting title: \(meeting.title)\n<transcript>\n\(context)\n</transcript>"
        let name = assistantModelName
        state.isGenerating = true
        state.generatingSummary = summary
        state.draft = ""
        state.error = nil
        state.task = Task { [weak self, weak state] in
            guard let self, let state else { return }
            defer { state.isGenerating = false; state.draft = ""; state.task = nil }
            do {
                let text: String
                let show: @MainActor (String) -> Void = { [weak state] partial in state?.draft = partial }
                if mode == .api {
                    guard let profile else { throw llmError(tr("请先在设置中选择 API 配置。")) }
                    let key = try LLMKeychain.read(profile)
                    guard profile.isLoopback || !key.isEmpty else { throw llmError(tr("请输入 API 密钥。")) }
                    text = try await RemoteLLMClient.generate(profile: profile, key: key, system: system, prompt: prompt, onUpdate: show)
                } else {
                    guard let engine = self.engine as? LocalEngine else { throw llmError(tr("本地引擎未启动。")) }
                    await self.waitForMemory()
                    text = try await engine.generate(system: system, prompt: prompt, onUpdate: show)
                }
                if summary { state.summary = text; state.summaryModelName = name }
                else { state.answers.append(.init(question: question ?? "", answer: text, modelName: name)) }
            } catch { state.error = error.localizedDescription }
        }
    }
}
