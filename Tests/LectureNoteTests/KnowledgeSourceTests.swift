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

    @Test func draggingACategoryTakesTheTargetSlot() {
        let english = category("英语课", 0)
        let math = category("数学课", 1)
        let computer = category("计算机课", 2)
        let other = category("hhh", 5)
        let categories = [other, english, computer, math]

        let toFront = MeetingCategory.placing(categories, moving: computer.id, at: english.id)
        #expect(toFront?.map(\.name) == ["计算机课", "英语课", "数学课", "hhh"])
        #expect(toFront?.map(\.sortOrder) == [0, 1, 2, 3])

        let toEnd = MeetingCategory.placing(categories, moving: english.id, at: other.id)
        #expect(toEnd?.map(\.name) == ["数学课", "计算机课", "hhh", "英语课"])

        let slideLeft = MeetingCategory.placing(categories, moving: other.id, at: math.id)
        #expect(slideLeft?.map(\.name) == ["英语课", "hhh", "数学课", "计算机课"])

        #expect(MeetingCategory.placing(categories, moving: math.id, at: math.id) == nil)
    }

    private func category(_ name: String, _ order: Int) -> MeetingCategory {
        MeetingCategory(id: UUID(), name: name, colorIndex: 0, symbol: "book.closed", sortOrder: order)
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
