import Foundation
import Observation

struct MeetingAssistantAnswer: Identifiable {
    var id = UUID()
    var question: String
    var answer: String
    var modelName: String
    var createdAt = Date()
}

@MainActor
@Observable
final class MeetingAssistantState {
    var answers: [MeetingAssistantAnswer] = []
    var summary: String?
    var summaryModelName = ""
    var isGenerating = false
    var generatingSummary = false
    var draft = ""
    var error: String?
    @ObservationIgnored var task: Task<Void, Never>?

    init() {}

    /// Picks up where the side panel left off before the app was restarted.
    init(record: MeetingAssistantRecord?) {
        guard let record else { return }
        summary = record.summary
        summaryModelName = record.summaryModelName ?? ""
        answers = record.answers.map {
            MeetingAssistantAnswer(id: $0.id, question: $0.question, answer: $0.answer, modelName: $0.modelName, createdAt: $0.createdAt)
        }
    }
}
