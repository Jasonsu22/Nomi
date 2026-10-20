import Foundation

/// Messages sent while an answer is coming: queued until it finishes, or used to steer it.
extension AppModel {
    /// Sends from a composer. When nothing is answering this is a normal question; otherwise `mode`
    /// decides between queueing and steering. Returns false when nothing was taken.
    @discardableResult
    func submit(_ question: String, images: [ChatImageDraft], anchor: UUID?, mode: BusySendMode) -> Bool {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return false }
        guard let running = chatGeneratingID else {
            return ask(trimmed, images: images, anchor: anchor)
        }
        if let anchor { ensureMeetingChat(anchor) } else { ensureChat() }
        guard let chatID = anchor.flatMap({ meetingChatID[$0] }) ?? currentChatID else { return false }
        // Steering another chat's answer from here would surprise the student, so it queues instead.
        if mode == .steer, running == chatID {
            return steer(trimmed, images: images, chatID: chatID)
        }
        enqueue(trimmed, images: images, chatID: chatID)
        return true
    }

    func enqueue(_ text: String, images: [ChatImageDraft], chatID: UUID) {
        chatQueue.append(QueuedPrompt(chatID: chatID, text: text, images: images))
        queuePaused.remove(chatID)
    }

    func queued(in chatID: UUID?) -> [QueuedPrompt] {
        guard let chatID else { return [] }
        return chatQueue.filter { $0.chatID == chatID }
    }

    /// Sends the next queued message once nothing is answering. Called after each answer ends.
    func advanceQueue(after chatID: UUID?) {
        guard chatGeneratingID == nil,
              let next = ChatQueueRules.next(chatQueue, paused: queuePaused, after: chatID) else { return }
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

    /// Called when an answer ends. A finished answer moves the queue on; a stop or an error pauses
    /// that chat's queue, so nothing is sent behind the student's back.
    func chatDidEnd(_ chatID: UUID, succeeded: Bool) {
        // The answer finished just before a steer could stop it; send the steer message next.
        if let steer = pendingSteer, steer.chatID == chatID {
            pendingSteer = nil
            chatQueue.insert(steer, at: 0)
            queuePaused.remove(chatID)
        }
        if !succeeded, chatQueue.contains(where: { $0.chatID == chatID }) {
            queuePaused.insert(chatID)
        }
        // Runs after the finished answer's task has cleared `chatGeneratingID`.
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
        if chatGeneratingID == item.chatID {
            _ = steer(item.text, images: item.images, chatID: item.chatID)
        } else if chatGeneratingID == nil {
            if !ask(item.text, images: item.images, chatID: item.chatID) { chatQueue.insert(item, at: 0) }
        } else {
            // Another chat is answering; this one goes first once it finishes.
            chatQueue.insert(item, at: 0)
        }
    }

    /// Stops the current answer of `chatID` and sends `text` at once, keeping what the answer had
    /// shown. If that chat is not answering, the message is sent or queued as usual.
    func steer(_ text: String, images: [ChatImageDraft], chatID: UUID) -> Bool {
        guard chatGeneratingID == chatID, pendingSteer == nil else {
            if chatGeneratingID == nil { return ask(text, images: images, chatID: chatID) }
            enqueue(text, images: images, chatID: chatID)
            return true
        }
        pendingSteer = QueuedPrompt(chatID: chatID, text: text, images: images)
        stopChat()
        return true
    }
}
