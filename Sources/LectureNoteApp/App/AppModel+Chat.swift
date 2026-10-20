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
            clearQueue(id)
        }
        let anchor = chats.first { $0.id == id }?.anchorMeetingID
        chats.removeAll { $0.id == id }
        if chatsReady { ChatStore.deleteInBackground(id) }
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
        if let id = citation.chatID, let chat = chats.first(where: { $0.id == id }) {
            showCitedChat(chat)
            return
        }
        if let raw = citation.url, let url = URL(string: raw) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Shows an earlier chat: a meeting's chat inside that meeting, any other chat on the Ask page.
    private func showCitedChat(_ chat: ChatSession) {
        if let meetingID = chat.anchorMeetingID, meetings.contains(where: { $0.id == meetingID }) {
            openChat(chat.id, forAnchor: meetingID)
            openMeeting(meetingID)
        } else {
            openChat(chat.id)
            page = .ask
        }
    }

    @discardableResult
    /// `chatID` sends into that chat directly, such as a queued message for a chat that is not on screen.
    /// `steered` marks a message that interrupted the previous answer, so the model is told.
    func ask(_ question: String, images: [ChatImageDraft] = [], anchor: UUID? = nil, chatID: UUID? = nil, steered: Bool = false) -> Bool {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty || !images.isEmpty else { return false }
        if chatID == nil {
            if let anchor { ensureMeetingChat(anchor) } else { ensureChat() }
        }
        let resolvedID = chatID ?? anchor.flatMap { meetingChatID[$0] } ?? currentChatID
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
        let remembered = memoryPrompt(for: question)
        let history = session.turns
        let chatSummary = session.summary
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
                let contextBudget = ContextBudget.current(mode: mode, profile: profile)
                let packed = ChatContext.pack(
                    await self.passageBlocks(meetings: pickedMeetings, sources: pickedSources, summaryAbove: contextBudget.scope),
                    question: question,
                    budget: contextBudget.scope
                )
                if hasScope && packed.isEmpty { throw llmError(tr("所选范围里还没有可以阅读的文字。")) }
                try Task.checkCancellation()
                let seesImages = ChatImages.seesImages(mode: mode, modelID: profile?.modelID ?? "")
                let imagePlan = ChatContext.attachedImages(history: history, currentCount: images.count)
                let promptImages = seesImages ? self.promptImages(current: images, history: imagePlan.history) : []
                let historyWindow = ChatHistory.window(
                    history,
                    budget: contextBudget,
                    summary: chatSummary,
                    omittedImageTurns: seesImages ? imagePlan.omittedTurnIDs : []
                )
                var blocks = packed
                var answer = ""
                var briefs: [String] = []
                var webNotice: String?
                var searched = false
                var prefetched = false
                var webReachable = allowsWeb
                // The rest of the student's material, searched when the question needs it.
                var library: ChatContext.LibraryTool = self.hasLibrary ? .available : .off
                var libraryDocuments: [LibraryDocument]?
                let excluded = LibraryExclusions(
                    turns: historyWindow.includedTurns,
                    meetings: chosenMeetings,
                    sources: chosenSources
                )
                func searchLibrary(_ request: LibraryRequest) async -> [ContextBlock] {
                    if libraryDocuments == nil { libraryDocuments = await self.libraryDocuments(excluding: excluded) }
                    let documents = libraryDocuments ?? []
                    let budget = contextBudget.library
                    return await Task.detached(priority: .userInitiated) { LibrarySearch.run(request, in: documents, budget: budget) }.value
                }
                // A question about last week, an earlier chat, or what the teacher said gets searched before the first answer.
                if library == .available, LibraryRequest.referencesPast(question) {
                    let found = await searchLibrary(LibraryRequest(query: question, range: LibraryDates.range(in: question)))
                    try Task.checkCancellation()
                    if !found.isEmpty {
                        blocks.append(contentsOf: found)
                        library = .prefetched
                    }
                }
                // With Web on, search the question itself first so a search happens even when the model would skip it.
                if allowsWeb, let query = ChatContext.searchQuery(question: question, history: history) {
                    let found = try await self.searchPasses([query][...])
                    if found.blocks.isEmpty {
                        if let notice = found.notice {
                            webNotice = notice
                            webReachable = false
                        }
                    } else {
                        blocks.append(contentsOf: found.blocks)
                        prefetched = true
                    }
                }
                for round in 0..<3 {
                    let webTool: ChatContext.WebTool
                    if !webReachable { webTool = .off }
                    else if searched { webTool = .used }
                    else { webTool = prefetched ? .prefetched : .available }
                    let system = ChatContext.composedSystemPrompt(
                        override: self.prompts.systemOverride,
                        language: language,
                        allowsWeb: blocks.count > packed.count,
                        hasPassages: !blocks.isEmpty,
                        skills: self.prompts.skills,
                        tools: true,
                        webTool: webTool,
                        library: library,
                        memory: remembered
                    )
                    let libraryOpen = library == .available || library == .prefetched
                    let mayStillSearch = (webReachable && !searched) || libraryOpen
                    var prompt = ChatContext.userPrompt(
                        question: question,
                        history: historyWindow,
                        blocks: blocks,
                        mentionsOlderImages: seesImages && imagePlan.mentionsOlderImages,
                        mentionsLibrary: libraryOpen,
                        steered: steered
                    )
                    if round > 0 {
                        let draft = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                        if draft.isEmpty {
                            prompt += "\n\nThe lookup finished and its results are in the numbered passages. Answer the question in Markdown."
                        } else {
                            prompt += "\n\nDraft already shown to the user:\n\(draft)\n\nContinue from here. Do not repeat the draft."
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
                        let shown = ChatTools.parse(ChatContext.streamingDisplay(partial), streaming: true, stopAtSearch: mayStillSearch).visible
                        let combined = self?.joinedAnswer(carried, shown) ?? shown
                        self?.pendingAnswer = combined
                        self?.pendingCitations = ChatContext.citations(in: combined, blocks: cited)
                    }
                    try Task.checkCancellation()
                    let parsed = ChatTools.parse(ChatContext.splitVisual(text, streaming: false).text, streaming: false, stopAtSearch: mayStillSearch)
                    answer = joinedAnswer(answer, parsed.visible)
                    briefs.append(contentsOf: parsed.calls.filter { $0.name == ChatTools.createDemo }.map(\.body))
                    let queries = parsed.calls.filter { $0.name == ChatTools.webSearch }.map(\.body)
                    let libraryCalls = parsed.calls.filter { $0.name == ChatTools.searchLibrary }.map(\.body)
                    var looked = false
                    if libraryOpen, let call = libraryCalls.first {
                        looked = true
                        library = .used
                        blocks.append(contentsOf: await searchLibrary(LibraryRequest.parse(call)))
                        try Task.checkCancellation()
                    }
                    if webReachable, !searched, !queries.isEmpty {
                        looked = true
                        searched = true
                        let found = try await self.searchPasses(queries.prefix(2))
                        if found.blocks.isEmpty {
                            if !prefetched {
                                webNotice = found.notice ?? tr("联网搜索没有返回结果，这次只根据会议和资料回答。")
                            }
                        } else {
                            blocks.append(contentsOf: found.blocks)
                        }
                    }
                    guard looked else { break }
                }
                let stored = self.storedImages(images)
                let turnID = self.finishChat(id, question: question, answer: answer, modelName: name, citations: ChatContext.citations(in: answer, blocks: blocks), error: nil, images: stored)
                self.pendingAnswer = ""
                self.pendingCitations = []
                if let webNotice { self.chatError = webNotice }
                self.scheduleAfterAnswerWork(chatID: id)
                // One demo per answer: the last brief has seen the search results. Without a brief, API models still get a demo when the answer is substantial.
                // Local models skip that fallback because a demo there blocks the next question until it finishes.
                let skipsDemo = ChatContext.skipsDemo(question, usedLibrary: library != .available && library != .off)
                let brief = skipsDemo ? nil : briefs.last { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                let fallback = !skipsDemo && brief == nil && mode == .api && ChatContext.wantsFallbackVisual(question: question, answer: answer)
                // A local demo would hold the only worker while queued messages wait.
                let queueWaiting = mode == .local && self.chatQueue.contains { !self.queuePaused.contains($0.chatID) }
                if let turnID, brief != nil || fallback, !queueWaiting {
                    self.startVisual(
                        chatID: id,
                        turnID: turnID,
                        brief: brief,
                        question: question,
                        answer: answer,
                        mode: mode,
                        profile: profile,
                        language: language
                    )
                }
                self.chatDidEnd(id, succeeded: true)
            } catch is CancellationError {
                self.chatWasStopped(id, question: question, images: images, modelName: name)
            } catch let error as URLError where error.code == .cancelled {
                self.chatWasStopped(id, question: question, images: images, modelName: name)
            } catch {
                if Task.isCancelled {
                    self.chatWasStopped(id, question: question, images: images, modelName: name)
                } else {
                    _ = self.finishChat(id, question: question, answer: "", modelName: name, citations: [], error: error.localizedDescription, images: self.storedImages(images))
                    self.chatDidEnd(id, succeeded: false)
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

    func searchPasses(_ queries: ArraySlice<String>) async throws -> (blocks: [ContextBlock], notice: String?) {
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
        localMaxTokens: Int = 2048,
        onUpdate: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        if mode == .api {
            guard let profile else { throw llmError(tr("请先在设置中选择 API 配置。")) }
            let key = try LLMKeychain.read(profile)
            guard profile.isLoopback || !key.isEmpty else { throw llmError(tr("请输入 API 密钥。")) }
            return try await RemoteLLMClient.generate(profile: profile, key: key, system: system, prompt: prompt, images: images, onUpdate: onUpdate)
        }
        guard let engine = self.engine as? LocalEngine else { throw llmError(tr("本地引擎未启动。")) }
        await waitForAfterAnswerWork()
        await waitForQuestionWork()
        return try await engine.generate(system: system, prompt: prompt, maxTokens: localMaxTokens, onUpdate: onUpdate)
    }

    private func startVisual(
        chatID: UUID,
        turnID: UUID,
        brief: String?,
        question: String,
        answer: String,
        mode: LLMMode,
        profile: LLMAPIProfile?,
        language: String
    ) {
        let requested = brief != nil
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
                let system = ChatContext.visualSystemPrompt(language: language)
                var prompt = ChatContext.visualUserPrompt(brief: brief, question: question, answer: answer)
                // API models get one repair attempt. A local retry would block the next question for another full run.
                let attempts = mode == .api ? 2 : 1
                for attempt in 0..<attempts {
                    try Task.checkCancellation()
                    let visual = try await self.completeChat(
                        mode: mode,
                        profile: profile,
                        system: system,
                        prompt: prompt,
                        localMaxTokens: 4096
                    ) { _ in }
                    try Task.checkCancellation()
                    if visual.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "NONE" { return }
                    if let fence = ChatContext.htmlFence(from: visual), ChatContext.rendersWidget(fence) {
                        self.appendVisual(chatID, turnID: turnID, fence: fence)
                        return
                    }
                    if attempt == 0 { prompt = ChatContext.visualRetryPrompt(prompt) }
                }
                if requested { self.chatError = tr("这次没能生成图示。") }
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

    /// Adds a finished turn to a meeting's chat, such as a Q&A answer the student wants to follow up on.
    func appendTurnToMeetingChat(_ meetingID: UUID, turn: ChatTurn) {
        ensureMeetingChat(meetingID)
        guard let id = meetingChatID[meetingID] else { return }
        mutate(id) { $0.turns.append(turn) }
    }

    private func mutate(_ id: UUID, _ body: (inout ChatSession) -> Void) {
        guard let index = chats.firstIndex(where: { $0.id == id }) else { return }
        body(&chats[index])
        chats[index].updatedAt = .now
        guard chatsReady, !chats[index].turns.isEmpty else { return }
        let snapshot = chats[index]
        let message = tr("无法保存对话。")
        ChatStore.saveInBackground(snapshot) { [weak self] in
            Task { @MainActor in self?.chatError = message }
        }
    }

    @discardableResult
    /// A stopped answer. Stop puts the question back in the composer and pauses the queue; a steer
    /// keeps what was shown as an interrupted turn and sends the new message once this task ends.
    private func chatWasStopped(_ id: UUID, question: String, images: [ChatImageDraft], modelName: String) {
        guard let steer = pendingSteer, steer.chatID == id else {
            restoreDraft(id, question: question, images: images)
            chatDidEnd(id, succeeded: false)
            return
        }
        pendingSteer = nil
        let shown = pendingAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing shown yet: the question is simply replaced, unless it carried images worth keeping.
        if !shown.isEmpty || !images.isEmpty {
            let turnID = finishChat(id, question: question, answer: shown, modelName: modelName, citations: pendingCitations, error: nil, images: storedImages(images))
            if let turnID, let chatIndex = chats.firstIndex(where: { $0.id == id }),
               let turnIndex = chats[chatIndex].turns.firstIndex(where: { $0.id == turnID }) {
                chats[chatIndex].turns[turnIndex].interrupted = true
                if chatsReady {
                    let message = tr("无法保存对话。")
                    ChatStore.saveInBackground(chats[chatIndex]) { [weak self] in
                        Task { @MainActor in self?.chatError = message }
                    }
                }
            }
        } else {
            images.forEach(ChatImages.discard)
        }
        // Runs after this answer's task has cleared `chatGeneratingID`.
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.ask(steer.text, images: steer.images, chatID: id, steered: true) {
                self.chatQueue.insert(steer, at: 0)
                self.queuePaused.insert(id)
            }
        }
    }

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

    /// Whether there is anything besides the current chat that a library search could find.
    var hasLibrary: Bool {
        !sources.isEmpty || meetings.contains { !$0.paragraphs.isEmpty } || chats.contains { $0.turns.count > 0 && $0.id != chatGeneratingID }
    }

    /// The student's recorded lectures, earlier chats and imported files, minus what this question already includes.
    private func libraryDocuments(excluding excluded: LibraryExclusions) async -> [LibraryDocument] {
        var documents: [LibraryDocument] = []
        for meeting in meetings where !excluded.meetings.contains(meeting.id) {
            let language = meeting.sourceLanguage
            documents += LibrarySearch.meetingDocuments(
                id: meeting.id,
                title: meeting.title,
                startedAt: meeting.startedAt,
                paragraphs: meeting.paragraphs.map {
                    ($0.openedAt, $0.renderedSource(language: language), $0.renderedTranslation(language: meeting.targetLanguage))
                },
                summary: meeting.assistant?.summary
            )
        }
        for chat in chats {
            let turns = chat.turns.filter { !excluded.turns.contains($0.id) }
            documents += LibrarySearch.chatDocuments(id: chat.id, title: chat.displayTitle, turns: turns, summary: chat.summary)
        }
        let files = sources.filter { !excluded.sources.contains($0.id) }
        await SourceTextCache.shared.keep(only: Set(sources.map(\.id)))
        for source in files {
            documents += LibrarySearch.sourceDocuments(source, blocks: await SourceTextCache.shared.blocks(for: source))
        }
        return documents
    }

    /// A meeting longer than `summaryAbove` characters also contributes its saved summary,
    /// pinned ahead of its paragraphs, so the model sees the whole lecture's outline.
    func passageBlocks(meetings: [Meeting], sources: [KnowledgeSource], summaryAbove: Int = .max) async -> [ContextBlock] {
        var blocks: [ContextBlock] = []
        for meeting in meetings {
            let length = meeting.paragraphs.reduce(0) { $0 + $1.renderedSource(language: meeting.sourceLanguage).count }
            if length > summaryAbove, let summary = meeting.assistant?.summary, !summary.isEmpty {
                blocks.append(ContextBlock(title: meeting.title, detail: tr("会议摘要"), body: summary, meetingID: meeting.id, pinned: true))
            }
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
