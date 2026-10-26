import Foundation

/// Messages sent while an answer is coming: queued until it finishes, or used to steer it.
/// Each chat answers on its own, so only a chat's own answer makes its messages wait.
extension AppModel {
    var isChatAnswering: Bool { !chatRuns.isEmpty }

    func isAnswering(_ chatID: UUID?) -> Bool {
        chatID.map { chatRuns[$0] != nil } ?? false
    }

    /// Whether another chat may start answering now. API answers run side by side; the local
    /// engine runs a few at once, each in its own worker, and further ones wait their turn.
    var canStartAnotherAnswer: Bool {
        llmConfiguration.mode == .api || chatRuns.values.filter { $0.mode == .local }.count < LocalEngine.maxReplies
    }

    /// Sends from a composer. When this chat is not answering this is a normal question; otherwise
    /// `mode` decides between queueing and steering. Returns false when nothing was taken.
    @discardableResult
    func submit(_ question: String, images: [ChatImageDraft], anchor: UUID?, mode: BusySendMode) -> Bool {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return false }
        if let anchor { ensureMeetingChat(anchor) } else { ensureChat() }
        guard let chatID = anchor.flatMap({ meetingChatID[$0] }) ?? currentChatID else { return false }
        if isAnswering(chatID) {
            if mode == .steer { return steer(trimmed, images: images, chatID: chatID) }
            enqueue(trimmed, images: images, chatID: chatID)
            return true
        }
        guard canStartAnotherAnswer else {
            enqueue(trimmed, images: images, chatID: chatID)
            return true
        }
        return ask(trimmed, images: images, chatID: chatID)
    }

    func enqueue(_ text: String, images: [ChatImageDraft], chatID: UUID) {
        chatQueue.append(QueuedPrompt(chatID: chatID, text: text, images: images))
        queuePaused.remove(chatID)
    }

    func queued(in chatID: UUID?) -> [QueuedPrompt] {
        guard let chatID else { return [] }
        return chatQueue.filter { $0.chatID == chatID }
    }

    /// Sends queued messages for chats that are not answering, as many as may run at once.
    /// Called after each answer ends.
    func advanceQueue(after chatID: UUID?) {
        while canStartAnotherAnswer,
              let next = ChatQueueRules.next(chatQueue.filter { !isAnswering($0.chatID) }, paused: queuePaused, after: chatID) {
            guard canGenerateAssistant else {
                // The model is missing or switching; wait for the student instead of failing each message.
                queuePaused.insert(next.chatID)
                return
            }
            chatQueue.removeAll { $0.id == next.id }
            if !ask(next.text, images: next.images, chatID: next.chatID) {
                chatQueue.insert(next, at: 0)
                queuePaused.insert(next.chatID)
            }
        }
    }

    /// Called when an answer ends. A finished answer moves the queue on; a stop or an error pauses
    /// that chat's queue, so nothing is sent behind the student's back.
    func chatDidEnd(_ chatID: UUID, succeeded: Bool) {
        // The answer finished just before a steer could stop it; send the steer message next.
        if let steer = pendingSteers.removeValue(forKey: chatID) {
            chatQueue.insert(steer, at: 0)
            queuePaused.remove(chatID)
        }
        if !succeeded, chatQueue.contains(where: { $0.chatID == chatID }) {
            queuePaused.insert(chatID)
        }
        // Runs after the finished answer's task has cleared its run.
        Task { @MainActor [weak self] in self?.advanceQueue(after: chatID) }
    }

    func resumeQueue(_ chatID: UUID) {
        queuePaused.remove(chatID)
        advanceQueue(after: chatID)
    }

    func removeQueued(_ id: UUID) {
        guard let item = chatQueue.first(where: { $0.id == id }) else { return }
        chatQueue.removeAll { $0.id == id }
        item.images.forEach(ChatImages.discard)
        if !chatQueue.contains(where: { $0.chatID == item.chatID }) { queuePaused.remove(item.chatID) }
    }

    func clearQueue(_ chatID: UUID) {
        for item in chatQueue where item.chatID == chatID { item.images.forEach(ChatImages.discard) }
        chatQueue.removeAll { $0.chatID == chatID }
        queuePaused.remove(chatID)
    }

    /// Takes a queued message out so the student can edit it in the composer.
    func takeQueued(_ id: UUID) -> QueuedPrompt? {
        guard let item = chatQueue.first(where: { $0.id == id }) else { return nil }
        chatQueue.removeAll { $0.id == id }
        if !chatQueue.contains(where: { $0.chatID == item.chatID }) { queuePaused.remove(item.chatID) }
        return item
    }

    func moveQueued(_ id: UUID, toOffset offset: Int) {
        chatQueue = ChatQueueRules.moving(chatQueue, id: id, toOffset: offset)
    }

    /// Sends a queued message now, steering the current answer of its chat.
    func sendQueuedNow(_ id: UUID) {
        guard let item = takeQueued(id) else { return }
        if isAnswering(item.chatID) {
            _ = steer(item.text, images: item.images, chatID: item.chatID)
        } else if canStartAnotherAnswer {
            if !ask(item.text, images: item.images, chatID: item.chatID) { chatQueue.insert(item, at: 0) }
        } else {
            // The local model is answering as many chats as it can; this one goes first after that.
            chatQueue.insert(item, at: 0)
        }
    }

    /// Stops the current answer of `chatID` and sends `text` at once, keeping what the answer had
    /// shown. If that chat is not answering, the message is sent or queued as usual.
    func steer(_ text: String, images: [ChatImageDraft], chatID: UUID) -> Bool {
        guard isAnswering(chatID), pendingSteers[chatID] == nil else {
            if !isAnswering(chatID), canStartAnotherAnswer { return ask(text, images: images, chatID: chatID) }
            enqueue(text, images: images, chatID: chatID)
            return true
        }
        pendingSteers[chatID] = QueuedPrompt(chatID: chatID, text: text, images: images)
        stopChat(chatID)
        return true
    }
}
