import Foundation
import Testing
@testable import LectureNoteApp

struct ChatHistoryTests {
    private func turn(_ question: String, _ answer: String, minutes: Double = 0, error: String? = nil) -> ChatTurn {
        ChatTurn(question: question, answer: answer, modelName: "m", createdAt: Date(timeIntervalSince1970: 1_800_000_000 + minutes * 60), error: error)
    }

    private func numberedList(_ count: Int) -> String {
        (1...count).map { "\($0). 第 \($0) 点：" + String(repeating: "这里是比较长的解释内容。", count: 12) }.joined(separator: "\n")
    }

    @Test func aLongAnswerKeepsItsStartAndItsEndAtSentenceBreaks() {
        let answer = "总的来说，量子计算靠叠加和干涉工作。\n" + numberedList(8) + "\n最后记住：测量只会得到一个结果。"
        let cleaned = ChatHistory.cleanedAnswer(answer, limit: 600)
        #expect(cleaned.count <= 600)
        #expect(cleaned.hasPrefix("总的来说"))
        #expect(cleaned.hasSuffix("测量只会得到一个结果。"))
        #expect(cleaned.contains("…"))
    }

    @Test func aDemoPageBecomesOneLine() {
        let page = "```html\n<!DOCTYPE html><html><head><title>火箭升空</title></head><body>" + String(repeating: "<div></div>", count: 400) + "</body></html>\n```"
        let cleaned = ChatHistory.cleanedAnswer("看下面的演示。\n\n" + page + "\n\n点击发射。", limit: 1_500)
        #expect(cleaned.contains("[交互演示：火箭升空]"))
        #expect(!cleaned.contains("<div>"))
        #expect(cleaned.contains("点击发射。"))
    }

    @Test func codeThatIsNotAPageStays() {
        let cleaned = ChatHistory.cleanedAnswer("```swift\nlet x = 1\n```", limit: 1_500)
        #expect(cleaned.contains("let x = 1"))
    }

    @Test func toolMarkersAreNotRepeatedToTheModel() {
        let cleaned = ChatHistory.cleanedAnswer("<tool name=\"web_search\">量子</tool>量子比特可以叠加。", limit: 1_500)
        #expect(!cleaned.contains("<tool"))
        #expect(cleaned.contains("量子比特可以叠加。"))
    }

    @Test func theWindowFillsTheBudgetNewestFirstAndSkipsErrors() {
        var turns = (0..<10).map { turn("问题 \($0)", numberedList(10), minutes: Double($0)) }
        turns.insert(turn("坏掉的", "", minutes: 9.5, error: "失败"), at: 10)
        let budget = ContextBudget.local
        let window = ChatHistory.window(turns, budget: budget)
        #expect(window.text.count <= budget.history + 40)
        #expect(window.includedTurns.contains(turns[9].id))
        #expect(!window.includedTurns.contains(turns[0].id))
        #expect(!window.includedTurns.contains(turns[10].id))
        #expect(window.omittedOlderTurns == 10 - window.includedTurns.count)
        // Oldest shown first, so the conversation reads in order.
        let first = window.text.range(of: "问题 \(10 - window.includedTurns.count)")
        let last = window.text.range(of: "问题 9")
        #expect(first != nil && last != nil && first!.lowerBound < last!.lowerBound)
    }

    @Test func theNewestTurnIsAlwaysShownEvenWhenItIsHuge() {
        let huge = turn("请详细解释", String(repeating: "很长的回答内容。", count: 3_000))
        let window = ChatHistory.window([huge], budget: .local)
        #expect(window.includedTurns == [huge.id])
        #expect(window.text.count <= ContextBudget.local.history + 80)
    }

    @Test func turnsAreDatedUnlessAskedNotTo() {
        let only = turn("你好", "你好！")
        #expect(ChatHistory.window([only], budget: .local).text.contains("Question: 你好"))
        #expect(ChatHistory.window([only], budget: .local).text.contains("] Question:"))
        #expect(!ChatHistory.window([only], budget: .local, dated: false).text.contains("] Question:"))
    }

    @Test func aFollowUpCanReachTheSeventhPoint() {
        let list = turn("量子计算有哪些要点？", numberedList(8))
        let window = ChatHistory.window([list], budget: .api)
        #expect(window.text.contains("7. 第 7 点"))
    }

    @Test func thePromptSaysWhenOlderTurnsAreHidden() {
        let window = HistoryWindow(text: "Previous conversation (reference only):\nQuestion: a\nAnswer: b", includedTurns: [], omittedOlderTurns: 5)
        let prompt = ChatContext.userPrompt(question: "c", history: window, blocks: [], mentionsLibrary: true)
        #expect(prompt.contains("5 earlier turns"))
        #expect(prompt.contains("search_library"))
        let quiet = ChatContext.userPrompt(question: "c", history: .empty, blocks: [])
        #expect(!quiet.contains("earlier turns"))
    }
}
