import Foundation
import Observation

@MainActor
@Observable
final class LocalModelLibrary {
    private(set) var installed: Set<String> = []
    private(set) var downloads: [String: ModelDownloadProgress] = [:]
    var errors: [String: String] = [:]
    var switchingID: String?
    var switchingRole: LocalModelRole?
    var deletingID: String?
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init() { refresh() }

    @ObservationIgnored private var scanTask: Task<Void, Never>?

    func refresh() {
        scanTask?.cancel()
        scanTask = nil
        installed = Self.scanInstalled()
    }

    /// Reads the model folders off the main thread, so opening a page never waits on disk.
    func refreshInBackground() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            let found = await Task.detached(priority: .utility) { Self.scanInstalled() }.value
            guard !Task.isCancelled, let self else { return }
            self.scanTask = nil
            if self.installed != found { self.installed = found }
        }
    }

    nonisolated private static func scanInstalled() -> Set<String> {
        Set(LocalModelDefinition.catalog.filter { LocalModelFiles.isComplete($0) }.map(\.id))
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

    func rememberSelection(_ model: LocalModelDefinition, for role: LocalModelRole) {
        UserDefaults.standard.set(model.id, forKey: role.preferenceKey)
    }

    func trash(_ model: LocalModelDefinition) throws {
        guard tasks[model.id] == nil,
              model.directory.deletingLastPathComponent().resolvingSymlinksInPath() == LocalModelDefinition.root.resolvingSymlinksInPath() else {
            throw llmError(tr("模型正在下载，暂时无法删除。"))
        }
        try FileManager.default.trashItem(at: model.directory, resultingItemURL: nil)
        refresh()
    }
}
