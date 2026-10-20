import Foundation
import Testing

struct LocalizationTests {
    /// One malformed line makes macOS ignore the whole file, and every string falls back to Chinese.
    @Test func englishCatalogParses() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/LectureNoteApp/Resources/en.lproj/Localizable.strings")
        let data = try Data(contentsOf: file)
        let table = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        #expect((table?.count ?? 0) > 100)
        #expect(table?["设置"] == "Settings")
    }

    @Test func englishCatalogCoversInterfaceKeys() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/LectureNoteApp")
        let catalog = try String(
            contentsOf: sources.appendingPathComponent("Resources/en.lproj/Localizable.strings"),
            encoding: .utf8
        )
        let keys = Set(catalogKeys(in: catalog))
        let interfaceKey = #/trf?\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"/#
        var missing: [String] = []
        guard let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            Issue.record("打不开源码目录")
            return
        }
        while let file = enumerator.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") { continue }
                for match in line.matches(of: interfaceKey) {
                    let key = String(match.1)
                    if !keys.contains(key) {
                        missing.append("\(file.lastPathComponent): \(key)")
                    }
                }
            }
        }
        #expect(missing.isEmpty, "英文文案缺这些键：\(missing.sorted())")
    }

    private func catalogKeys(in text: String) -> [String] {
        let catalogKey = #/^"((?:[^"\\]|\\.)*)"\s*=/#
        return text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("/*") else { return nil }
            return trimmed.firstMatch(of: catalogKey).map { String($0.1) }
        }
    }
}
