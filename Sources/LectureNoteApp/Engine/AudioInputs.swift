import CoreAudio
import Foundation
import SwiftUI

struct AudioInputDevice: Identifiable, Equatable, Sendable {
    var id: String
    var deviceID: AudioDeviceID
    var name: String
}

enum AudioHardware {
    static func inputs() -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { return [] }
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0,
                  let uid = string(id, selector: kAudioDevicePropertyDeviceUID),
                  let name = string(id, selector: kAudioObjectPropertyName) else { return nil }
            return AudioInputDevice(id: uid, deviceID: id, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The Mac's own microphone, used when a chosen device such as an iPhone does not answer.
    static func builtInInput() -> AudioInputDevice? {
        inputs().first { device in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var transport: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device.deviceID, &address, 0, nil, &size, &transport) == noErr
                && transport == kAudioDeviceTransportTypeBuiltIn
        }
    }

    static func defaultInputID() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return 0 }
        return id
    }

    /// The rate the device itself runs its input at. Bluetooth headsets such as AirPods
    /// drop to 24 kHz or 16 kHz once their microphone opens, before AVAudioEngine notices.
    static func inputSampleRate(_ id: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate) == noErr, rate > 0 else { return nil }
        return rate
    }

    static func selected(uid: String, devices: [AudioInputDevice], defaultID: AudioDeviceID) -> AudioInputDevice? {
        uid == AudioInputs.systemDefault ? devices.first { $0.deviceID == defaultID } : devices.first { $0.id == uid }
    }

    private static func string(_ id: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}

private final class AudioDeviceObservation: @unchecked Sendable {
    private let block: AudioObjectPropertyListenerBlock
    private let selectors: [AudioObjectPropertySelector] = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice]

    init(onChange: @escaping @Sendable () -> Void) {
        block = { _, _ in onChange() }
        for selector in selectors {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
    }

    deinit {
        for selector in selectors {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
    }
}

@MainActor
@Observable
final class AudioInputs {
    nonisolated static let systemDefault = "system"
    static let key = "nomi.audioInputUID"
    var selectedUID: String {
        didSet { UserDefaults.standard.set(selectedUID, forKey: Self.key) }
    }
    private(set) var devices: [AudioInputDevice] = []
    private(set) var defaultID: AudioDeviceID = 0
    @ObservationIgnored private var observation: AudioDeviceObservation?

    init() {
        selectedUID = UserDefaults.standard.string(forKey: Self.key) ?? Self.systemDefault
        refresh()
        observation = AudioDeviceObservation { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
    }

    var selectedDevice: AudioInputDevice? {
        AudioHardware.selected(uid: selectedUID, devices: devices, defaultID: defaultID)
    }

    var selectionTitle: String {
        if selectedUID == Self.systemDefault { return tr("系统默认") }
        return selectedDevice?.name ?? tr("设备已断开")
    }

    func refresh() {
        devices = AudioHardware.inputs()
        defaultID = AudioHardware.defaultInputID()
    }
}

struct AudioInputPicker: View {
    @Bindable var inputs: AudioInputs
    var enabled = true
    var fitsSelectedText = false

    var body: some View {
        if fitsSelectedText {
            SettingsPopUp(selection: $inputs.selectedUID, options: options)
                .disabled(!enabled)
                .accessibilityLabel(tr("输入源"))
        } else {
            picker.frame(maxWidth: 300, alignment: .trailing)
        }
    }

    private var options: [(value: String, title: String)] {
        var options = [(AudioInputs.systemDefault, tr("系统默认"))] + inputs.devices.map { ($0.id, $0.name) }
        if inputs.selectedUID != AudioInputs.systemDefault, inputs.selectedDevice == nil {
            options.append((inputs.selectedUID, tr("设备已断开")))
        }
        return options
    }

    private var picker: some View {
        Picker(tr("输入源"), selection: $inputs.selectedUID) {
            Text(tr("系统默认")).tag(AudioInputs.systemDefault)
            ForEach(inputs.devices) { device in
                Text(device.name).tag(device.id)
            }
            if inputs.selectedUID != AudioInputs.systemDefault, inputs.selectedDevice == nil {
                Text(tr("设备已断开")).tag(inputs.selectedUID)
            }
        }
        .labelsHidden()
        .clickCursor()
        .disabled(!enabled)
        .accessibilityLabel(tr("输入源"))
    }
}
