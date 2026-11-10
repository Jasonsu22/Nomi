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
            let removing = chats.filter { $0.anchorMeetingID == anchor && $0.turns.isEmpty && chatRuns[$0.id] == nil }.map(\.id)
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
        let removing = chats.filter { $0.anchorMeetingID == nil && $0.turns.isEmpty && chatRuns[$0.id] == nil }.map(\.id)
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
        guard chatRuns[id] == nil else { return }
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
        let key = (try? LLMKeys.read(profile)) ?? ""
        guard profile.isLoopback || !key.isEmpty else { return }
        guard let models = try? await RemoteLLMClient.models(profile: profile, key: key), !models.isEmpty else { return }
        llmConfiguration.setListedModels(models, for: profile.id)
    }

    func useAPIModel(_ modelID: String) {
        llmConfiguration.setMode(.api)
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
            if CitationKind.of(citation) == .summary {
                detailTabRequest = DetailTabRequest(meetingID: id, tab: .summary)
            } else if let at = { let details = citationDetails(citation); return details.lineAt ?? details.at }() {
                // The transcript scrolls to that moment and lights the line.
                jumpTranscript(id, to: at)
            }
            return
        }
        if let id = citation.sourceID, let source = sources.first(where: { $0.id == id }) {
            let file = SourceStore.fileURL(for: source)
            if file.pathExtension.lowercased() == "pdf" {
                showPDF(file, page: citation.page ?? CitationQuote.pageNumber(in: citation.detail), quote: citation.quote)
            } else {
                NSWorkspace.shared.open(file)
            }
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
        guard let id = resolvedID, chatRuns[id] == nil, canStartAnotherAnswer, canGenerateAssistant,
              let session = chats.first(where: { $0.id == id }) else {
            chatError = tr("现在不能提问。")
            return false
        }
        let boundMeeting = anchor ?? session.anchorMeetingID
        let boundClass = boundMeeting.flatMap { id in meetings.first { $0.id == id } }
        let meetingItems = chatMeetingItems()
        let sourceItems = chatSourceItems()
        let chosenMeetings: Set<UUID>
        var chosenSources: Set<UUID>
        let hasScope: Bool
        if let boundMeeting {
            chosenMeetings = [boundMeeting]
            chosenSources = Set(meetingLinks[boundMeeting] ?? [])
            let meeting = meetings.first { $0.id == boundMeeting }.map(current)
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
        // Documents attached to this question go into Sources and are always read for it, whatever the scope.
        let pictures = images.filter { !$0.isFile }
        let attached = addChatFiles(images.filter(\.isFile), meetingID: boundMeeting)
        chosenSources.formUnion(attached.map(\.id))
        let allowsWeb = session.allowsWeb && webSearch.isActiveReady
        let mode = llmConfiguration.mode
        let profile = llmConfiguration.activeProfile
        let name = assistantModelName
        let language = prompts.modelLanguageName
        let remembered = memoryPrompt(for: question)
        let history = session.turns
        let chatSummary = session.summary
        // The class being recorded is read from the live transcript, not the copy from before it started.
        let pickedMeetings = meetings.filter { chosenMeetings.contains($0.id) }.map(current)
        let attachedIDs = Set(attached.map(\.id))
        let pickedSources = sources.filter { chosenSources.contains($0.id) && !attachedIDs.contains($0.id) }
        mutate(id) {
            $0.modelMode = mode.rawValue
            $0.profileID = mode == .api ? profile?.id : nil
        }
        chatRuns[id] = ChatRun(question: question, images: images, mode: mode)
        chatTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                self.chatRuns[id] = nil
                self.chatTasks[id] = nil
            }
            do {
                let contextBudget = ContextBudget.current(mode: mode, profile: profile)
                // API models get earlier turns as real messages and keep one system prompt for the whole
                // answer, so each request starts with the bytes of the one before and hits the service's cache.
                let usesMessages = mode == .api
                // Attached files come first, each with its share; the scope gets what is left, and at least a quarter.
                var fileBlocks: [[ContextBlock]] = []
                if !attached.isEmpty {
                    let names = attached.map(\.fileName).joined(separator: "、")
                    let step = self.beginStep(id, .files, trf("正在读取 %@…", AnswerStepSummary.quoted(names)), count: attached.count)
                    for source in attached {
                        fileBlocks.append(await self.passageBlocks(meetings: [], sources: [source]))
                    }
                    self.finishStep(id, step, attached.count == 1
                        ? trf("读取了 %@", AnswerStepSummary.quoted(names))
                        : trf("读取了 %d 个文件 · %@", attached.count, AnswerStepSummary.quoted(names)))
                }
                let filePassages = ChatContext.packFiles(fileBlocks, question: question, budget: contextBudget.scope)
                if !attached.isEmpty && filePassages.isEmpty { throw llmError(tr("附加的文件里没有可以阅读的文字。")) }
                let fileUsed = filePassages.reduce(0) { $0 + $1.body.count }
                let scopeBudget = attached.isEmpty ? contextBudget.scope : max(contextBudget.scope / 4, contextBudget.scope - fileUsed)
                let scopeStep = pickedMeetings.isEmpty && pickedSources.isEmpty ? nil : self.beginStep(id, .files, tr("正在阅读所选的课和资料…"))
                let packed = filePassages + ChatContext.pack(
                    await self.passageBlocks(meetings: pickedMeetings, sources: pickedSources, summaryAbove: scopeBudget),
                    question: question,
                    budget: scopeBudget
                )
                if let scopeStep { self.finishStep(id, scopeStep, trf("读了 %d 段课和资料", packed.count - filePassages.count)) }
                if hasScope && packed.isEmpty { throw llmError(tr("所选范围里还没有可以阅读的文字。")) }
                try Task.checkCancellation()
                let seesImages = ChatImages.seesImages(mode: mode, modelID: profile?.modelID ?? "")
                let imagePlan = ChatContext.attachedImages(history: history, currentCount: pictures.count)
                let promptImages = seesImages ? self.promptImages(current: pictures, history: imagePlan.history) : []
                let historyWindow = ChatHistory.window(
                    history,
                    budget: contextBudget,
                    summary: chatSummary,
                    omittedImageTurns: seesImages ? imagePlan.omittedTurnIDs : [],
                    stableStart: usesMessages
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
                @MainActor func searchLibrary(_ request: LibraryRequest) async -> [ContextBlock] {
                    let step = self.beginStep(id, .library, trf("正在资料库中搜索「%@」…", AnswerStepSummary.quoted(request.query)))
                    if libraryDocuments == nil { libraryDocuments = await self.libraryDocuments(excluding: excluded) }
                    let documents = libraryDocuments ?? []
                    let budget = contextBudget.library
                    let found = await Task.detached(priority: .userInitiated) { LibrarySearch.run(request, in: documents, budget: budget) }.value
                    self.finishStep(id, step, found.isEmpty ? tr("资料库里没有找到相关内容") : trf("在资料库找到 %d 段", found.count))
                    return found
                }
                @MainActor func searchWeb(_ queries: ArraySlice<String>) async throws -> (blocks: [ContextBlock], notice: String?) {
                    let shown = queries.map { "「\(AnswerStepSummary.quoted($0))」" }.joined()
                    let step = self.beginStep(id, .web, trf("正在联网搜索%@…", shown))
                    let found = try await self.searchPasses(queries)
                    let sites = AnswerStepSummary.sites(found.blocks)
                    self.finishStep(id, step, found.blocks.isEmpty
                        ? tr("联网搜索没有结果")
                        : (sites.isEmpty ? trf("找到 %d 个网页", found.blocks.count) : trf("找到 %d 个网页 · %@", found.blocks.count, sites)))
                    return found
                }
                // A question about last week, an earlier chat, or what the teacher said gets searched before the first answer.
                // In a class's own chat, the teacher and today mean that class, so only a question pointing elsewhere searches.
                let searchesFirst = boundClass.map { LibraryRequest.pointsOutsideClass(question, classStartedAt: $0.startedAt) }
                    ?? LibraryRequest.referencesPast(question)
                if library == .available, searchesFirst {
                    let found = await searchLibrary(LibraryRequest(query: question, range: LibraryDates.range(in: question)))
                    try Task.checkCancellation()
                    if !found.isEmpty {
                        blocks.append(contentsOf: found)
                        library = .prefetched
                    }
                }
                // With Web on, search the question itself first so a search happens even when the model would skip it.
                if allowsWeb, let query = ChatContext.searchQuery(question: question, history: history) {
                    let found = try await searchWeb([query][...])
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
                let thinkingLevel: ThinkingLevel = usesMessages ? (profile?.effectiveThinking ?? .off) : .off
                var messages: [LLMMessage] = []
                var system = ""
                var sentPassages = 0
                var lastRaw = ""
                for round in 0..<3 {
                    let webTool: ChatContext.WebTool
                    if !webReachable { webTool = .off }
                    else if searched { webTool = .used }
                    else { webTool = prefetched ? .prefetched : .available }
                    let libraryOpen = library == .available || library == .prefetched
                    let mayStillSearch = (webReachable && !searched) || libraryOpen
                    let request: LLMRequest
                    if usesMessages {
                        if round == 0 {
                            system = ChatContext.composedSystemPrompt(
                                override: self.prompts.systemOverride,
                                language: language,
                                allowsWeb: allowsWeb,
                                hasPassages: !blocks.isEmpty,
                                skills: self.prompts.skills,
                                tools: true,
                                webTool: webTool,
                                library: library,
                                currentClass: boundClass.map { ChatContext.classLabel(title: $0.title, startedAt: $0.startedAt) },
                                memory: remembered
                            )
                            let prompt = ChatContext.userPrompt(
                                question: question,
                                history: historyWindow.forMessages,
                                blocks: blocks,
                                mentionsOlderImages: seesImages && imagePlan.mentionsOlderImages,
                                mentionsLibrary: libraryOpen,
                                steered: steered,
                                attachedFiles: attached.map(\.title)
                            )
                            messages = historyWindow.messages + [LLMMessage(role: .user, text: prompt, images: promptImages)]
                        } else {
                            // Only what is new: the draft as the model wrote it, then the lookup's results.
                            // Marking the first question lets this round reread everything before from cache.
                            messages[historyWindow.messages.count].cacheMark = true
                            messages.append(LLMMessage(role: .assistant, text: lastRaw))
                            messages.append(LLMMessage(role: .user, text: ChatContext.continuationPrompt(
                                newBlocks: Array(blocks[sentPassages...]),
                                startingAt: sentPassages,
                                webFinished: allowsWeb && (searched || !webReachable),
                                libraryFinished: library == .used,
                                draftEmpty: answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                searchFailed: webNotice != nil
                            )))
                        }
                        sentPassages = blocks.count
                        request = LLMRequest(system: system, messages: messages, thinking: thinkingLevel, cacheKey: id.uuidString,
                                             label: round == 0 ? "answer" : "answer-\(round + 1)")
                    } else {
                        let localSystem = ChatContext.composedSystemPrompt(
                            override: self.prompts.systemOverride,
                            language: language,
                            allowsWeb: blocks.count > packed.count,
                            hasPassages: !blocks.isEmpty,
                            skills: self.prompts.skills,
                            tools: true,
                            webTool: webTool,
                            library: library,
                            currentClass: boundClass.map { ChatContext.classLabel(title: $0.title, startedAt: $0.startedAt) },
                            memory: remembered
                        )
                        var prompt = ChatContext.userPrompt(
                            question: question,
                            history: historyWindow,
                            blocks: blocks,
                            mentionsOlderImages: seesImages && imagePlan.mentionsOlderImages,
                            mentionsLibrary: libraryOpen,
                            steered: steered,
                            attachedFiles: attached.map(\.title)
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
                        request = .single(system: localSystem, prompt: prompt, images: promptImages, label: "answer")
                    }
                    let carried = answer
                    let cited = blocks
                    let thinks = thinkingLevel != .off
                    let waitStep = self.beginStep(id, thinks ? .thinking : .writing,
                                                  thinks ? tr("正在思考…") : (round == 0 ? tr("正在写回答…") : tr("正在继续写回答…")))
                    self.chatRuns[id]?.thinking = ""
                    let text = try await self.completeChat(
                        mode: mode,
                        profile: profile,
                        request: request
                    ) { [weak self] progress in
                        guard let self else { return }
                        if !progress.thinking.isEmpty {
                            self.chatRuns[id]?.thinking = progress.thinking
                            // A model can think without being asked (DeepSeek-R1, <think> tags); the line says so.
                            self.markThinking(id, waitStep)
                        }
                        let shown = ChatTools.parse(ChatContext.streamingDisplay(progress.answer), streaming: true, stopAtSearch: mayStillSearch).visible
                        if !shown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.finishWaiting(id, waitStep) }
                        let combined = self.joinedAnswer(carried, shown)
                        self.chatRuns[id]?.answer = combined
                        self.chatRuns[id]?.citations = ChatContext.citations(in: combined, blocks: cited)
                    }
                    self.finishWaiting(id, waitStep)
                    try Task.checkCancellation()
                    lastRaw = text
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
                        let found = try await searchWeb(queries.prefix(2))
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
                let run = self.chatRuns[id]
                let stored = self.storedImages(images)
                let turnID = self.finishChat(id, question: question, answer: answer, modelName: name, citations: ChatContext.citations(in: answer, blocks: blocks), error: nil, images: stored, files: self.fileRefs(attached),
                                             steps: run?.steps ?? [], seconds: run.map { Date().timeIntervalSince($0.startedAt) })
                self.chatRuns[id] = nil
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
                    _ = self.finishChat(id, question: question, answer: "", modelName: name, citations: [], error: error.localizedDescription, images: self.storedImages(images), files: self.fileRefs(attached))
                    self.chatDidEnd(id, succeeded: false)
                }
            }
        }
        return true
    }

    func stopChat(_ chatID: UUID) {
        chatTasks[chatID]?.cancel()
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
        request: LLMRequest,
        localMaxTokens: Int = 2048,
        onProgress: @escaping @MainActor (LLMProgress) -> Void
    ) async throws -> String {
        if mode == .api {
            guard let profile else { throw llmError(tr("请先在设置中选择 API 配置。")) }
            let key = try LLMKeys.read(profile)
            guard profile.isLoopback || !key.isEmpty else { throw llmError(tr("请输入 API 密钥。")) }
            let result = try await RemoteLLMClient.stream(profile: profile, key: key, request: request, onProgress: onProgress)
            // Remembered, so later questions skip what this service turned down.
            llmConfiguration.noteUnsupported(profileID: profile.id, responses: result.responsesRejected, thinking: result.thinkingRejected)
            return result.answer
        }
        guard let engine = self.engine as? LocalEngine else { throw llmError(tr("本地引擎未启动。")) }
        await waitForAfterAnswerWork()
        await waitForQuestionWork()
        let prompt = request.messages.last?.text ?? ""
        return try await engine.generate(system: request.system, prompt: prompt, maxTokens: localMaxTokens) { text in
            onProgress(LLMProgress(answer: text))
        }
    }

    /// Adds a running step to an answer and returns its id.
    @discardableResult
    func beginStep(_ chatID: UUID, _ kind: AnswerStep.Kind, _ title: String, count: Int = 0) -> UUID {
        var step = AnswerStep(kind: kind, title: title, startedAt: .now)
        step.count = count
        chatRuns[chatID]?.steps.append(step)
        return step.id
    }

    /// Ends a step with what it found. A step ended with no detail leaves the list.
    func finishStep(_ chatID: UUID, _ stepID: UUID, _ detail: String) {
        guard let index = chatRuns[chatID]?.steps.firstIndex(where: { $0.id == stepID }),
              chatRuns[chatID]?.steps[index].isRunning == true else { return }
        chatRuns[chatID]?.steps[index].detail = detail
        chatRuns[chatID]?.steps[index].endedAt = .now
    }

    /// The waiting line turns into "正在思考…" when thinking text starts to arrive.
    private func markThinking(_ chatID: UUID, _ stepID: UUID) {
        guard let index = chatRuns[chatID]?.steps.firstIndex(where: { $0.id == stepID }),
              let step = chatRuns[chatID]?.steps[index], step.isRunning, step.kind != .thinking else { return }
        chatRuns[chatID]?.steps[index].kind = .thinking
        chatRuns[chatID]?.steps[index].title = tr("正在思考…")
    }

    /// Ends the thinking or writing line once the answer starts: "思考了 N 秒" when there was
    /// thinking, which can be opened to read it again; otherwise the line just goes.
    private func finishWaiting(_ chatID: UUID, _ stepID: UUID) {
        guard let run = chatRuns[chatID], let index = run.steps.firstIndex(where: { $0.id == stepID }),
              run.steps[index].isRunning else { return }
        let thought = run.thinking.trimmingCharacters(in: .whitespacesAndNewlines)
        chatRuns[chatID]?.steps[index].thought = thought
        finishStep(chatID, stepID, thought.isEmpty ? "" : trf("思考了 %d 秒", run.steps[index].seconds))
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
                    // A demo takes one of the local engine's workers; it waits for a free one.
                    while self.localVisualBusy || self.chatRuns.values.filter({ $0.mode == .local }).count >= LocalEngine.maxReplies {
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
                        request: .single(system: system, prompt: prompt, label: "demo"),
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
        guard let steer = pendingSteers.removeValue(forKey: id) else {
            restoreDraft(id, question: question, images: images)
            chatDidEnd(id, succeeded: false)
            return
        }
        let run = chatRuns[id]
        let shown = (run?.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // The interrupted question is always kept, even before any answer appeared, so the model gets
        // both it and the new message.
        do {
            let turnID = finishChat(id, question: question, answer: shown, modelName: modelName, citations: run?.citations ?? [], error: nil, images: storedImages(images), files: fileRefs(images.compactMap(existingSource)), steps: run?.steps ?? [])
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
        }
        // Runs after this answer's task has cleared its run.
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.ask(steer.text, images: steer.images, chatID: id, steered: true) {
                self.chatQueue.insert(steer, at: 0)
                self.queuePaused.insert(id)
            }
        }
    }

    private func finishChat(_ id: UUID, question: String, answer: String, modelName: String, citations: [ChatCitation], error: String?, images: [ChatImage] = [], files: [ChatFileRef] = [], steps: [AnswerStep] = [], seconds: Double? = nil) -> UUID? {
        guard chats.contains(where: { $0.id == id }) else { return nil }
        var turn = ChatTurn(
            question: question,
            answer: answer,
            modelName: modelName,
            citations: citations,
            error: error,
            images: images,
            files: files
        )
        let kept = AnswerStepSummary.kept(steps)
        if !kept.isEmpty { turn.steps = kept }
        if error == nil { turn.answerSeconds = seconds }
        mutate(id) { session in
            if !session.titleCustom && session.title.isEmpty {
                let source = question.isEmpty ? (files.first?.name ?? images.first?.name ?? "") : question
                session.title = String(source.prefix(20))
            }
            session.turns.append(turn)
        }
        return turn.id
    }

    /// Images move into the chat's own folder. Attached documents are already in Sources, so their
    /// temporary copies are removed.
    private func storedImages(_ drafts: [ChatImageDraft]) -> [ChatImage] {
        drafts.filter(\.isFile).forEach(ChatImages.discard)
        return drafts.filter { !$0.isFile }.compactMap { ChatImages.promote($0) }
    }

    private func fileRefs(_ sources: [KnowledgeSource]) -> [ChatFileRef] {
        sources.map { ChatFileRef(sourceID: $0.id, name: $0.fileName) }
    }

    /// Copies documents attached in the chat box into Sources and returns their records. In a meeting's
    /// chat they join that meeting's category and are linked to it; elsewhere they are Uncategorized.
    /// A file already in Sources (same name and size) is reused rather than copied again.
    func addChatFiles(_ drafts: [ChatImageDraft], meetingID: UUID?) -> [KnowledgeSource] {
        let meeting = meetingID.flatMap { id in meetings.first { $0.id == id } }
        var added: [KnowledgeSource] = []
        for draft in drafts where draft.isFile {
            if let existing = existingSource(draft) {
                added.append(existing)
                continue
            }
            do {
                let source = try SourceStore.stage(draft.fileURL, categoryID: meeting?.categoryID)
                sources.append(source)
                added.append(source)
            } catch {
                chatError = trf("无法加入 %@：%@", draft.name, error.localizedDescription)
            }
        }
        if let meetingID, meeting != nil, !added.isEmpty {
            var links = meetingLinks[meetingID] ?? []
            for source in added where !links.contains(source.id) { links.append(source.id) }
            meetingLinks[meetingID] = links
        }
        return added
    }

    private func existingSource(_ draft: ChatImageDraft) -> KnowledgeSource? {
        guard draft.isFile, let size = (try? draft.fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        return sources.first { $0.fileName == SourceStore.safeFileName(draft.name) && $0.byteCount == Int64(size) }
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
        !sources.isEmpty || meetings.contains { !current($0).paragraphs.isEmpty } || chats.contains { $0.turns.count > 0 && chatRuns[$0.id] == nil }
    }

    /// The student's recorded lectures, earlier chats and imported files, minus what this question already includes.
    private func libraryDocuments(excluding excluded: LibraryExclusions) async -> [LibraryDocument] {
        var documents: [LibraryDocument] = []
        for meeting in meetings.map(current) where !excluded.meetings.contains(meeting.id) {
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
                    meetingID: meeting.id,
                    at: paragraph.openedAt
                ))
            }
        }
        // Cached, so a file whose pictures took a while to read is not read again for the next question.
        for source in sources {
            blocks.append(contentsOf: await SourceTextCache.shared.blocks(for: source))
        }
        return blocks
    }
}
