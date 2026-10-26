import Foundation

/// The Q&A tab: finds the questions the teacher asked and answers them one at a time.
/// With a local model it shares the one chat worker, so it only generates when chat, summaries
/// and memory are quiet, and a chat question waits for at most the answer already generating.
extension AppModel {
    /// The meeting's Q&A, read from disk the first time it is needed.
    func qa(for meetingID: UUID) -> MeetingQA {
        if let state = qaStates[meetingID] { return state }
        let state = MeetingQA(meetingID: meetingID)
        if persistsQA, let stored = MeetingQAStore.load(meetingID) {
            // An answer cut off by quitting is answered again.
            state.questions = stored.questions.map { question in
                var copy = question
                if copy.status == .answering { copy.status = .queued; copy.answer = "" }
                return copy
            }
            state.autoAnswer = stored.autoAnswer
            state.scannedThrough = stored.scannedThrough
        }
        qaStates[meetingID] = state
        if state.questions.contains(where: { $0.status == .queued }) { kickQuestionQueue() }
        return state
    }

    private var persistsQA: Bool { chatsReady }

    func saveQA(_ state: MeetingQA) {
        guard persistsQA else { return }
        MeetingQAStore.save(state.meetingID, .init(questions: state.questions, autoAnswer: state.autoAnswer, scannedThrough: state.scannedThrough))
    }

    // MARK: Transcript

    /// The transcript as timed lines. A recording in progress uses its finished paragraphs only.
    func transcriptLines(_ meetingID: UUID, includingOpen: Bool = false) -> [QuestionFinder.Line] {
        guard let meeting = meetings.first(where: { $0.id == meetingID }) else { return [] }
        let live = meetingID == recordingMeetingID
        let paragraphs = live ? engine.transcript.paragraphs.filter { $0.closed || includingOpen } : meeting.paragraphs
        return paragraphs.compactMap { paragraph in
            let text = paragraph.renderedSource(language: meeting.sourceLanguage).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : QuestionFinder.Line(at: paragraph.openedAt, text: text)
        }
    }

    // MARK: Finding questions

