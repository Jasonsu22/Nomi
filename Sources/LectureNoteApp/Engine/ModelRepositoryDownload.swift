import CryptoKit
import Foundation

struct ModelDownloadProgress: Sendable {
    var completed: Int64 = 0
    var total: Int64 = 0
    var file = ""
    var verifying = false
    var fraction: Double { total > 0 ? min(1, Double(completed) / Double(total)) : 0 }
}

enum ModelRepositoryDownload {
    private struct Repository: Decodable {
        struct File: Decodable, Sendable {
            struct LFS: Decodable, Sendable { var sha256: String }
            var rfilename: String
            var size: Int64
            var lfs: LFS?
        }
        var sha: String
        var siblings: [File]
    }

    static func download(_ model: LocalModelDefinition, progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws {
        let manager = FileManager.default
        let staging = LocalModelDefinition.root.appendingPathComponent(".nomi-downloads/\(model.id)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        let url = URL(string: "https://huggingface.co/api/models/\(model.repository)/revision/\(model.revision)?blobs=true")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try check(response)
        let repository = try JSONDecoder().decode(Repository.self, from: data)
        guard repository.sha == model.revision else { throw failure(tr("模型版本不匹配，请重试。")) }
        let files = repository.siblings.filter { file in
            let name = file.rfilename
            return !name.contains("/") && !name.contains("\\") && !name.hasPrefix(".")
                && (name.hasSuffix(".safetensors") || name.hasSuffix(".json")
                    || ["merges.txt", "chat_template.jinja", "README.md", "LICENSE", "LICENSE.txt"].contains(name))
        }
        guard !files.isEmpty else { throw failure(tr("模型仓库没有可下载的文件。")) }
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        let remaining = files.reduce(Int64(0)) { sum, file in
            sum + (fileSize(staging.appendingPathComponent(file.rfilename)) == file.size ? 0 : file.size)
        }
        if let available = try? staging.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           available < remaining + 256_000_000 {
            throw failure(tr("磁盘空间不足，无法下载这个模型。"))
        }
        var completed: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let destination = staging.appendingPathComponent(file.rfilename)
            if fileSize(destination) != file.size {
                let baseline = completed
                let transfer = ModelFileTransfer(destination: destination) { count in
                    progress(.init(completed: baseline + count, total: total, file: file.rfilename))
                }
                let url = URL(string: "https://huggingface.co/\(model.repository)/resolve/\(model.revision)/\(file.rfilename)")!
                try await transfer.download(url)
            }
            progress(.init(completed: completed + file.size, total: total, file: file.rfilename, verifying: true))
            do {
                try await Task.detached(priority: .utility) {
                    guard fileSize(destination) == file.size else { throw failure(tr("模型文件下载不完整，请重试。")) }
                    if let expected = file.lfs?.sha256 {
                        let handle = try FileHandle(forReadingFrom: destination)
                        defer { try? handle.close() }
                        var digest = SHA256()
                        while let block = try handle.read(upToCount: 4 * 1024 * 1024), !block.isEmpty {
                            digest.update(data: block)
                        }
                        guard digest.finalize().map({ String(format: "%02x", $0) }).joined() == expected else {
                            throw failure(tr("模型文件校验失败，请重试。"))
                        }
                    }
                }.value
            } catch {
                try? manager.removeItem(at: destination)
                throw error
            }
            completed += file.size
            progress(.init(completed: completed, total: total, file: file.rfilename))
        }
        try Task.checkCancellation()
        guard LocalModelFiles.isComplete(model, at: staging) else {
            throw failure(tr("模型文件不完整或架构不受支持。"))
        }
        let receipt = Dictionary(uniqueKeysWithValues: files.map { ($0.rfilename, $0.size) })
        try JSONEncoder().encode(receipt).write(to: staging.appendingPathComponent(".nomi-model.json"), options: .atomic)
        try Data(model.revision.utf8).write(to: staging.appendingPathComponent(".nomi-revision"), options: .atomic)
        var backup: URL?
        if manager.fileExists(atPath: model.directory.path) {
            let url = staging.deletingLastPathComponent().appendingPathComponent("\(model.id)-backup-\(UUID().uuidString)")
            try manager.moveItem(at: model.directory, to: url)
            backup = url
        }
        do {
            try manager.moveItem(at: staging, to: model.directory)
        } catch {
            if let backup { try? manager.moveItem(at: backup, to: model.directory) }
            throw error
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    fileprivate static func check(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw failure(trf("下载失败（HTTP %d）。请检查网络后重试。", code))
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Nomi.ModelDownload", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private final class ModelFileTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let progress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var fileError: (any Error)?
    private var cancelled = false
    private var receivedFile = false
    private var lastProgressReport: TimeInterval = 0

    init(destination: URL, progress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func download(_ url: URL) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                lock.lock()
                defer { lock.unlock() }
                guard !cancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 86_400
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.downloadTask(with: url)
                self.task = task
                task.resume()
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            let task = self.task
            self.lock.unlock()
            task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date.timeIntervalSinceReferenceDate
        lock.lock()
        let shouldReport = now - lastProgressReport >= 0.1 || totalBytesWritten == totalBytesExpectedToWrite
        if shouldReport { lastProgressReport = now }
        lock.unlock()
        guard shouldReport else { return }
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock()
        defer { lock.unlock() }
        do {
            guard !cancelled else { throw CancellationError() }
            guard let response = downloadTask.response else { throw URLError(.badServerResponse) }
            try ModelRepositoryDownload.check(response)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            receivedFile = true
        } catch { fileError = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let resultError = cancelled ? CancellationError() : (error ?? fileError ?? (receivedFile ? nil : URLError(.badServerResponse)))
        self.task = nil
        self.session = nil
        lock.unlock()
        session.finishTasksAndInvalidate()
        if let resultError { continuation?.resume(throwing: resultError) }
        else { continuation?.resume() }
    }
}
