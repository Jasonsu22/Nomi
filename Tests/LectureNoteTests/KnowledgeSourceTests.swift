import AppKit
import Foundation
import Testing
@testable import LectureNoteApp

struct KnowledgeSourceTests {
    @Test func filterByCategoryAndQuery() {
        let course = UUID()
        let other = UUID()
        let sources = [
            sample("Assignment.pdf", categoryID: course),
            sample("Lecture slides", categoryID: other),
            sample("Scratch notes", categoryID: nil),
        ]
        #expect(sources.matching(query: "assign", filter: .all).map(\.title) == ["Assignment.pdf"])
        #expect(sources.matching(query: "", filter: .category(course)).count == 1)
        #expect(sources.matching(query: "", filter: .uncategorized).map(\.title) == ["Scratch notes"])
        #expect(sources.matching(query: "notes", filter: .category(course)).isEmpty)
    }

    @Test func droppedFileURLReadsFinderPayload() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("nomi-drop-test.txt")
        try Data("hello".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(fileURL(fromDroppedItem: file)?.path == file.path)
        #expect(fileURL(fromDroppedItem: file.absoluteString)?.path == file.path)
        #expect(fileURL(fromDroppedItem: Data(file.absoluteString.utf8))?.path == file.path)
        #expect(fileURL(fromDroppedItem: "https://example.com") == nil)

        let board = NSPasteboard(name: NSPasteboard.Name("nomi-drop-test"))
        board.clearContents()
        #expect(board.writeObjects([file as NSURL]))
        #expect(fileURLs(on: board).map(\.path) == [file.path])
        board.clearContents()
    }

    private func sample(_ title: String, categoryID: UUID?) -> KnowledgeSource {
        KnowledgeSource(
            id: UUID(),
            title: title,
            fileName: title,
            categoryID: categoryID,
            importedAt: .now,
            fileModifiedAt: .now,
            byteCount: 1
        )
    }
}
