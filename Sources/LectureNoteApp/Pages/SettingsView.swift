import AppKit
import AVFoundation
import SwiftUI

struct SettingsView: View {
    var model: AppModel
    @AppStorage(InterfaceLanguage.key) private var interfaceLanguage = InterfaceLanguage.system.rawValue
    @AppStorage(InterfaceAppearance.key) private var appearance = InterfaceAppearance.system.rawValue
    @AppStorage(MicrophonePrompt.key) private var microphonePrompt = MicrophonePrompt.ask.rawValue

    var body: some View {
        PageScaffold(title: tr("设置"), columnWidth: PageColumnLayout.narrowWidth) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s6) {
                    SettingsSection(tr("通用")) {
                        SettingsRow(tr("界面语言")) {
                            SettingsPopUp(
                                selection: $interfaceLanguage,
                                options: InterfaceLanguage.allCases.map { ($0.rawValue, $0.title) }
                            )
                        }
                        SettingsRow(tr("外观")) {
                            SettingsPopUp(
                                selection: $appearance,
                                options: InterfaceAppearance.allCases.map { ($0.rawValue, $0.title) }
                            )
                        }
                    }
                    LocalModelsSection(model: model) {
                        SettingsRow(tr("麦克风权限")) {
                            SettingsPopUp(
                                selection: $microphonePrompt,
                                options: MicrophonePrompt.allCases.map { ($0.rawValue, $0.title) }
                            )
                            .onChange(of: microphonePrompt) { _, value in
                                guard value == MicrophonePrompt.allow.rawValue else { return }
                                Task { await allowMicrophoneNow() }
                            }
                        }
                    }
                    LLMSettingsSection(model: model)
                    SearchSettingsSection(model: model)
                        .id("search-settings")
                    PromptSettingsSection(model: model)
                    MemorySettingsSection(model: model)
                        .id("memory-settings")
                }
                .pageColumn(maxWidth: PageColumnLayout.narrowWidth)
                .padding(.bottom, Space.s7)
            }
            .onAppear {
                revealSearch(proxy)
                revealMemory(proxy)
            }
            .onChange(of: model.revealSearchSettings) { _, _ in revealSearch(proxy) }
            .onChange(of: model.revealMemorySettings) { _, _ in revealMemory(proxy) }
            }
        }
    }

    private func revealSearch(_ proxy: ScrollViewProxy) {
        guard model.revealSearchSettings else { return }
        Task { @MainActor in
            proxy.scrollTo("search-settings", anchor: .top)
            model.revealSearchSettings = false
        }
    }

    private func revealMemory(_ proxy: ScrollViewProxy) {
        guard model.revealMemorySettings else { return }
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo("memory-settings", anchor: .top) }
            model.revealMemorySettings = false
        }
    }

    private func allowMicrophoneNow() async {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            openMicrophoneSettings()
        default:
            let granted = await requestMicrophoneAccess()
            if !granted { openMicrophoneSettings() }
        }
    }

    private func openMicrophoneSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
        ]
        for raw in candidates {
            guard let url = URL(string: raw), NSWorkspace.shared.open(url) else { continue }
            return
        }
    }
}

private func requestMicrophoneAccess() async -> Bool {
    await withCheckedContinuation { continuation in
        AVAudioApplication.requestRecordPermission { granted in
            continuation.resume(returning: granted)
        }
    }
}
