import AppKit
import Foundation

enum WebSearchSupport: Equatable {
    case available, local, unsupported
}

extension AppModel {
    var currentChat: ChatSession? {
        chats.first { $0.id == currentChatID }
    }

    var chatHistory: [ChatSession] {
        chats.filter { !$0.turns.isEmpty }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func chatHistory(anchoredTo meetingID: UUID?) -> [ChatSession] {
        guard let meetingID else { return chatHistory }
        return chatHistory.filter { $0.anchorMeetingID == meetingID }
    }

    func chat(anchoredTo meetingID: UUID?) -> ChatSession? {
        if let meetingID {
            guard let id = meetingChatID[meetingID] else { return nil }
            return chats.first { $0.id == id }
        }
        return currentChat
    }

    var webSearchSupport: WebSearchSupport {
        guard llmConfiguration.mode == .api else { return .local }
        guard let profile = llmConfiguration.activeProfile else { return .unsupported }
        if profile.format == .anthropic { return .available }
        if URL(string: profile.baseURL)?.host == "api.openai.com" { return .available }
        return .unsupported
    }

    func ensureChat() {
        if let current = currentChat, current.anchorMeetingID == nil { return }
        if let existing = chats.first(where: { $0.anchorMeetingID == nil }) {
            currentChatID = existing.id
            return
        }
        let session = ChatSession()
        chats.insert(session, at: 0)
        currentChatID = session.id
    }

    func ensureMeetingChat(_ meetingID: UUID) {
        if let id = meetingChatID[meetingID], chats.contains(where: { $0.id == id && $0.anchorMeetingID == meetingID }) {
            return
        }
        if let existing = chats.first(where: { $0.anchorMeetingID == meetingID }) {
            meetingChatID[meetingID] = existing.id
            return
        }
        let session = ChatSession(anchorMeetingID: meetingID)
        chats.insert(session, at: 0)
        meetingChatID[meetingID] = session.id
    }

    func beginNewChat() {
        beginNewChat(anchor: nil)
    }

    func beginNewChat(anchor: UUID?) {
        if let anchor {
            if let id = meetingChatID[anchor],
               let current = chats.first(where: { $0.id == id }), current.turns.isEmpty {
                chatFocusRequest += 1
                return
            }
            chats.removeAll { $0.anchorMeetingID == anchor && $0.turns.isEmpty && $0.id != chatGeneratingID }
            let session = ChatSession(anchorMeetingID: anchor)
            chats.insert(session, at: 0)
            meetingChatID[anchor] = session.id
            chatError = nil
            chatFocusRequest += 1
            return
        }
        if let current = currentChat, current.anchorMeetingID == nil, current.turns.isEmpty {
            chatFocusRequest += 1
            return
        }
        let scope = (currentChat?.anchorMeetingID == nil ? currentChat?.scope : nil) ?? ChatScope()
        chats.removeAll { $0.anchorMeetingID == nil && $0.turns.isEmpty && $0.id != chatGeneratingID }
        let session = ChatSession(scope: scope)
        chats.insert(session, at: 0)
        currentChatID = session.id
        chatError = nil
        chatFocusRequest += 1
    }

    func openChat(_ id: UUID, forAnchor: UUID? = nil) {
        guard let session = chats.first(where: { $0.id == id }) else { return }
        if let forAnchor, session.anchorMeetingID == forAnchor {
            meetingChatID[forAnchor] = id
        } else {
            currentChatID = id
        }
        chatError = nil
        applyStoredModel(session)
        chatFocusRequest += 1
    }

    func deleteChat(_ id: UUID) {
        guard chatGeneratingID != id else { return }
        let anchor = chats.first { $0.id == id }?.anchorMeetingID
        chats.removeAll { $0.id == id }
        if chatsReady { ChatStore.delete(id) }
        if let anchor, meetingChatID[anchor] == id {
            meetingChatID[anchor] = chats.first { $0.anchorMeetingID == anchor }?.id
        }
        guard currentChatID == id else { return }
        currentChatID = chats.first { $0.anchorMeetingID == nil }?.id
        if let current = chats.first(where: { $0.id == currentChatID }) {
            applyStoredModel(current)
        } else {
            let session = ChatSession()
            chats.insert(session, at: 0)
            currentChatID = session.id
        }
        chatError = nil
    }

    func renameChat(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(id) {
            $0.title = String(trimmed.prefix(80))
            $0.titleCustom = true
        }
    }

    func updateChatScope(_ scope: ChatScope) {
        ensureChat()
        guard let id = currentChatID else { return }
        mutate(id) { $0.scope = scope }
    }

    func setChatWeb(_ enabled: Bool) {
        ensureChat()
        guard let id = currentChatID, webSearchSupport == .available else { return }
        mutate(id) { $0.allowsWeb = enabled }
    }

    func useLocalChatModel() {
        llmConfiguration.setMode(.local)
        ensureChat()
        guard let id = currentChatID else { return }
        mutate(id) {
            $0.modelMode = LLMMode.local.rawValue
            $0.profileID = nil
        }
    }

    var apiModelChoices: [String] {
        guard let profile = llmConfiguration.activeProfile else { return [] }
        var choices = profile.savedModelIDs
        for id in llmConfiguration.listedModels[profile.id] ?? [] where !choices.contains(id) {
            choices.append(id)
        }
        if !profile.modelID.isEmpty, !choices.contains(profile.modelID) {
            choices.insert(profile.modelID, at: 0)
        }
        return choices
    }

    func refreshActiveAPIModels() async {
        guard llmConfiguration.mode == .api, let profile = llmConfiguration.activeProfile else { return }
        let key = (try? LLMKeychain.read(profile)) ?? ""
        guard profile.isLoopback || !key.isEmpty else { return }
        guard let models = try? await RemoteLLMClient.models(profile: profile, key: key), !models.isEmpty else { return }
        llmConfiguration.setListedModels(models, for: profile.id)
    }

    func useAPIModel(_ modelID: String) {
        llmConfiguration.selectModel(modelID)
        ensureChat()
        guard let id = currentChatID else { return }
        mutate(id) {
            $0.modelMode = LLMMode.api.rawValue
            $0.profileID = llmConfiguration.activeID
        }
    }

    func useChatProfile(_ id: UUID) {
        guard llmConfiguration.profiles.contains(where: { $0.id == id }) else { return }
        llmConfiguration.setMode(.api)
        llmConfiguration.activate(id)
        ensureChat()
        guard let chatID = currentChatID else { return }
        mutate(chatID) {
            $0.modelMode = LLMMode.api.rawValue
            $0.profileID = id
        }
    }

    func citationIsOpenable(_ citation: ChatCitation) -> Bool {
        if let id = citation.meetingID { return meetings.contains { $0.id == id } }
        if let id = citation.sourceID { return sources.contains { $0.id == id } }
        return citation.url != nil
    }

    func openCitation(_ citation: ChatCitation) {
        if let id = citation.meetingID, meetings.contains(where: { $0.id == id }) {
            openMeeting(id)
            return
        }
        if let id = citation.sourceID, let source = sources.first(where: { $0.id == id }) {
            NSWorkspace.shared.open(SourceStore.fileURL(for: source))
            return
        }
        if let raw = citation.url, let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    func ask(_ question: String, anchor: UUID? = nil) -> Bool {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return false }
        if let anchor { ensureMeetingChat(anchor) } else { ensureChat() }
        let resolvedID = anchor.flatMap { meetingChatID[$0] } ?? currentChatID
        guard chatGeneratingID == nil, canGenerateAssistant, let id = resolvedID,
              let session = chats.first(where: { $0.id == id }) else {
            chatError = tr("现在不能提问。")
            return false
        }
        let boundMeeting = anchor ?? session.anchorMeetingID
        let meetingItems = chatMeetingItems()
        let sourceItems = chatSourceItems()
        let chosenMeetings: Set<UUID>
        let chosenSources: Set<UUID>
        let hasScope: Bool
        if let boundMeeting {
            chosenMeetings = [boundMeeting]
            chosenSources = Set(meetingLinks[boundMeeting] ?? [])
            let meeting = meetings.first { $0.id == boundMeeting }
            let hasText = meeting?.paragraphs.contains {
                !$0.renderedSource(language: meeting?.sourceLanguage ?? "zh").isEmpty
            } ?? false
            hasScope = hasText || !chosenSources.isEmpty
        } else {
            chosenMeetings = session.scope.selectedMeetings(meetingItems)
            chosenSources = session.scope.selectedSources(sourceItems)
            hasScope = !chosenMeetings.isEmpty || !chosenSources.isEmpty
        }
        chatError = nil
        let allowsWeb = session.allowsWeb && webSearchSupport == .available
        let mode = llmConfiguration.mode
        let profile = llmConfiguration.activeProfile
        let name = assistantModelName
        let language = prompts.modelLanguageName
        let history = session.turns
        let pickedMeetings = meetings.filter { chosenMeetings.contains($0.id) }
        let pickedSources = sources.filter { chosenSources.contains($0.id) }
        mutate(id) {
            $0.modelMode = mode.rawValue
            $0.profileID = mode == .api ? profile?.id : nil
        }
        pendingQuestion = question
        chatGeneratingID = id
        chatTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.chatGeneratingID == id {
                    self.chatGeneratingID = nil
                    self.pendingQuestion = nil
                    self.chatTask = nil
                }
            }
            do {
                let packed = ChatContext.pack(await self.passageBlocks(meetings: pickedMeetings, sources: pickedSources), question: question)
                if hasScope && packed.isEmpty { throw llmError(tr("所选范围里还没有可以阅读的文字。")) }
                try Task.checkCancellation()
                let text: String
                let system = ChatContext.composedSystemPrompt(
                    override: self.prompts.systemOverride,
                    language: language,
                    allowsWeb: allowsWeb,
                    hasPassages: !packed.isEmpty,
                    skills: self.prompts.skills
                )
                let prompt = ChatContext.userPrompt(question: question, history: history, blocks: packed)
                if mode == .api {
                    guard let profile else { throw llmError(tr("请先在设置中选择 API 配置。")) }
                    let key = try LLMKeychain.read(profile)
                    guard profile.isLoopback || !key.isEmpty else { throw llmError(tr("请输入 API 密钥。")) }
                    text = try await RemoteLLMClient.generate(
                        profile: profile,
                        key: key,
                        system: system,
                        prompt: prompt,
                        allowsWeb: allowsWeb
                    )
                } else {
                    guard let engine = self.engine as? LocalEngine else { throw llmError(tr("本地引擎未启动。")) }
                    text = try await engine.generate(system: system, prompt: prompt)
                }
                try Task.checkCancellation()
                self.finishChat(id, question: question, answer: text, modelName: name, citations: ChatContext.citations(in: text, blocks: packed), error: nil)
            } catch is CancellationError {
                if self.currentChatID == id { self.chatDraftRestore = question }
            } catch let error as URLError where error.code == .cancelled {
                if self.currentChatID == id { self.chatDraftRestore = question }
            } catch {
                if Task.isCancelled {
                    if self.currentChatID == id { self.chatDraftRestore = question }
                } else {
                    self.finishChat(id, question: question, answer: "", modelName: name, citations: [], error: error.localizedDescription)
                }
            }
        }
        return true
    }

    func stopChat() {
        chatTask?.cancel()
    }

    func chatMeetingItems() -> [ScopeItem] {
        meetings.map { ScopeItem(id: $0.id, categoryID: $0.categoryID, live: $0.isLive) }
    }

    func chatSourceItems() -> [ScopeItem] {
        sources.map { ScopeItem(id: $0.id, categoryID: $0.categoryID) }
    }

    func chatCategoryNames() -> [ScopeCategoryName] {
        var rows = categories.sorted { $0.sortOrder < $1.sortOrder }.map { ScopeCategoryName(id: $0.id, name: $0.name) }
        rows.append(ScopeCategoryName(id: nil, name: tr("未分类")))
        return rows
    }

    private func applyStoredModel(_ session: ChatSession) {
        guard let raw = session.modelMode, let mode = LLMMode(rawValue: raw) else { return }
        if mode == .local {
            llmConfiguration.setMode(.local)
            return
        }
        guard let id = session.profileID, llmConfiguration.profiles.contains(where: { $0.id == id }) else { return }
        llmConfiguration.setMode(.api)
        llmConfiguration.activate(id)
    }

    private func mutate(_ id: UUID, _ body: (inout ChatSession) -> Void) {
        guard let index = chats.firstIndex(where: { $0.id == id }) else { return }
        body(&chats[index])
        chats[index].updatedAt = .now
        guard chatsReady, !chats[index].turns.isEmpty else { return }
        do { try ChatStore.save(chats[index]) }
        catch { chatError = tr("无法保存对话。") }
    }

    private func finishChat(_ id: UUID, question: String, answer: String, modelName: String, citations: [ChatCitation], error: String?) {
        guard chats.contains(where: { $0.id == id }) else { return }
        mutate(id) { session in
            if !session.titleCustom && session.title.isEmpty {
                session.title = String(question.prefix(20))
            }
            session.turns.append(ChatTurn(
                question: question,
                answer: answer,
                modelName: modelName,
                citations: citations,
                error: error
            ))
        }
        pendingQuestion = nil
    }

    private func passageBlocks(meetings: [Meeting], sources: [KnowledgeSource]) async -> [ContextBlock] {
        var blocks: [ContextBlock] = []
        for meeting in meetings {
            for paragraph in meeting.paragraphs {
                let text = paragraph.renderedSource(language: meeting.sourceLanguage)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                blocks.append(ContextBlock(
                    title: meeting.title,
                    detail: formatClock(paragraph.openedAt),
                    body: text,
                    meetingID: meeting.id
                ))
            }
        }
        for source in sources {
            let url = SourceStore.fileURL(for: source)
            let title = source.title
            let sourceID = source.id
            let extracted = await Task.detached(priority: .userInitiated) {
                SourceText.blocks(url: url, title: title, sourceID: sourceID)
            }.value
            blocks.append(contentsOf: extracted)
        }
        return blocks
    }
}
