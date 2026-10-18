import Foundation
import Observation

@MainActor
@Observable
final class LocalModelLibrary {
    private(set) var installed: Set<String> = []
    private(set) var downloads: [String: ModelDownloadProgress] = [:]
    var errors: [String: String] = [:]
    var switchingID: String?
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init() { refresh() }

    func refresh() {
        installed = Set(LocalModelDefinition.catalog.filter { LocalModelFiles.isComplete($0) }.map(\.id))
    }

    func download(_ model: LocalModelDefinition) {
        guard tasks[model.id] == nil, !installed.contains(model.id) else { return }
        errors[model.id] = nil
        downloads[model.id] = ModelDownloadProgress()
        tasks[model.id] = Task { [weak self] in
            do {
                try await ModelRepositoryDownload.download(model) { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.tasks[model.id] != nil else { return }
                        self.downloads[model.id] = progress
                    }
                }
            } catch is CancellationError {
                // Completed files remain in staging for the next attempt.
            } catch {
                if !Task.isCancelled { self?.errors[model.id] = error.localizedDescription }
            }
            guard let self else { return }
            self.tasks[model.id] = nil
            self.downloads[model.id] = nil
            self.refresh()
        }
    }

    func cancel(_ model: LocalModelDefinition) {
        tasks[model.id]?.cancel()
    }

    func rememberSelection(_ model: LocalModelDefinition) {
        UserDefaults.standard.set(model.id, forKey: model.role.preferenceKey)
    }
}
