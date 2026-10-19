import AppKit
import Foundation

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
            let removing = chats.filter { $0.anchorMeetingID == anchor && $0.turns.isEmpty && $0.id != chatGeneratingID }.map(\.id)
            discardComposerImages(removing)
            chats.removeAll { removing.contains($0.id) }
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
        let removing = chats.filter { $0.anchorMeetingID == nil && $0.turns.isEmpty && $0.id != chatGeneratingID }.map(\.id)
        discardComposerImages(removing)
        chats.removeAll { removing.contains($0.id) }
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
        if let session = chats.first(where: { $0.id == id }) {
            for turn in session.turns {
                visualTasks[turn.id]?.cancel()
                visualTasks[turn.id] = nil
                preparingVisualTurnIDs.remove(turn.id)
            }
            ChatImages.delete(session.turns.flatMap(\.images))
            discardComposerImages([id])
        }
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

    func setChatWeb(_ enabled: Bool, anchor: UUID? = nil) {
        if let anchor { ensureMeetingChat(anchor) } else { ensureChat() }
        guard webSearch.isActiveReady else { return }
        let id = anchor.flatMap { meetingChatID[$0] } ?? currentChatID
        guard let id else { return }
        mutate(id) { $0.allowsWeb = enabled }
    }

    func removeSearch(_ vendor: SearchVendor) throws {
        guard try webSearch.delete(vendor) else { return }
        for chat in chats where chat.allowsWeb {
            mutate(chat.id) { $0.allowsWeb = false }
        }
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
    func ask(_ question: String, images: [ChatImageDraft] = [], anchor: UUID? = nil) -> Bool {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty || !images.isEmpty else { return false }
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
        let allowsWeb = session.allowsWeb && webSearch.isActiveReady
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
        pendingImageDrafts = images
        pendingAnswer = ""
        chatGeneratingID = id
        chatTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.chatGeneratingID == id {
                    self.chatGeneratingID = nil
                    self.pendingQuestion = nil
                    self.pendingAnswer = ""
                    self.pendingCitations = []
                    self.pendingImageDrafts = []
                    self.chatTask = nil
                }
            }
            do {
                let packed = ChatContext.pack(await self.passageBlocks(meetings: pickedMeetings, sources: pickedSources), question: question)
                if hasScope && packed.isEmpty { throw llmError(tr("所选范围里还没有可以阅读的文字。")) }
                try Task.checkCancellation()
                let seesImages = ChatImages.seesImages(mode: mode, modelID: profile?.modelID ?? "")
                let imagePlan = ChatContext.attachedImages(history: history, currentCount: images.count)
                let promptImages = seesImages ? self.promptImages(current: images, history: imagePlan.history) : []
                var blocks = packed
                var answer = ""
                var briefs: [String] = []
                var webNotice: String?
                var searched = false
                for round in 0..<2 {
                    let system = ChatContext.composedSystemPrompt(
                        override: self.prompts.systemOverride,
                        language: language,
                        allowsWeb: blocks.count > packed.count,
                        hasPassages: !blocks.isEmpty,
                        skills: self.prompts.skills,
                        tools: true,
                        webTool: allowsWeb ? (searched ? .used : .available) : .off
                    )
                    var prompt = ChatContext.userPrompt(
                        question: question,
                        history: history,
                        blocks: blocks,
                        omittedImageTurns: seesImages ? imagePlan.omittedTurnIDs : [],
                        mentionsOlderImages: seesImages && imagePlan.mentionsOlderImages
                    )
                    if round > 0 {
                        let draft = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                        if draft.isEmpty {
                            prompt += "\n\nThe web search tool finished. Answer the question in Markdown. Do not call web_search again."
                        } else {
                            prompt += "\n\nDraft already shown to the user:\n\(draft)\n\nContinue from here. Do not repeat the draft or call web_search again."
                        }
                        if webNotice != nil, blocks.count == packed.count {
                            prompt += "\n\nThe search returned nothing. Answer from the material you already have."
                        }
                    }
                    let carried = answer
                    let cited = blocks
                    let text = try await self.completeChat(
                        mode: mode,
                        profile: profile,
                        system: system,
                        prompt: prompt,
                        images: promptImages
                    ) { [weak self] partial in
                        let shown = ChatTools.parse(ChatContext.streamingDisplay(partial), streaming: true).visible
                        let combined = self?.joinedAnswer(carried, shown) ?? shown
                        self?.pendingAnswer = combined
                        self?.pendingCitations = ChatContext.citations(in: combined, blocks: cited)
                    }
                    try Task.checkCancellation()
                    let parsed = ChatTools.parse(ChatContext.splitVisual(text, streaming: false).text, streaming: false)
                    answer = joinedAnswer(answer, parsed.visible)
                    briefs.append(contentsOf: parsed.calls.filter { $0.name == ChatTools.createDemo }.map(\.body))
                    let queries = parsed.calls.filter { $0.name == ChatTools.webSearch }.map(\.body)
                    guard allowsWeb, !searched, !queries.isEmpty else { break }
                    searched = true
                    let found = try await self.searchPasses(queries.prefix(2))
                    if found.blocks.isEmpty {
                        webNotice = found.notice ?? tr("联网搜索没有返回结果，这次只根据会议和资料回答。")
                    } else {
                        blocks.append(contentsOf: found.blocks)
                    }
                }
                let stored = self.storedImages(images)
                let turnID = self.finishChat(id, question: question, answer: answer, modelName: name, citations: ChatContext.citations(in: answer, blocks: blocks), error: nil, images: stored)
                self.pendingAnswer = ""
                self.pendingCitations = []
                if let webNotice { self.chatError = webNotice }
                if let turnID, !briefs.isEmpty {
                    self.startVisual(
                        chatID: id,
                        turnID: turnID,
                        briefs: briefs,
                        mode: mode,
                        profile: profile,
                        language: language
                    )
                }
            } catch is CancellationError {
                self.restoreDraft(id, question: question, images: images)
            } catch let error as URLError where error.code == .cancelled {
                self.restoreDraft(id, question: question, images: images)
            } catch {
                if Task.isCancelled {
                    self.restoreDraft(id, question: question, images: images)
                } else {
                    self.finishChat(id, question: question, answer: "", modelName: name, citations: [], error: error.localizedDescription, images: self.storedImages(images))
                }
            }
        }
        return true
    }

    func stopChat() {
        chatTask?.cancel()
    }

    private func joinedAnswer(_ current: String, _ next: String) -> String {
        let piece = next.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !piece.isEmpty else { return current }
        let base = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return piece }
        return base + "\n\n" + piece
    }

    private func searchPasses(_ queries: ArraySlice<String>) async throws -> (blocks: [ContextBlock], notice: String?) {
        var blocks: [ContextBlock] = []
        var notice: String?
        for query in queries {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            do {
                let hits = try await webSearch.lookup(String(text.prefix(300)))
                try Task.checkCancellation()
                blocks.append(contentsOf: hits.map { $0.contextBlock() })
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch {
                if Task.isCancelled { throw CancellationError() }
                notice = error.localizedDescription
            }
        }
        return (blocks, notice)
    }

    private func completeChat(
        mode: LLMMode,
        profile: LLMAPIProfile?,
        system: String,
        prompt: String,
        images: [ModelImage] = [],
        onUpdate: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        if mode == .api {
            guard let profile else { throw llmError(tr("请先在设置中选择 API 配置。")) }
            let key = try LLMKeychain.read(profile)
            guard profile.isLoopback || !key.isEmpty else { throw llmError(tr("请输入 API 密钥。")) }
            return try await RemoteLLMClient.generate(profile: profile, key: key, system: system, prompt: prompt, images: images, onUpdate: onUpdate)
        }
        guard let engine = self.engine as? LocalEngine else { throw llmError(tr("本地引擎未启动。")) }
        return try await engine.generate(system: system, prompt: prompt, onUpdate: onUpdate)
    }

    private func startVisual(
        chatID: UUID,
        turnID: UUID,
        briefs: [String],
        mode: LLMMode,
        profile: LLMAPIProfile?,
        language: String
    ) {
        let briefs = briefs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !briefs.isEmpty else { return }
        preparingVisualTurnIDs.insert(turnID)
        visualTasks[turnID] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.preparingVisualTurnIDs.remove(turnID)
                self.visualTasks[turnID] = nil
                if mode == .local { self.localVisualBusy = false }
            }
            do {
                if mode == .local {
                    while self.chatGeneratingID != nil || self.localVisualBusy || (self.engine as? LocalEngine)?.isGenerating == true {
                        try await Task.sleep(for: .milliseconds(200))
                    }
                    self.localVisualBusy = true
                }
                for brief in briefs {
                    try Task.checkCancellation()
                    let visual = try await self.completeChat(
                        mode: mode,
                        profile: profile,
                        system: ChatContext.visualSystemPrompt(language: language),
                        prompt: ChatContext.visualUserPrompt(brief: brief)
                    ) { _ in }
                    try Task.checkCancellation()
                    if let fence = ChatContext.htmlFence(from: visual) {
                        self.appendVisual(chatID, turnID: turnID, fence: fence)
                    }
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                if !Task.isCancelled { self.chatError = error.localizedDescription }
            }
        }
    }

    private func appendVisual(_ chatID: UUID, turnID: UUID, fence: String) {
        mutate(chatID) { session in
            guard let index = session.turns.firstIndex(where: { $0.id == turnID }) else { return }
            guard !session.turns[index].answer.contains(fence) else { return }
            session.turns[index].answer += "\n\n" + fence
        }
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

    @discardableResult
    private func finishChat(_ id: UUID, question: String, answer: String, modelName: String, citations: [ChatCitation], error: String?, images: [ChatImage] = []) -> UUID? {
        guard chats.contains(where: { $0.id == id }) else { return nil }
        let turn = ChatTurn(
            question: question,
            answer: answer,
            modelName: modelName,
            citations: citations,
            error: error,
            images: images
        )
        mutate(id) { session in
            if !session.titleCustom && session.title.isEmpty {
                let source = question.isEmpty ? (images.first?.name ?? "") : question
                session.title = String(source.prefix(20))
            }
            session.turns.append(turn)
        }
        pendingQuestion = nil
        pendingImageDrafts = []
        return turn.id
    }

    private func storedImages(_ drafts: [ChatImageDraft]) -> [ChatImage] {
        drafts.compactMap { ChatImages.promote($0) }
    }

    private func promptImages(current: [ChatImageDraft], history: [ChatImage]) -> [ModelImage] {
        var images: [ModelImage] = []
        for draft in current.prefix(ChatImages.countLimit) {
            if let payload = ChatImages.payload(url: draft.fileURL, mime: draft.mime) {
                images.append(payload)
            }
        }
        for image in history where images.count < ChatImages.countLimit {
            if let payload = ChatImages.payload(url: image.fileURL(), mime: image.mime) {
                images.append(payload)
            }
        }
        return images
    }

    private func restoreDraft(_ id: UUID, question: String, images: [ChatImageDraft]) {
        composerImages[id] = images
        let showing = currentChatID == id || meetingChatID.values.contains(id)
        if showing { chatDraftRestore = question }
    }

    private func discardComposerImages(_ ids: [UUID]) {
        for id in ids {
            for draft in composerImages[id] ?? [] {
                ChatImages.discard(draft)
            }
            composerImages[id] = nil
        }
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
