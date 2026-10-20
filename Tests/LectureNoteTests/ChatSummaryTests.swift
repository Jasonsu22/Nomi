import Foundation
import Testing
@testable import LectureNoteApp

struct ChatSummaryTests {
    private func turns(_ count: Int, answerLength: Int = 900) -> [ChatTurn] {
        (0..<count).map { index in
            ChatTurn(
                question: "第 \(index) 个问题",
                answer: "第 \(index) 个回答。" + String(repeating: "解释。", count: answerLength / 3),
                modelName: "m",
                createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index) * 60)
            )
        }
    }

    private func summary(through turn: ChatTurn, covered: Int) -> ChatSummary {
        ChatSummary(text: "讨论了量子比特。", throughTurnID: turn.id, throughDate: turn.createdAt, coveredTurns: covered, modelName: "m", updatedAt: .now)
    }

    @Test func shortChatsAreNeverSummarized() {
        #expect(ChatSummaries.pending(turns(5, answerLength: 5_000), summary: nil, budget: .local) == nil)
    }

    @Test func olderTurnsThatNoLongerFitAreSummarizedInOrder() throws {
        let chat = turns(12)
        let pending = try #require(ChatSummaries.pending(chat, summary: nil, budget: .local))
        #expect(pending.first?.id == chat[0].id)
        let window = ChatHistory.window(chat, budget: .local)
        #expect(pending.allSatisfy { !window.includedTurns.contains($0.id) })
        #expect(pending.count == 12 - window.includedTurns.count)
    }

    @Test func coveredTurnsAreNotSummarizedAgainUntilEnoughNewOnesPile_up() {
        let chat = turns(12)
        let window = ChatHistory.window(chat, budget: .local)
        let oldestShown = chat.firstIndex { window.includedTurns.contains($0.id) } ?? 0
        let covered = summary(through: chat[oldestShown - 1], covered: oldestShown)
        #expect(ChatSummaries.pending(chat, summary: covered, budget: .local) == nil)
    }

    @Test func theWindowShowsTheSummaryAndDoesNotCountCoveredTurnsAsHidden() {
        let chat = turns(12)
        let plain = ChatHistory.window(chat, budget: .local)
        let oldestShown = chat.firstIndex { plain.includedTurns.contains($0.id) } ?? 0
        let covered = summary(through: chat[oldestShown - 1], covered: oldestShown)
        let window = ChatHistory.window(chat, budget: .local, summary: covered)
        #expect(window.text.hasPrefix("Summary of earlier conversation"))
        #expect(window.text.contains("讨论了量子比特。"))
        #expect(window.omittedOlderTurns <= max(0, chat.count - window.includedTurns.count - oldestShown))
        #expect(window.text.count <= ContextBudget.local.history + 100)
    }

    @Test func aChatWithOnlyASummaryStillGetsIt() {
        let only = ChatHistory.window([], budget: .local, summary: summary(through: turns(1)[0], covered: 1))
        #expect(only.text.contains("讨论了量子比特。"))
    }

    @Test func oldChatsLoadAndSummariesRoundTrip() throws {
        let old = #"{"id":"0B7C8A4E-3C1F-4C55-9A2D-2E3F4A5B6C7D","title":"旧对话","turns":[]}"#
        var chat = try JSONDecoder().decode(ChatSession.self, from: Data(old.utf8))
        #expect(chat.summary == nil)
        let first = turns(1)[0]
        chat.summary = summary(through: first, covered: 1)
        let again = try JSONDecoder().decode(ChatSession.self, from: JSONEncoder().encode(chat))
        #expect(again.summary?.throughTurnID == first.id)
        #expect(again.summary?.text == "讨论了量子比特。")
    }

    @Test func emptyRepliesAreRejectedAndLongOnesTrimmed() {
        #expect(ChatSummaries.cleaned("   ", limit: 600) == nil)
        let long = ChatSummaries.cleaned(String(repeating: "要点。", count: 600), limit: 600)
        #expect((long?.count ?? 0) <= 600)
    }

    @Test func aChatSummaryIsSearchable() {
        let chat = turns(2)
        let documents = LibrarySearch.chatDocuments(id: UUID(), title: "t", turns: chat, summary: summary(through: chat[0], covered: 1))
        #expect(documents.count == 3)
        #expect(documents.first?.body.contains("讨论了量子比特。") == true)
    }

    @Test func thePromptCarriesTheEarlierSummaryAndTheNewTurns() {
        let chat = turns(3, answerLength: 30)
        let prompt = ChatSummaries.prompt(previous: summary(through: chat[0], covered: 1), turns: Array(chat[1...]), budget: .local)
        #expect(prompt.contains("讨论了量子比特。"))
        #expect(prompt.contains("第 1 个问题"))
        #expect(prompt.contains("第 2 个问题"))
        #expect(ChatSummaries.system(language: "Simplified Chinese", limit: 600).contains("600"))
    }
}
