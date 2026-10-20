import Foundation
import Testing
@testable import LectureNoteApp

struct ChatQueueTests {
    private func item(_ text: String, chat: UUID, at seconds: Double) -> QueuedPrompt {
        QueuedPrompt(chatID: chat, text: text, images: [], createdAt: Date(timeIntervalSince1970: 1_800_000_000 + seconds))
    }

    @Test func theChatThatJustAnsweredGoesFirstThenTheOldestElsewhere() {
        let a = UUID(), b = UUID()
        let queue = [item("b1", chat: b, at: 1), item("a1", chat: a, at: 2), item("b2", chat: b, at: 3)]
        #expect(ChatQueueRules.next(queue, paused: [], after: a)?.text == "a1")
        #expect(ChatQueueRules.next(queue, paused: [], after: UUID())?.text == "b1")
        #expect(ChatQueueRules.next(queue, paused: [b], after: b)?.text == "a1")
        #expect(ChatQueueRules.next(queue, paused: [a, b], after: a) == nil)
    }

    @Test func reorderingMovesWithinOneChatAndLeavesOthersInPlace() {
        let a = UUID(), b = UUID()
        let queue = [item("a1", chat: a, at: 1), item("b1", chat: b, at: 2), item("a2", chat: a, at: 3), item("a3", chat: a, at: 4)]
        let moved = ChatQueueRules.moving(queue, id: queue[3].id, toOffset: 0)
        #expect(moved.map(\.text) == ["a3", "b1", "a1", "a2"])
        #expect(ChatQueueRules.next(moved, paused: [], after: a)?.text == "a3")
    }

    @Test func enterUsesTheSettingAndCommandEnterTheOther() {
        let key = BusySendMode.key
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        #expect(BusySendMode.current == .queue)
        BusySendMode.current = .steer
        #expect(BusySendMode.current == .steer)
        #expect(BusySendMode.steer.other == .queue)
        #expect(BusySendMode.queue.other == .steer)
    }

    @MainActor @Test func aStopOrErrorPausesThatChatsQueueAndASendResumesIt() {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        let chat = UUID()
        model.enqueue("下一个问题", images: [], chatID: chat)
        model.chatDidEnd(chat, succeeded: false)
        #expect(model.queuePaused.contains(chat))
        model.enqueue("再一个", images: [], chatID: chat)
        #expect(!model.queuePaused.contains(chat))
        #expect(model.queued(in: chat).map(\.text) == ["下一个问题", "再一个"])
    }

    @MainActor @Test func aQueueWaitsWhenNoModelCanAnswer() {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        let chat = UUID()
        model.enqueue("问题", images: [], chatID: chat)
        if !model.canGenerateAssistant {
            model.advanceQueue(after: chat)
            #expect(model.queuePaused.contains(chat))
            #expect(model.queued(in: chat).count == 1)
        }
    }

    @MainActor @Test func editingRemovingAndClearingTheQueue() {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        let chat = UUID()
        model.enqueue("一", images: [], chatID: chat)
        model.enqueue("二", images: [], chatID: chat)
        let first = model.queued(in: chat)[0]
        #expect(model.takeQueued(first.id)?.text == "一")
        #expect(model.queued(in: chat).map(\.text) == ["二"])
        model.removeQueued(model.queued(in: chat)[0].id)
        #expect(model.queued(in: chat).isEmpty)
        model.enqueue("三", images: [], chatID: chat)
        model.queuePaused.insert(chat)
        model.clearQueue(chat)
        #expect(model.queued(in: chat).isEmpty)
        #expect(!model.queuePaused.contains(chat))
    }

    @MainActor @Test func deletingAChatDropsItsQueue() {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        model.ensureChat()
        let chat = model.currentChatID!
        model.enqueue("问题", images: [], chatID: chat)
        model.deleteChat(chat)
        #expect(model.queued(in: chat).isEmpty)
    }
}
