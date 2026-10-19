import Foundation
import Testing
@testable import LectureNoteApp

struct SearchClientTests {
    @Test func parsersReadTheThreeFields() throws {
        let tavily = Data(#"{"results":[{"title":"Nomi","url":"https://example.com/a","content":"A note"}]}"#.utf8)
        let exa = Data(#"{"results":[{"title":"Exa hit","url":"https://exa.ai/b","highlights":["first","second"]}]}"#.utf8)
        let searx = Data(#"{"results":[{"title":"Local","url":"http://127.0.0.1/c","content":"page"}]}"#.utf8)

        #expect(try SearchClient.hits(vendor: .tavily, data: tavily) == [SearchHit(title: "Nomi", url: "https://example.com/a", snippet: "A note")])
        #expect(try SearchClient.hits(vendor: .exa, data: exa).first?.snippet == "first")
        #expect(try SearchClient.hits(vendor: .searxng, data: searx).first?.url == "http://127.0.0.1/c")
    }

    @Test func parsersSkipResultsWithoutAnHTTPURLAndKeepFive() throws {
        let json = Data(#"{"results":[{"title":"no","url":"ftp://x"},{"title":"yes","url":"https://ok.example"}]}"#.utf8)
        let hits = try SearchClient.hits(vendor: .tavily, data: json)
        #expect(hits.count == 1)
        #expect(hits[0].title == "yes")
    }

    @Test func searxngForbiddenUsesTheJSONHint() {
        let message = SearchClient.failureMessage(vendor: .searxng, status: 403, data: Data("secret-key".utf8), key: "secret-key")
        #expect(message == tr("这台 SearXNG 没有打开 JSON。在它的设置里把 json 加进 search.formats。"))
    }

    @Test func otherFailuresRedactTheKey() {
        let message = SearchClient.failureMessage(vendor: .tavily, status: 401, data: Data(#"{"error":"bad tvly-secret"}"#.utf8), key: "tvly-secret")
        #expect(message.contains("••••"))
        #expect(!message.contains("tvly-secret"))
    }

    @Test func searchAddressRejectsUserInfoQueryAndFragment() throws {
        #expect(try SearchURL.normalize("http://127.0.0.1:8080/") == "http://127.0.0.1:8080")
        #expect(throws: (any Error).self) { try SearchURL.normalize("http://user:pass@127.0.0.1:8080") }
        #expect(throws: (any Error).self) { try SearchURL.normalize("https://example.com/search?q=1") }
        #expect(throws: (any Error).self) { try SearchURL.normalize("https://example.com/search#top") }
        #expect(throws: (any Error).self) { try SearchURL.normalize("ftp://example.com") }
    }

    @Test func webPassageKeepsItsURLAndDoesNotDuplicateTheRawLink() {
        let blocks = [ContextBlock(title: "Nomi", detail: "example.com", body: "text\nhttps://example.com/a", url: "https://example.com/a")]
        let found = ChatContext.citations(in: "See [1] and https://example.com/a.", blocks: blocks)
        #expect(found.count == 1)
        #expect(found[0].url == "https://example.com/a")
        #expect(found[0].detail == "example.com")
    }

    @Test func webPromptDoesNotTellTheModelToSearchByItself() {
        let system = ChatContext.systemPrompt(language: "English", allowsWeb: true, hasPassages: true)
        #expect(system.contains("Do not invent URLs"))
        #expect(!system.contains("You may search the web"))
    }

    @MainActor
    @Test func providerMarksLoad() {
        let files = [
            "provider-openai", "provider-anthropic", "provider-gemini", "provider-deepseek",
            "provider-kimi", "provider-groq", "provider-nvidia", "provider-zhipu",
            "provider-ollama", "provider-qwen", "search-tavily", "search-exa",
            "search-searxng",
        ]
        for file in files {
            #expect(ProviderLogo.image(named: file) != nil, "\(file)")
        }
        #expect(ProviderLogo.image(named: nil) == nil)
    }
}
