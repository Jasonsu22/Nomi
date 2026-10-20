import Foundation

/// How much text one request may carry, in characters, for the model it goes to.
///
/// Characters rather than tokens: Chinese costs about one token per 1–1.5 characters and
/// English about one per 3–4, so a character budget is close for Chinese and safe for English,
/// without a tokenizer. A small local model reads long prompts slowly; API models have room.
struct ContextBudget: Equatable, Sendable {
    /// Earlier turns of the current chat, its running summary included.
    var history: Int
    /// The longest single earlier answer kept whole; longer ones keep their start and end.
    var turnAnswer: Int
    /// Meetings and files picked in the scope chip.
    var scope: Int
    /// One library search's results.
    var library: Int
    /// The transcript sent with a question or summary in a meeting's side panel.
    var sidePanelTranscript: Int

    static let local = ContextBudget(history: 6_000, turnAnswer: 1_500, scope: 16_000, library: 9_000, sidePanelTranscript: 18_000)
    static let api = ContextBudget(history: 24_000, turnAnswer: 6_000, scope: 60_000, library: 24_000, sidePanelTranscript: 90_000)

    /// The characters `api` is sized for. A profile's `contextCharacters` scales it from here.
    static let apiReference = 120_000

    static func current(mode: LLMMode, profile: LLMAPIProfile?) -> ContextBudget {
        guard mode == .api else { return .local }
        guard let size = profile?.contextCharacters, size > 0 else { return .api }
        return api.scaled(by: Double(size) / Double(apiReference))
    }

    /// Every part scaled together, never below a quarter of the local budget.
    func scaled(by factor: Double) -> ContextBudget {
        func part(_ value: Int, floor: Int) -> Int { max(floor / 4, Int(Double(value) * factor)) }
        return ContextBudget(
            history: part(history, floor: Self.local.history),
            turnAnswer: part(turnAnswer, floor: Self.local.turnAnswer),
            scope: part(scope, floor: Self.local.scope),
            library: part(library, floor: Self.local.library),
            sidePanelTranscript: part(sidePanelTranscript, floor: Self.local.sidePanelTranscript)
        )
    }
}
