import Foundation
import Observation

struct MeetingAssistantAnswer: Identifiable {
    var id = UUID()
    var question: String
    var answer: String
    var modelName: String
}

@MainActor
@Observable
final class MeetingAssistantState {
    var answers: [MeetingAssistantAnswer] = []
    var summary: String?
    var summaryModelName = ""
    var isGenerating = false
    var generatingSummary = false
    var error: String?
    @ObservationIgnored var task: Task<Void, Never>?
}
