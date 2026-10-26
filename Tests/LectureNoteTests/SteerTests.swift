import Foundation
import Testing
@testable import LectureNoteApp

struct SteerTests {
    @MainActor @Test func steeringStopsThisChatsAnswerAndHoldsTheMessage() async {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        let chat = UUID()
        model.chatRuns[chat] = ChatRun(question: "q", images: [], mode: .api)
        let running = Task<Void, Never> { try? await Task.sleep(for: .seconds(30)) }
        model.chatTasks[chat] = running
        #expect(model.steer("换个角度讲", images: [], chatID: chat))
        #expect(running.isCancelled)
        #expect(model.pendingSteers[chat]?.text == "换个角度讲")
        #expect(model.queued(in: chat).isEmpty)
    }

    @MainActor @Test func stoppingOneChatLeavesAnotherAnswering() {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        let first = UUID(), second = UUID()
        let one = Task<Void, Never> { try? await Task.sleep(for: .seconds(30)) }
        let two = Task<Void, Never> { try? await Task.sleep(for: .seconds(30)) }
        model.chatRuns[first] = ChatRun(question: "a", images: [], mode: .api)
        model.chatRuns[second] = ChatRun(question: "b", images: [], mode: .api)
        model.chatTasks[first] = one
        model.chatTasks[second] = two
        model.stopChat(first)
        #expect(one.isCancelled)
        #expect(!two.isCancelled)
        two.cancel()
    }

    @MainActor @Test func aFullLocalModelQueuesOtherChats() {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        model.llmConfiguration.setMode(.local)
        for _ in 0..<LocalEngine.maxReplies {
            model.chatRuns[UUID()] = ChatRun(question: "q", images: [], mode: .local)
        }
        #expect(!model.canStartAnotherAnswer)
        let mine = UUID()
        #expect(model.steer("问题", images: [], chatID: mine))
        #expect(model.pendingSteers[mine] == nil)
        #expect(model.queued(in: mine).map(\.text) == ["问题"])
        model.llmConfiguration.setMode(.api)
        #expect(model.canStartAnotherAnswer)
    }

    @MainActor @Test func aSteerThatArrivesAsTheAnswerFinishesGoesFirstInTheQueue() {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        let chat = UUID()
        model.enqueue("早先排队的", images: [], chatID: chat)
        model.pendingSteers[chat] = QueuedPrompt(chatID: chat, text: "打断的", images: [])
        model.chatDidEnd(chat, succeeded: true)
        #expect(model.pendingSteers[chat] == nil)
        #expect(model.queued(in: chat).map(\.text).first == "打断的")
    }

    @Test func interruptedAnswersAreLabelledForTheModel() {
        var turn = ChatTurn(question: "讲讲量子", answer: "量子比特可以", modelName: "m")
        turn.interrupted = true
        let window = ChatHistory.window([turn], budget: .local)
        #expect(window.text.contains("Answer (interrupted by the student): 量子比特可以"))
    }

    @Test func theSteeredMessageTellsTheModelItInterrupted() {
        let prompt = ChatContext.userPrompt(question: "换个角度", history: .empty, blocks: [], steered: true)
        let note = prompt.range(of: ChatContext.steerNote)
        let question = prompt.range(of: "Question: 换个角度")
        #expect(note != nil && question != nil && note!.lowerBound < question!.lowerBound)
        #expect(!ChatContext.userPrompt(question: "q", history: .empty, blocks: []).contains(ChatContext.steerNote))
    }

    @Test func interruptedTurnsRoundTripAndOldTurnsLoad() throws {
        let old = #"{"id":"3B1C2D3E-4F50-4A6B-8C7D-9E0F1A2B3C4D","question":"q","answer":"a","modelName":"m"}"#
        var turn = try JSONDecoder().decode(ChatTurn.self, from: Data(old.utf8))
        #expect(turn.interrupted == nil)
        turn.interrupted = true
        let again = try JSONDecoder().decode(ChatTurn.self, from: JSONEncoder().encode(turn))
        #expect(again.interrupted == true)
    }

    @MainActor @Test func aStoppedBackgroundReplyIsNotAFailure() {
        #expect(AppModel.isCancellation(CancellationError()))
        #expect(AppModel.isCancellation(URLError(.cancelled)))
        #expect(!AppModel.isCancellation(URLError(.timedOut)))
        #expect(!AppModel.isCancellation(llmError("失败")))
    }
}
