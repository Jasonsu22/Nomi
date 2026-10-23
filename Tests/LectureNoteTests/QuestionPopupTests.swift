import Foundation
import Testing
@testable import LectureNoteApp

/// The live Q&A pop-up: one card at a time, and what each choice does to the question.
@MainActor
struct QuestionPopupTests {
    private func model(autoAnswer: Bool, questions count: Int) -> (AppModel, UUID, [UUID]) {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        let meeting = UUID()
        let state = model.qa(for: meeting)
        state.autoAnswer = autoAnswer
        state.questions = (0..<count).map { index in
            MeetingQuestion(text: "Question \(index)?", quote: "Question \(index)?", at: Double(index * 30), status: .waiting)
        }
        return (model, meeting, state.questions.map(\.id))
    }

    private func status(_ model: AppModel, _ meeting: UUID, _ id: UUID) -> MeetingQuestion.Status? {
        model.qa(for: meeting).questions.first { $0.id == id }?.status
    }

    @Test func popupsShowOneAtATimeInOrderAndNeverTwiceForOneQuestion() {
        let (model, meeting, ids) = model(autoAnswer: false, questions: 2)
        model.showQuestionPopup(QuestionPopup(meetingID: meeting, questionID: ids[0]))
        model.showQuestionPopup(QuestionPopup(meetingID: meeting, questionID: ids[1]))
        model.showQuestionPopup(QuestionPopup(meetingID: meeting, questionID: ids[1]))
        #expect(model.questionPopup?.questionID == ids[0])
        #expect(model.questionPopupQueue.map(\.questionID) == [ids[1]])
        model.answerPopupQuestionLater()
        #expect(model.questionPopup?.questionID == ids[1])
        model.closeQuestionPopup()
        #expect(model.questionPopup == nil)
    }

    @Test func laterLeavesTheQuestionWaitingInTheQATab() {
        let (model, meeting, ids) = model(autoAnswer: true, questions: 1)
        model.showQuestionPopup(QuestionPopup(meetingID: meeting, questionID: ids[0]))
        model.answerPopupQuestionLater()
        #expect(status(model, meeting, ids[0]) == .waiting)
        #expect(model.questionPopup == nil)
    }

    @Test func answerNowQueuesItFirstAndKeepsTheCardOpen() {
        let (model, meeting, ids) = model(autoAnswer: false, questions: 1)
        model.showQuestionPopup(QuestionPopup(meetingID: meeting, questionID: ids[0]))
        model.answerPopupQuestionNow()
        #expect(model.urgentQuestionID == ids[0])
        #expect(model.questionPopup?.answering == true)
        #expect(status(model, meeting, ids[0]) != .waiting)
    }

    @Test func aPopupLeftAloneFollowsAutoAnswer() {
        let (on, meetingOn, idsOn) = model(autoAnswer: true, questions: 1)
        on.showQuestionPopup(QuestionPopup(meetingID: meetingOn, questionID: idsOn[0]))
        on.questionPopupTimedOut()
        #expect(status(on, meetingOn, idsOn[0]) != .waiting)

        let (off, meetingOff, idsOff) = model(autoAnswer: false, questions: 1)
        off.showQuestionPopup(QuestionPopup(meetingID: meetingOff, questionID: idsOff[0]))
        off.questionPopupTimedOut()
        #expect(status(off, meetingOff, idsOff[0]) == .waiting)
        #expect(off.questionPopup == nil)
    }

    @Test func endingTheRecordingSettlesEveryCardLikeLeavingItAlone() {
        let (model, meeting, ids) = model(autoAnswer: false, questions: 2)
        model.showQuestionPopup(QuestionPopup(meetingID: meeting, questionID: ids[0]))
        model.showQuestionPopup(QuestionPopup(meetingID: meeting, questionID: ids[1]))
        model.settleQuestionPopups()
        #expect(model.questionPopup == nil)
        #expect(model.questionPopupQueue.isEmpty)
        #expect(ids.allSatisfy { status(model, meeting, $0) == .waiting })
    }

    /// A question whose meeting is gone used to be retried in a tight loop that froze the app.
    @Test func aQuestionThatCannotStartStopsTheQueueInsteadOfSpinning() async {
        let (model, meeting, ids) = model(autoAnswer: true, questions: 1)
        model.askQuestion(ids[0], in: meeting)
        for _ in 0..<50 where model.questionQueueTask != nil {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.questionQueueTask == nil)
    }
}

