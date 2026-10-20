import Foundation
import Testing
@testable import LectureNoteApp

struct ContextBudgetTests {
    @Test func localModelsGetTheSmallBudgetAndAPIModelsTheLargeOne() {
        #expect(ContextBudget.current(mode: .local, profile: nil) == .local)
        #expect(ContextBudget.current(mode: .api, profile: LLMAPIProfile(modelID: "m")) == .api)
        #expect(ContextBudget.api.scope > ContextBudget.local.scope)
        #expect(ContextBudget.api.history > ContextBudget.local.history)
    }

    @Test func aProfileWithASmallWindowScalesEveryPartDown() {
        var profile = LLMAPIProfile(modelID: "small")
        profile.contextCharacters = ContextBudget.apiReference / 4
        let budget = ContextBudget.current(mode: .api, profile: profile)
        #expect(budget.scope == ContextBudget.api.scope / 4)
        #expect(budget.history == ContextBudget.api.history / 4)
        // Never below a quarter of the local budget, however small the window.
        profile.contextCharacters = 100
        let tiny = ContextBudget.current(mode: .api, profile: profile)
        #expect(tiny.scope == ContextBudget.local.scope / 4)
    }

    @Test func profilesWithoutTheFieldStillLoadAndTheFieldRoundTrips() throws {
        let old = #"{"id":"5F0D6A6E-6D36-4D5B-9C61-3A1D2B9F7E10","name":"Old","baseURL":"https://x.test/v1","modelID":"m"}"#
        let decoded = try JSONDecoder().decode(LLMAPIProfile.self, from: Data(old.utf8))
        #expect(decoded.contextCharacters == nil)
        var profile = decoded
        profile.contextCharacters = 32_000
        let again = try JSONDecoder().decode(LLMAPIProfile.self, from: JSONEncoder().encode(profile))
        #expect(again.contextCharacters == 32_000)
    }

    @Test func packRespectsASmallerBudget() {
        let blocks = (0..<10).map { ContextBlock(title: "Lecture", detail: "\($0)", body: String(repeating: "量子", count: 500), meetingID: nil, sourceID: nil, url: nil) }
        let packed = ChatContext.pack(blocks, question: "量子", budget: 3_000)
        #expect(packed.reduce(0) { $0 + $1.body.count } <= 3_000)
        #expect(!packed.isEmpty)
    }
}
