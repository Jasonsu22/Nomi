import Foundation
import Testing
@testable import LectureNoteApp

struct QuestionFinderTests {
    @Test func fillerQuestionsAreNotRealQuestions() {
        for filler in ["对吧？", "是吧？", "好吗？", "懂了吗？", "大家能听到吗？", "这样可以吗？", "是不是？", "Right?", "okay?", "Can you hear me?", "Does that make sense?", "Any questions?", "嗯？", "这个就是注意力，对吧？"] {
            #expect(QuestionFinder.isFiller(filler), "\(filler) should be a filler")
        }
        for real in ["为什么要除以根号 d？", "注意力机制决定了模型看向哪里吗，还是决定输出什么？", "Why do we scale the dot product by the square root of d?", "What happens to the gradient when the softmax saturates?", "什么是动作电位？"] {
            #expect(!QuestionFinder.isFiller(real), "\(real) is a real question")
        }
    }

    @Test func aStretchWithoutQuestionsSkipsTheModel() {
        let statements = [
            QuestionFinder.Line(at: 10, text: "今天我们讲注意力机制。它决定了模型看向哪里。"),
            QuestionFinder.Line(at: 40, text: "你好，你好，能听到吗？Okay. This is good, right?"),
        ]
        #expect(QuestionFinder.candidates(in: statements).isEmpty)

        let asked = statements + [QuestionFinder.Line(at: 70, text: "那么为什么要除以根号 d？我们来看一下。")]
        #expect(QuestionFinder.candidates(in: asked) == ["那么为什么要除以根号 d？"])
    }

    @Test func theModelsListIsFilteredAndTimed() {
        let lines = [QuestionFinder.Line(at: 60, text: "…"), QuestionFinder.Line(at: 300, text: "…")]
        let existing = [MeetingQuestion(text: "为什么注意力要除以根号 d？", quote: "", at: 100, status: .answered)]
        let reply = """
        Here you go:
        {"questions": [
          {"question": "为什么注意力分数要除以根号 d？", "quote": "为什么要除以根号 d", "at": "1:40"},
          {"question": "对吧？", "quote": "对吧", "at": "2:00"},
          {"question": "Softmax 饱和时梯度会怎样？", "quote": "softmax 饱和了会怎么样？", "at": "4:10"},
          {"question": "多头注意力为什么比单头好？", "quote": "为什么要用多个头？", "at": "99:00"},
          {"question": "位置编码解决了什么问题？", "quote": "位置编码是干什么的？", "at": 75}
        ]}
        """
        let found = QuestionFinder.parse(reply, lines: lines, existing: existing, status: .queued)
        // The near duplicate and the filler are dropped; a timestamp past the chunk is held to its end.
        #expect(found.map(\.text) == ["Softmax 饱和时梯度会怎样？", "多头注意力为什么比单头好？", "位置编码解决了什么问题？"])
        #expect(found.map(\.at) == [250, 300, 75])
        #expect(found.allSatisfy { $0.status == .queued })
        #expect(QuestionFinder.parse("no json here", lines: lines, existing: [], status: .waiting).isEmpty)
    }

    @Test func aPassAcceptsAtMostFiveQuestions() {
        let lines = [QuestionFinder.Line(at: 0, text: "…"), QuestionFinder.Line(at: 600, text: "…")]
        let topics = ["梯度消失", "批归一化", "残差连接", "学习率预热", "权重衰减", "早停法", "数据增强"]
        let entries = topics.enumerated().map { #"{"question": "\#($1)是怎么起作用的？", "quote": "", "at": "\#($0):00"}"# }
        let found = QuestionFinder.parse(#"{"questions": [\#(entries.joined(separator: ","))]}"#, lines: lines, existing: [], status: .waiting)
        #expect(found.count == QuestionFinder.perPass)
    }

    @Test func timesAndChunksAreRead() {
        #expect(QuestionFinder.seconds("1:05") == 65)
        #expect(QuestionFinder.seconds("[01:02:03]") == 3723)
        #expect(QuestionFinder.seconds(NSNumber(value: 42)) == 42)
        #expect(QuestionFinder.seconds("soon") == nil)

        let long = (0..<10).map { QuestionFinder.Line(at: TimeInterval($0 * 30), text: String(repeating: "字", count: 1_000)) }
        let chunks = QuestionFinder.chunks(long, limit: 3_000)
        #expect(chunks.count == 4)
        #expect(chunks.flatMap { $0 } == long)
    }

    @Test func theAnswerStartsFromTheMomentItWasAsked() {
        let meeting = UUID()
        let question = MeetingQuestion(text: "为什么要除以根号 d？", quote: "为什么要除以根号 d", at: 600, status: .queued)
        let lines = [0, 400, 500, 600, 700, 900].map { QuestionFinder.Line(at: TimeInterval($0), text: "第 \($0) 秒") }
        let around = QuestionFinder.moment(question, in: lines, meetingID: meeting, title: "Lecture")
        #expect(around.map(\.body) == ["第 500 秒", "第 600 秒", "第 700 秒"])
        #expect(around.allSatisfy { $0.pinned && $0.meetingID == meeting })
        #expect(QuestionFinder.answerQuestion(question).contains("10:00"))
    }
}
