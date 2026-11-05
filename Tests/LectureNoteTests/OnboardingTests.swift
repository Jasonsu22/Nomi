import Foundation
import Testing
@testable import LectureNoteApp

struct OnboardingTests {
    @MainActor @Test func aProfileBoundInTheGuideAnswersAndCancellingChangesNothing() {
        let model = AppModel(engine: ReplayEngine(), meetings: [], categories: [])
        model.llmConfiguration.setMode(.local)
        let previous = model.llmConfiguration.activeID

        // Cancel: the editor closes without saving, so the student stays on the local model.
        model.useProfileFromOnboarding(UUID())
        #expect(model.llmConfiguration.mode == .local)
        #expect(model.llmConfiguration.activeID == previous)

        // Loopback needs no key, so this saves without touching the Keychain.
        let profile = LLMAPIProfile(providerID: "ollama", name: "Ollama", baseURL: "http://localhost:11434/v1", modelID: "test-model")
        defer {
            try? model.llmConfiguration.delete(profile)
            model.llmConfiguration.setMode(.local)
        }
        #expect(throws: Never.self) { try model.llmConfiguration.save(profile, key: "") }
        model.useProfileFromOnboarding(profile.id)
        #expect(model.llmConfiguration.mode == .api)
        #expect(model.llmConfiguration.activeID == profile.id)
    }
}
