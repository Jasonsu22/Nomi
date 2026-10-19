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
