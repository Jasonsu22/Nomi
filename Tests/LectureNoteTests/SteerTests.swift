import Foundation
import Testing
@testable import LectureNoteApp

struct SteerTests {
    @MainActor @Test func steeringStopsThisChatsAnswerAndHoldsTheMessage() async {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        let chat = UUID()
        model.chatGeneratingID = chat
        let running = Task<Void, Never> { try? await Task.sleep(for: .seconds(30)) }
        model.chatTask = running
        #expect(model.steer("换个角度讲", images: [], chatID: chat))
        #expect(running.isCancelled)
        #expect(model.pendingSteer?.text == "换个角度讲")
        #expect(model.queued(in: chat).isEmpty)
    }

    @MainActor @Test func steeringAnotherChatsAnswerQueuesInstead() {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        model.chatGeneratingID = UUID()
        let mine = UUID()
        #expect(model.steer("问题", images: [], chatID: mine))
        #expect(model.pendingSteer == nil)
        #expect(model.queued(in: mine).map(\.text) == ["问题"])
    }

    @MainActor @Test func aSteerThatArrivesAsTheAnswerFinishesGoesFirstInTheQueue() {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        let chat = UUID()
        model.enqueue("早先排队的", images: [], chatID: chat)
        model.pendingSteer = QueuedPrompt(chatID: chat, text: "打断的", images: [])
        model.chatDidEnd(chat, succeeded: true)
        #expect(model.pendingSteer == nil)
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
