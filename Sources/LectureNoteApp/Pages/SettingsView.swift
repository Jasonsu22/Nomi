import AppKit
import AVFoundation
import SwiftUI

struct SettingsView: View {
    var model: AppModel
    @AppStorage(InterfaceLanguage.key) private var interfaceLanguage = InterfaceLanguage.system.rawValue
    @AppStorage(InterfaceAppearance.key) private var appearance = InterfaceAppearance.system.rawValue
    @AppStorage(MicrophonePrompt.key) private var microphonePrompt = MicrophonePrompt.ask.rawValue

    var body: some View {
        PageScaffold(title: tr("设置")) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    VStack(spacing: 0) {
                        settingRow(tr("界面语言")) {
                            valueMenu(
                                selection: $interfaceLanguage,
                                options: InterfaceLanguage.allCases.map { ($0.rawValue, $0.title) }
                            )
                        }
                        divider
                        settingRow(tr("外观")) {
                            valueMenu(
                                selection: $appearance,
                                options: InterfaceAppearance.allCases.map { ($0.rawValue, $0.title) }
                            )
                        }
                        divider
                        settingRow(tr("麦克风权限")) {
                            valueMenu(
                                selection: $microphonePrompt,
                                options: MicrophonePrompt.allCases.map { ($0.rawValue, $0.title) }
                            )
                            .onChange(of: microphonePrompt) { _, value in
                                guard value == MicrophonePrompt.allow.rawValue else { return }
                                Task { await allowMicrophoneNow() }
                            }
                        }
                    }
                    .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                    LocalModelsSection(model: model)
                    LLMSettingsSection(model: model)
                    SearchSettingsSection(model: model)
                        .id("search-settings")
                    PromptSettingsSection(model: model)
                }
                .pageColumn(maxWidth: 760)
                .padding(.bottom, Space.s7)
            }
            .onAppear { revealSearch(proxy) }
            .onChange(of: model.revealSearchSettings) { _, _ in revealSearch(proxy) }
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

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(AppFont.body).foregroundStyle(AppColor.textPrimary)
            Spacer()
            content()
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
    }

    private func valueMenu(selection: Binding<String>, options: [(value: String, title: String)]) -> some View {
        let current = options.first { $0.value == selection.wrappedValue }?.title ?? ""
        return Picker("", selection: selection) {
            ForEach(options, id: \.value) { option in
                Text(option.title).tag(option.value)
            }
        }
        .labelsHidden()
        .font(AppFont.secondary)
        .clickCursor()
        .selectedTextPickerWidth(current)
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

    private var divider: some View {
        Rectangle().fill(AppColor.separator).frame(height: 1).padding(.leading, Space.s4)
    }
}

private func requestMicrophoneAccess() async -> Bool {
    await withCheckedContinuation { continuation in
        AVAudioApplication.requestRecordPermission { granted in
            continuation.resume(returning: granted)
        }
    }
}
