import Foundation
import UniformTypeIdentifiers

struct SourceExportFile: Sendable {
    var sourceURL: URL
    var folder: String
    var fileName: String
}

enum SourceStore {
    static let allowedExtensions: Set<String> = [
        "pdf", "ppt", "pptx", "key", "doc", "docx", "txt", "md", "png", "jpg", "jpeg", "heic",
    ]

    static var allowedTypes: [UTType] {
        var types: [UTType] = [.pdf, .png, .jpeg, .heic, .plainText, .presentation]
        for ext in ["pptx", "ppt", "key", "docx", "doc", "md"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    private static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nomi", isDirectory: true)
    }

    private static var file: URL { root.appendingPathComponent("sources.json") }

    static func directory(for id: UUID) -> URL {
        root.appendingPathComponent("sources/\(id.uuidString)", isDirectory: true)
    }

    static func fileURL(for source: KnowledgeSource) -> URL {
        directory(for: source.id).appendingPathComponent(source.fileName)
    }

    static func accepts(_ url: URL) -> Bool {
        allowedExtensions.contains(url.pathExtension.lowercased())
    }

    static func load() throws -> [KnowledgeSource] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([KnowledgeSource].self, from: Data(contentsOf: file))
    }

    static func save(_ sources: [KnowledgeSource]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(sources).write(to: file, options: .atomic)
    }

    /// Copies the file into the library folder. The caller decides whether to keep the record.
    static func stage(_ url: URL, categoryID: UUID?) throws -> KnowledgeSource {
        guard accepts(url) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let id = UUID()
        let name = safeFileName(url.lastPathComponent)
        let directory = directory(for: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return KnowledgeSource(
            id: id,
            title: name,
            fileName: name,
            categoryID: categoryID,
            importedAt: .now,
            fileModifiedAt: values.contentModificationDate ?? .now,
            byteCount: Int64(values.fileSize ?? 0)
        )
    }

    static func remove(_ source: KnowledgeSource) {
        try? FileManager.default.removeItem(at: directory(for: source.id))
    }

    /// Copies each file into a category folder under `directory`. Same names in one folder get a numeric suffix.
    @discardableResult
    static func exportGrouped(_ files: [SourceExportFile], into directory: URL) throws -> [URL] {
        let accessing = directory.startAccessingSecurityScopedResource()
        defer { if accessing { directory.stopAccessingSecurityScopedResource() } }
        var written: [URL] = []
        var used: Set<String> = []
        for file in files {
            let folder = safeFileName(file.folder)
            let dir = directory.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let destination = uniqueDestination(in: dir, folder: folder, name: safeFileName(file.fileName), used: &used)
            try FileManager.default.copyItem(at: file.sourceURL, to: destination)
            written.append(destination)
        }
        return written
    }

    private static func uniqueDestination(in directory: URL, folder: String, name: String, used: inout Set<String>) -> URL {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var candidate = name
        var number = 2
        while true {
            let key = folder + "/" + candidate.lowercased()
            if !used.contains(key), !FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
                used.insert(key)
                return directory.appendingPathComponent(candidate)
            }
            candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            number += 1
        }
    }

    private static func safeFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "file" : cleaned
    }
}