    /// Checks the live transcript every two minutes while recording.
    func startLiveQuestionScan(_ meetingID: UUID) {
        questionScanTask?.cancel()
        questionScanTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard let self, !Task.isCancelled, self.recordingMeetingID == meetingID else { return }
                await self.findQuestions(meetingID)
            }
        }
    }

    /// One last pass over the whole transcript once the recording is saved.
    func finishQuestionScan(_ meetingID: UUID) {
        questionScanTask?.cancel()
        questionScanTask = nil
        quickQuestionCheck?.cancel()
        settleQuestionPopups()
        guard meetings.contains(where: { $0.id == meetingID }) else { return }
        Task { [weak self] in await self?.findQuestions(meetingID) }
    }

    /// Called for each committed line while recording. When the newest sentence reads like a
    /// question, the recent transcript is checked a few seconds later instead of at the next
    /// two-minute pass, so the pop-up appears while the teacher is still on that question.
    func checkLatestLineForQuestion() {
        guard let id = recordingMeetingID, QuestionPopupPreference.isOn else { return }
        let state = qa(for: id)
        let fresh = transcriptLines(id, includingOpen: true).filter { $0.at > state.scannedThrough }.suffix(2)
        guard !QuestionFinder.candidates(in: Array(fresh)).isEmpty else { return }
        quickQuestionCheck?.cancel()
        quickQuestionCheck = Task { [weak self] in
            // Let the sentence finish, and fold a burst of commits into one check.
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, self.recordingMeetingID == id else { return }
            await self.findQuestions(id, includingOpen: true)
        }
    }

    /// Reads transcript not read before, in passes, and adds the questions found.
    /// `includingOpen` also reads the paragraph still being spoken, without marking it read.
    func findQuestions(_ meetingID: UUID, fromStart: Bool = false, includingOpen: Bool = false) async {
        guard canRunBackgroundWork else { return }
        let state = qa(for: meetingID)
        guard !state.scanning else { return }
        state.scanning = true
        state.scanError = nil
        defer { state.scanning = false }
        if fromStart { state.scannedThrough = -1 }
        let closed = transcriptLines(meetingID)
        let fresh = transcriptLines(meetingID, includingOpen: includingOpen).filter { $0.at > state.scannedThrough }
        // The open paragraph keeps growing; only finished ones count as read.
        let readUpTo = { (at: TimeInterval) in min(at, closed.last?.at ?? state.scannedThrough) }
        let live = meetingID == recordingMeetingID && QuestionPopupPreference.isOn
        let language = prompts.modelLanguageName
        for chunk in QuestionFinder.chunks(fresh) {
            guard let last = chunk.last, state.questions.count < QuestionFinder.perMeeting else { break }
            // Most of a lecture asks nothing; skip the model call when no sentence looks like a question.
            guard !QuestionFinder.candidates(in: chunk).isEmpty else {
                state.scannedThrough = max(state.scannedThrough, readUpTo(last.at))
                continue
            }
            let mode = llmConfiguration.mode
            guard await waitUntilQuiet(local: mode == .local, forChat: false) else { return }
            questionWorkGenerating = true
            let reply = try? await backgroundReply(
                mode: mode,
                profile: llmConfiguration.activeProfile,
                system: QuestionFinder.findSystem(language: language),
                prompt: QuestionFinder.findPrompt(lines: chunk, found: state.questions),
                maxTokens: 700
            )
            questionWorkGenerating = false
            guard let reply else {
                state.scanError = tr("暂时没能找出问题，稍后会再试。")
                break
            }
            // While recording, the pop-up decides first; a question left alone follows Auto-answer then.
            let found = QuestionFinder.parse(reply, lines: chunk, existing: state.questions, status: live ? .waiting : (state.autoAnswer ? .queued : .waiting))
            state.questions.append(contentsOf: found)
            state.scannedThrough = max(state.scannedThrough, readUpTo(last.at))
            saveQA(state)
            if live { found.forEach { showQuestionPopup(QuestionPopup(meetingID: meetingID, questionID: $0.id)) } }
        }
        saveQA(state)
        if state.questions.contains(where: { $0.status == .queued }) { kickQuestionQueue() }
    }

    // MARK: Answering

    /// Waits until generating will not get in the way. Chat always goes first; with a local model,
    /// summaries, memory and the other Q&A job also go first. False when cancelled.
    private func waitUntilQuiet(local: Bool, forChat: Bool) async -> Bool {
        while true {
            if Task.isCancelled { return false }
            let chatting = isChatAnswering || assistantStates.values.contains { $0.isGenerating }
            let busyLocally = local && (assistantIsBusy || afterAnswerGenerating || questionWorkGenerating)
            if !(forChat ? chatting || busyLocally : busyLocally) { return true }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func kickQuestionQueue() {
        guard questionQueueTask == nil else { return }
        questionQueueTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                guard let next = self.nextQueuedQuestion() else { break }
                let local = self.llmConfiguration.mode == .local
                guard await self.waitUntilQuiet(local: local, forChat: true) else { break }
                // The student may have deleted or turned off the question while the queue waited.
                guard let index = next.state.questions.firstIndex(where: { $0.id == next.id }),
                      next.state.questions[index].status == .queued else { continue }
                // Claimed before gathering passages, so a chat question cannot start on the local model in between.
                if local { self.questionWorkGenerating = true }
                await self.answer(next.id, in: next.state)
                self.questionWorkGenerating = false
                // Still queued means it could not start (no model, or its meeting is gone).
                // Stop instead of retrying in a tight loop that freezes the app; the next ask restarts the queue.
                if next.state.questions.first(where: { $0.id == next.id })?.status == .queued { break }
            }
            self?.questionQueueTask = nil
        }
    }

    private func nextQueuedQuestion() -> (state: MeetingQA, id: UUID)? {
        if let urgent = urgentQuestionID {
            for state in qaStates.values where state.questions.contains(where: { $0.id == urgent && $0.status == .queued }) {
                return (state, urgent)
            }
            urgentQuestionID = nil
        }
        for state in qaStates.values {
            // Newest first, matching the Q&A tab: the question just asked matters most in class.
            if let question = state.questions.last(where: { $0.status == .queued }) { return (state, question.id) }
        }
        return nil
    }

    private func answer(_ id: UUID, in state: MeetingQA) async {
        guard canRunBackgroundWork, let index = state.questions.firstIndex(where: { $0.id == id }),
              let meeting = meetings.first(where: { $0.id == state.meetingID }) else { return }
        let question = state.questions[index]
        state.questions[index].status = .answering
        state.questions[index].answer = ""
        state.questions[index].error = nil
        let mode = llmConfiguration.mode
        let profile = llmConfiguration.activeProfile
        let name = assistantModelName
        let budget = ContextBudget.current(mode: mode, profile: profile)

        // The moment the teacher asked it comes first, then the rest of the lecture and its files by relevance.
        let lines = transcriptLines(meeting.id)
        let lecture = current(meeting)
        let linked = sources.filter { meetingLinks[meeting.id]?.contains($0.id) == true }
        var blocks = QuestionFinder.moment(question, in: lines, meetingID: meeting.id, title: meeting.title)
        let around = Set(blocks.map(\.body))
        let packed = ChatContext.pack(await passageBlocks(meetings: [lecture], sources: linked), question: question.text, budget: budget.scope)
        blocks += packed.filter { !around.contains($0.body) }
        let chat = meetingChatID[meeting.id].flatMap { chatID in chats.first { $0.id == chatID } }
        let allowsWeb = (chat?.allowsWeb ?? false) && webSearch.isActiveReady
        if allowsWeb, let found = try? await searchPasses([question.text][...]) {
            blocks += found.blocks
        }
        let memory = memoryPrompt(for: question.text)
        var system = QuestionFinder.answerSystem(language: prompts.modelLanguageName, hasWeb: blocks.contains { $0.url != nil })
        if !memory.isEmpty { system += "\n\n" + memory }
        let prompt = ChatContext.userPrompt(question: QuestionFinder.answerQuestion(question), history: .empty, blocks: blocks)

        do {
            let text = try await questionReply(mode: mode, profile: profile, system: system, prompt: prompt) { [weak state] partial in
                guard let state, let current = state.questions.firstIndex(where: { $0.id == id }) else { return }
                state.questions[current].answer = partial
            }
            guard let current = state.questions.firstIndex(where: { $0.id == id }) else { return }
            state.questions[current].answer = text
            state.questions[current].citations = ChatContext.citations(in: text, blocks: blocks)
            state.questions[current].modelName = name
            state.questions[current].status = .answered
        } catch {
            guard let current = state.questions.firstIndex(where: { $0.id == id }) else { return }
            state.questions[current].status = .failed
            state.questions[current].error = error.localizedDescription
        }
        saveQA(state)
    }

    /// Streams an answer. Local answers are background work, so the chat box stays usable.
    private func questionReply(mode: LLMMode, profile: LLMAPIProfile?, system: String, prompt: String, onUpdate: @escaping @MainActor (String) -> Void) async throws -> String {
        if mode == .api {
            guard let profile else { throw llmError(tr("请先在设置中选择 API 配置。")) }
            let key = try LLMKeychain.read(profile)
            guard profile.isLoopback || !key.isEmpty else { throw llmError(tr("请输入 API 密钥。")) }
            return try await RemoteLLMClient.generate(profile: profile, key: key, system: system, prompt: prompt, onUpdate: onUpdate)
        }
        guard let engine = engine as? LocalEngine else { throw llmError(tr("本地引擎未启动。")) }
        return try await engine.generate(system: system, prompt: prompt, maxTokens: 900, background: true, onUpdate: onUpdate)
    }

    /// A chat reply waits for a Q&A generation that is already running on the local model.
    func waitForQuestionWork() async {
        while questionWorkGenerating, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    // MARK: Actions from the tab

    func setAutoAnswer(_ on: Bool, for meetingID: UUID) {
        let state = qa(for: meetingID)
        state.autoAnswer = on
        for index in state.questions.indices {
            if on, state.questions[index].status == .waiting { state.questions[index].status = .queued }
            if !on, state.questions[index].status == .queued { state.questions[index].status = .waiting }
        }
        saveQA(state)
        if on { kickQuestionQueue() }
    }

    /// Ask one question now, or again after an edit or a failure.
    func askQuestion(_ id: UUID, in meetingID: UUID) {
        let state = qa(for: meetingID)
        guard let index = state.questions.firstIndex(where: { $0.id == id }), state.questions[index].status != .answering else { return }
        state.questions[index].status = .queued
        state.questions[index].error = nil
        saveQA(state)
        kickQuestionQueue()
    }

    func askAllQuestions(in meetingID: UUID) {
        let state = qa(for: meetingID)
        for index in state.questions.indices where state.questions[index].status == .waiting || state.questions[index].status == .failed {
            state.questions[index].status = .queued
        }
        saveQA(state)
        kickQuestionQueue()
    }

    func editQuestion(_ id: UUID, in meetingID: UUID, text: String) {
        let state = qa(for: meetingID)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = state.questions.firstIndex(where: { $0.id == id }),
              state.questions[index].status != .answering, state.questions[index].text != trimmed else { return }
        state.questions[index].text = trimmed
        // An edited question needs a new answer.
        if state.questions[index].status == .answered || state.questions[index].status == .failed {
            state.questions[index].answer = ""
            state.questions[index].citations = []
            state.questions[index].status = state.autoAnswer ? .queued : .waiting
        }
        saveQA(state)
        if state.questions[index].status == .queued { kickQuestionQueue() }
    }

    func deleteQuestion(_ id: UUID, in meetingID: UUID) {
        let state = qa(for: meetingID)
        guard state.questions.first(where: { $0.id == id })?.status != .answering else { return }
        state.questions.removeAll { $0.id == id }
        saveQA(state)
    }

    /// Moves a question up or down in the queue.
    func moveQuestion(_ id: UUID, in meetingID: UUID, by offset: Int) {
        let state = qa(for: meetingID)
        guard let index = state.questions.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard state.questions.indices.contains(target) else { return }
        state.questions.swapAt(index, target)
        saveQA(state)
    }

    /// Copies the question and its answer into the meeting's chat, for follow-up questions.
    func continueQuestionInChat(_ id: UUID, in meetingID: UUID) {
        let state = qa(for: meetingID)
        guard let question = state.questions.first(where: { $0.id == id }), question.status == .answered else { return }
        appendTurnToMeetingChat(meetingID, turn: ChatTurn(
            question: question.text,
            answer: question.answer,
            modelName: question.modelName,
            citations: question.citations
        ))
    }

    /// Scrolls the meeting's transcript to a moment.
    func jumpTranscript(_ meetingID: UUID, to time: TimeInterval) {
        transcriptJump = TranscriptJump(meetingID: meetingID, time: time)
    }

    func forgetQA(_ meetingID: UUID) {
        qaStates[meetingID] = nil
        MeetingQAStore.delete(meetingID)
    }
}

