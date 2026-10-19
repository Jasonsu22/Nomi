import Foundation

struct KnowledgeSource: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var title: String
    var fileName: String
    var categoryID: UUID?
    var importedAt: Date
    var fileModifiedAt: Date
    var byteCount: Int64
}

extension Array where Element == KnowledgeSource {
    func matching(query: String, filter: CategoryFilter) -> [KnowledgeSource] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return self.filter { source in
            let inCategory: Bool
            switch filter {
            case .all:
                inCategory = true
            case .uncategorized:
                inCategory = source.categoryID == nil
            case .category(let id):
                inCategory = source.categoryID == id
            }
            guard inCategory else { return false }
            guard !needle.isEmpty else { return true }
            return source.title.localizedStandardContains(needle)
        }
    }
}
