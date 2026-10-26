import Foundation

/// The first-start guide: shown once, and again whenever the speech model is missing and the
/// student asks for it from the top bar or Help.
enum OnboardingPreference {
    static let key = "lecturenote.onboardingDone"
    static var done: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

extension AppModel {
    /// Macs under 16 GB get the lighter models; they run faster and leave room for other apps.
    static var prefersLightModels: Bool { ProcessInfo.processInfo.physicalMemory < 16 * 1_073_741_824 }

    func recommendedModel(for role: LocalModelRole) -> LocalModelDefinition {
        let light = role == .asr ? "qwen3-asr-0.6b" : "Qwen3.5-0.8B-MLX-4bit"
        let id = Self.prefersLightModels ? light : role.defaultID
        return LocalModelDefinition.catalog.first { $0.id == id } ?? LocalModelDefinition.selected(for: role)
    }

    /// The other size offered next to the recommendation.
    func alternativeModel(for role: LocalModelRole) -> LocalModelDefinition? {
        let pair = role == .asr ? ["qwen3-asr-1.7b", "qwen3-asr-0.6b"] : ["Qwen3.5-2B-MLX-4bit", "Qwen3.5-0.8B-MLX-4bit"]
        let recommended = recommendedModel(for: role).id
        return LocalModelDefinition.catalog.first { pair.contains($0.id) && $0.id != recommended }
    }

    /// Downloads a model if needed, then loads it as soon as the engine can take it.
    func downloadAndUse(_ item: LocalModelDefinition, for role: LocalModelRole) {
        localModels.rememberSelection(item, for: role)
        if !localModels.installed.contains(item.id) { localModels.download(item) }
        Task { [weak self] in
            while let self, !Task.isCancelled {
                if self.localModels.errors[item.id] != nil { return }
                if self.localModels.installed.contains(item.id), self.canSwitchModels { break }
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self else { return }
            let loaded = (self.engine as? LocalEngine)?.modelStatus?.model(for: role)
            if loaded?.loaded == true, loaded?.path == item.directory.path { return }
            await self.selectLocalModel(item, for: role)
        }
    }

    func finishOnboarding(startTour: Bool) {
        OnboardingPreference.done = true
        onboardingPresented = false
        if startTour { startTutorial() }
    }
}