/// A request to scroll a meeting's transcript; a new token repeats the jump.
struct TranscriptJump: Equatable {
    var meetingID: UUID
    var time: TimeInterval
    var token = UUID()
    var createdAt = Date.now

    /// A transcript that appears later (reopening the meeting) should not jump again.
    var isFresh: Bool { Date.now.timeIntervalSince(createdAt) < 3 }
}

// MARK: - Live question pop-up

extension AppModel {
    func showQuestionPopup(_ popup: QuestionPopup) {
        guard questionPopup?.questionID != popup.questionID,
              !questionPopupQueue.contains(where: { $0.questionID == popup.questionID }) else { return }
        if questionPopup == nil {
            questionPopup = popup
        } else {
            questionPopupQueue.append(popup)
        }
    }

    func question(for popup: QuestionPopup) -> MeetingQuestion? {
        qa(for: popup.meetingID).questions.first { $0.id == popup.questionID }
    }

    /// Answer now: first in the queue, and the pop-up stays to show the answer.
    func answerPopupQuestionNow() {
        guard let popup = questionPopup else { return }
        urgentQuestionID = popup.questionID
        askQuestion(popup.questionID, in: popup.meetingID)
        questionPopup?.answering = true
    }

    /// Later: the question waits in the Q&A tab until the student asks for it.
    func answerPopupQuestionLater() {
        closeQuestionPopup()
    }

