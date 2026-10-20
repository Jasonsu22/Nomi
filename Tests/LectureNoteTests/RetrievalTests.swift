import Foundation
import Testing
@testable import LectureNoteApp

struct RetrievalTests {
    private func block(_ body: String, _ detail: String, meeting: UUID? = nil) -> ContextBlock {
        ContextBlock(title: "第三讲", detail: detail, body: body, meetingID: meeting)
    }

    @Test func aTermDeepInALongLectureIsPickedOverCommonCharacters() {
        let meeting = UUID()
        var blocks = (0..<60).map { block("我们今天的课是关于这个学期的安排，这是很重要的，大家要注意。", "\($0)", meeting: meeting) }
        blocks[42] = block("薛定谔方程描述了量子态随时间的演化。", "42", meeting: meeting)
        let packed = ChatContext.pack(blocks, question: "薛定谔方程是什么？", budget: 300)
        #expect(packed.contains { $0.detail == "42" })
        #expect(packed.contains { $0.detail == "41" } && packed.contains { $0.detail == "43" })
        let order = packed.compactMap { Int($0.detail) }
        #expect(order == order.sorted())
    }

    @Test func commonCharactersAloneDoNotDecide() {
        let blocks = [
            block("的是了的是了的是了的是了", "a"),
            block("傅里叶变换把信号分解成频率。", "b"),
        ] + (0..<30).map { block(String(repeating: "填充内容。", count: 20), "f\($0)") }
        let scores = LibrarySearch.relevance(of: blocks.map(\.body), to: "傅里叶变换的是什么")
        #expect(scores[1] > scores[0])
        let packed = ChatContext.pack(blocks, question: "傅里叶变换的是什么", budget: 200)
        #expect(packed.contains { $0.detail == "b" })
    }

    @Test func aBlockThatDoesNotFitIsSkippedNotTheEnd() {
        let blocks = [
            block(String(repeating: "量子", count: 400), "big"),
            block("量子比特。", "small"),
        ]
        let packed = ChatContext.pack(blocks, question: "量子比特", budget: 500)
        #expect(packed.contains { $0.detail == "small" })
    }

    @Test func aFollowUpBorrowsTheTopic() {
        let history = [ChatTurn(question: "什么是量子计算机", answer: "量子计算机……", modelName: "m")]
        let query = ChatContext.searchQuery(question: "那它和经典计算机比呢？", history: history)
        #expect(query?.contains("量子计算机") == true)
        #expect(query?.hasSuffix("那它和经典计算机比呢？") == true)
        let english = ChatContext.searchQuery(question: "How fast is it compared to a laptop?", history: [ChatTurn(question: "What is a quantum computer?", answer: "…", modelName: "m")])
        #expect(english?.contains("quantum computer") == true)
    }

    @Test func aStandaloneQuestionIsSearchedAsIs() {
        let history = [ChatTurn(question: "什么是量子计算机", answer: "……", modelName: "m")]
        #expect(ChatContext.searchQuery(question: "傅里叶变换在信号处理里有什么用", history: history) == "傅里叶变换在信号处理里有什么用")
        #expect(ChatContext.searchQuery(question: "这节课的作业什么时候交", history: history) == "这节课的作业什么时候交")
    }

    @Test func aChainOfFollowUpsKeepsTheOriginalTopic() {
        let history = [
            ChatTurn(question: "什么是量子纠缠", answer: "……", modelName: "m"),
            ChatTurn(question: "那它有什么用？", answer: "……", modelName: "m"),
        ]
        let query = ChatContext.searchQuery(question: "还有呢", history: history)
        #expect(query?.contains("量子纠缠") == true)
    }

    @Test func relevanceIsZeroWithoutSharedTerms() {
        let scores = LibrarySearch.relevance(of: ["量子比特", "傅里叶变换"], to: "量子")
        #expect(scores[0] > 0)
        #expect(scores[1] == 0)
    }
}
