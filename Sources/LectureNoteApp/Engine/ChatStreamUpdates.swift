import Foundation

/// Throttle cumulative answers, not token deltas. The last value includes every token.
@MainActor
final class ChatStreamUpdates {
    private var latest: String?
    private var task: Task<Void, Never>?
    private let onUpdate: (String) -> Void
    private let interval: Duration

    init(interval: Duration = .milliseconds(50), onUpdate: @escaping (String) -> Void) {
        self.interval = interval
        self.onUpdate = onUpdate
    }

    func submit(_ text: String) {
        latest = text
        guard task == nil else { return }
        task = Task { [weak self, interval] in
            do { try await Task.sleep(for: interval) } catch { return }
            self?.flush()
        }
    }

    func flush() {
        task?.cancel()
        task = nil
        guard let latest else { return }
        self.latest = nil
        onUpdate(latest)
    }

    func cancel() {
        task?.cancel()
        task = nil
        latest = nil
    }
}