    /// Nobody chose: the question follows the meeting's Auto-answer switch.
    func questionPopupTimedOut() {
        guard let popup = questionPopup else { return }
        let state = qa(for: popup.meetingID)
        if !popup.answering, state.autoAnswer,
           state.questions.first(where: { $0.id == popup.questionID })?.status == .waiting {
            askQuestion(popup.questionID, in: popup.meetingID)
        }
        closeQuestionPopup()
    }

    /// The pop-up belongs to the recording. When it ends, unanswered cards are treated as left alone.
    func settleQuestionPopups() {
        while let popup = questionPopup {
            if popup.answering {
                closeQuestionPopup()
            } else {
                questionPopupTimedOut()
            }
        }
    }

    func closeQuestionPopup() {
        questionPopup = questionPopupQueue.isEmpty ? nil : questionPopupQueue.removeFirst()
    }

    /// Open in Q&A: the meeting, its side panel on the Q&A tab, and the moment in the transcript.
    func openPopupQuestionInQA() {
        guard let popup = questionPopup, let question = question(for: popup) else { return }
        page = .meetings
        openMeetingID = popup.meetingID
        detailTabRequest = DetailTabRequest(meetingID: popup.meetingID, tab: .qa)
        jumpTranscript(popup.meetingID, to: question.at)
        closeQuestionPopup()
    }
}

/// One question the pop-up is showing.
struct QuestionPopup: Equatable, Identifiable {
    var meetingID: UUID
    var questionID: UUID
    /// The student pressed Answer now; the card stays to show the answer.
    var answering = false
    var id: UUID { questionID }
}

/// Asks a meeting's side panel to show a tab; a new token repeats the request.
struct DetailTabRequest: Equatable {
    var meetingID: UUID
    var tab: DetailTab
    var token = UUID()
}

/// Settings › Questions & Summaries › question pop-ups while recording. On by default.
enum QuestionPopupPreference {
    static let key = "lecturenote.questionPopups"
    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

