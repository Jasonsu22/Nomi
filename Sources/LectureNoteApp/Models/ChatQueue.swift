import Foundation

/// What Enter does while Nomi is still answering. ⌘Enter does the other one.
enum BusySendMode: String, CaseIterable, Identifiable {
    /// Wait for the answer, then send queued messages in order.
    case queue
    /// Stop the answer where it is and send the new message at once.
    case steer

    static let key = "nomi.chat.busySend"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queue: tr("排队")
        case .steer: tr("打断并引导")
        }
    }

    var other: BusySendMode { self == .queue ? .steer : .queue }

    static var current: BusySendMode {
        get { UserDefaults.standard.string(forKey: key).flatMap(BusySendMode.init(rawValue:)) ?? .queue }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// One chat's answer while it is coming in.
struct ChatRun: Equatable {
    var question: String
    var images: [ChatImageDraft]
    var mode: LLMMode
    var answer = ""
    var citations: [ChatCitation] = []
}

/// A message sent while another answer was still coming, waiting for its turn.
struct QueuedPrompt: Identifiable, Equatable {
    var id = UUID()
    var chatID: UUID
    var text: String
    var images: [ChatImageDraft]
    var createdAt = Date()
}

/// Which queued message goes next. Pure, so the order can be tested.
enum ChatQueueRules {
    /// The chat that just answered goes first, so its follow-ups stay together; then the oldest
    /// message of any other chat. Paused chats wait for the student.
    static func next(_ queue: [QueuedPrompt], paused: Set<UUID>, after chatID: UUID?) -> QueuedPrompt? {
        let ready = queue.filter { !paused.contains($0.chatID) }
        if let chatID, let same = ready.first(where: { $0.chatID == chatID }) { return same }
        return ready.min { $0.createdAt < $1.createdAt }
    }

    /// Moves one chat's item to a new place among that chat's items, leaving other chats in order.
    static func moving(_ queue: [QueuedPrompt], id: UUID, toOffset offset: Int) -> [QueuedPrompt] {
        guard let item = queue.first(where: { $0.id == id }) else { return queue }
        var own = queue.filter { $0.chatID == item.chatID }
        let positions = queue.indices.filter { queue[$0].chatID == item.chatID }
        own.removeAll { $0.id == id }
        own.insert(item, at: min(max(0, offset), own.count))
        var result = queue
        for (position, value) in zip(positions, own) { result[position] = value }
        return result
    }
}
