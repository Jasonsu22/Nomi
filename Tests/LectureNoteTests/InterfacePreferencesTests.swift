import Foundation
import Testing
@testable import LectureNoteApp

struct InterfacePreferencesTests {
    @Test func interfaceLanguageFollowsTheSystemUnlessExplicitlySelected() {
        #expect(InterfaceLanguage.resolved("system", preferredLanguages: ["zh-Hant-TW"]) == .chinese)
        #expect(InterfaceLanguage.resolved("system", preferredLanguages: ["en-US"]) == .english)
        #expect(InterfaceLanguage.resolved("system", preferredLanguages: ["fr-FR"]) == .english)
        #expect(InterfaceLanguage.resolved("en", preferredLanguages: ["zh-Hans"]) == .english)
        #expect(InterfaceLanguage.resolved("zh-Hans", preferredLanguages: ["en-US"]) == .chinese)
    }

    @Test func appearanceCanReturnToTheSystem() {
        #expect(InterfaceAppearance.system.colorScheme == nil)
        #expect(InterfaceAppearance.light.colorScheme == .light)
        #expect(InterfaceAppearance.dark.colorScheme == .dark)
    }

    @Test func audioSelectionUsesStableUIDAndDoesNotReplaceADisconnectedDevice() {
        let builtIn = AudioInputDevice(id: "builtin", deviceID: 10, name: "Built-in Microphone")
        let usb = AudioInputDevice(id: "usb", deviceID: 20, name: "USB Microphone")
        #expect(AudioHardware.selected(uid: "system", devices: [builtIn, usb], defaultID: 20) == usb)
        #expect(AudioHardware.selected(uid: "builtin", devices: [builtIn, usb], defaultID: 20) == builtIn)
        #expect(AudioHardware.selected(uid: "usb", devices: [builtIn], defaultID: 10) == nil)
        let reconnected = AudioInputDevice(id: "usb", deviceID: 40, name: "USB Microphone")
        #expect(AudioHardware.selected(uid: "usb", devices: [builtIn, reconnected], defaultID: 10)?.deviceID == 40)
    }
}

@MainActor
struct RecordingConfigurationTests {
    @Test func openingSetupDoesNotRecordAndStartingFreezesTheChosenLanguages() {
        let defaults = UserDefaults.standard
        let source = defaults.object(forKey: LectureLanguages.sourceKey)
        let target = defaults.object(forKey: LectureLanguages.targetKey)
        defer {
            defaults.set(source, forKey: LectureLanguages.sourceKey)
            defaults.set(target, forKey: LectureLanguages.targetKey)
        }
        let engine = RecordingTestEngine()
        let model = AppModel(engine: engine, meetings: [], categories: [])
        model.prepareRecording()
        #expect(model.recordingSetupPresented)
        #expect(engine.starts == 0)
        #expect(model.meetings.isEmpty)
        model.recordingSourceLanguage = "ja"
        model.recordingTargetLanguage = "en"
        model.startTranscription()
        #expect(engine.starts == 1)
        #expect(engine.sourceLanguage == "ja")
        #expect(engine.targetLanguage == "en")
        #expect(engine.inputDeviceUID == model.audioInputs.selectedDevice?.id)
        #expect(model.meetings.first?.sourceLanguage == "ja")
        model.recordingSourceLanguage = "zh"
        #expect(model.meetings.first?.sourceLanguage == "ja")
        #expect(engine.sourceLanguage == "ja")
        #expect(!model.recordingSetupPresented)
    }
}

@MainActor
private final class RecordingTestEngine: TranscriptionEngine {
    let transcript = LiveTranscript()
    let level = LevelMeter()
    let session = SessionState()
    var loadError: String? { nil }
    var readiness: EngineReadiness { .preview }
    var canStart: Bool { session.phase == .idle }
    var sourceLanguage = "zh"
    var targetLanguage = "en"
    var inputDeviceUID: String?
    var onFinished: (@MainActor ([Paragraph], TimeInterval) -> Void)?
    var starts = 0
    func start() { starts += 1; session.begin() }
    func stop() { session.markIdle() }
    func togglePause() {}
}
