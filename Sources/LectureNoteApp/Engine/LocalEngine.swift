import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import SwiftUI

@MainActor
@Observable
final class LocalEngine: TranscriptionEngine {
    let transcript = LiveTranscript()
    let level = LevelMeter()
    let session = SessionState()

    private(set) var loadError: String?
    private(set) var readiness: EngineReadiness = .preparing
    var sourceLanguage = "zh"
    var targetLanguage = "en"
    var inputDeviceUID: String?
    var onFinished: (@MainActor ([Paragraph], TimeInterval) -> Void)?

    var canStart: Bool {
        session.phase == .idle && loadError == nil && (readiness == .ready || readiness == .sourceOnly)
    }

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var stdout = Data()
    @ObservationIgnored private var port: Int?
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var receiveTask: Task<Void, Never>?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private let microphone = MicrophoneCapture()
    @ObservationIgnored private let sendGate = SendGate()

    static func launchIfAvailable() -> LocalEngine? {
        guard binaryURL() != nil else { return nil }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return nil }
        let engine = LocalEngine()
        engine.launch()
        return engine
    }

    func start() {
        guard canStart else { return }
        loadError = nil
        transcript.setSourceLanguage(sourceLanguage)
        transcript.reset()
        session.begin()
        Task { await openSession() }
    }

    func stop() {
        guard session.phase == .preparing || session.phase == .listening else { return }
        sendGate.closeGate()
        microphone.stop()
        let duration = session.beginStopping()
        level.rms = 0
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            await self?.sendText(#"{"type":"stop"}"#)
            try? await Task.sleep(for: .seconds(45))
            guard let self, self.session.phase == .stopping else { return }
            self.finish(duration: duration)
        }
    }

    func togglePause() {
        guard session.phase == .listening else { return }
        withAnimationIfNeeded {
            session.togglePause()
        }
        if session.isPaused {
            sendGate.closeGate()
            level.rms = 0
        } else {
            sendGate.openGate()
        }
    }

    deinit {
        process?.terminate()
    }

    private func launch() {
        guard let url = Self.binaryURL() else {
            readiness = .unavailable
            return
        }
        let process = Process()
        process.executableURL = url
        process.arguments = ["--port", "0"]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.consume(data)
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.port == nil else { return }
                self.readiness = .unavailable
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            readiness = .unavailable
            loadError = tr("引擎没有启动")
        }
    }

    private func consume(_ data: Data) {
        stdout.append(data)
        guard port == nil, let newline = stdout.firstIndex(of: 10) else { return }
        let line = stdout.prefix(upTo: newline)
        stdout.removeSubrange(..<stdout.index(after: newline))
        guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { return }
        port = object["port"] as? Int
        token = object["token"] as? String
        Task { await refreshStatus() }
    }

    private func refreshStatus() async {
        guard let port, let token else { return }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/status")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                readiness = .unavailable
                return
            }
            let status = try JSONDecoder().decode(EngineStatus.self, from: data)
            apply(status)
        } catch {
            readiness = .unavailable
        }
    }

    private func apply(_ status: EngineStatus) {
        guard status.asr.loaded else {
            readiness = status.asr.files == "missing" ? .asrMissing : .unavailable
            if readiness == .unavailable { loadError = tr("识别模型没有加载") }
            return
        }
        loadError = nil
        readiness = status.translator.loaded ? .ready : .sourceOnly
    }

    private func openSession() async {
        let allowed = await Self.requestMicrophone()
        guard session.phase == .preparing else { return }
        guard allowed else {
            loadError = tr("没有麦克风权限")
            session.markIdle()
            onFinished?([], 0)
            return
        }
        guard let port, let token,
              let url = URL(string: "ws://127.0.0.1:\(port)/v1/session") else {
            failStart(tr("引擎还没准备好"))
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        let start = """
        {"type":"start","source":"microphone","sourceLanguage":"\(sourceLanguage)","targetLanguage":"\(targetLanguage)"}
        """
        do {
            try await socket.send(.string(start))
        } catch {
            failStart(tr("连接转录服务失败"))
            return
        }
        receive()
        microphone.onSamples = { [weak self] data, rms in
            Task { @MainActor in
                self?.forward(data, rms: rms)
            }
        }
        do {
            try microphone.start(deviceUID: inputDeviceUID)
            sendGate.openGate()
        } catch {
            failStart(tr("打不开麦克风"))
        }
    }

    private func forward(_ data: Data, rms: Double) {
        guard sendGate.isOpen, session.phase == .preparing || session.phase == .listening else { return }
        level.rms = rms
        socket?.send(.data(data)) { _ in }
    }

    private func receive() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let socket = self.socket else { return }
                do {
                    let message = try await socket.receive()
                    if case .string(let text) = message {
                        self.handle(text)
                    }
                } catch {
                    return
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONDecoder().decode(EngineEvent.self, from: data) else { return }
        let reduce = ReduceMotion.system
        switch event.type {
        case "state":
            switch event.value {
            case "listening":
                if session.phase == .preparing {
                    withAnimationIfNeeded { session.markListening() }
                }
            case "idle":
                finish(duration: session.phase == .stopping ? session.elapsed : session.beginStopping())
            default:
                break
            }
        case "tail":
            let text = event.text ?? ""
            guard !text.isEmpty else { break }
            transcript.applyTail(text: text, start: event.start ?? 0, reduceMotion: reduce)
        case "commit":
            let commit = Commit(
                id: event.id ?? 0,
                source: event.source ?? "",
                translation: event.translation ?? "",
                start: event.start ?? 0,
                end: event.end ?? 0
            )
            transcript.applyCommit(commit, tail: event.tail ?? "", reduceMotion: reduce)
        case "level":
            if sendGate.isOpen { level.rms = event.rms ?? 0 }
        case "error":
            if event.code == "asr_missing" {
                readiness = .asrMissing
                failStart(tr("缺少识别模型"))
            }
        default:
            break
        }
    }

    private func finish(duration: TimeInterval) {
        guard session.phase != .idle else { return }
        stopTask?.cancel()
        sendGate.closeGate()
        microphone.stop()
        transcript.flush(at: duration, reduceMotion: ReduceMotion.system)
        let paragraphs = transcript.paragraphs
        withAnimationIfNeeded { session.markIdle() }
        level.rms = 0
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        receiveTask?.cancel()
        onFinished?(paragraphs, duration)
    }

    private func failStart(_ message: String) {
        loadError = message
        sendGate.closeGate()
        microphone.stop()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session.markIdle()
        onFinished?([], 0)
    }

    private func sendText(_ text: String) async {
        try? await socket?.send(.string(text))
    }

    private func withAnimationIfNeeded(_ updates: () -> Void) {
        withAnimation(Motion.morph(ReduceMotion.system), updates)
    }

    private static func requestMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        default:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private static func binaryURL() -> URL? {
        let candidates = [
            ProcessInfo.processInfo.environment["NOMI_ENGINE"].map { URL(fileURLWithPath: $0) },
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("moxin-engine"),
            URL(fileURLWithPath: "/Users/jason/Projects/LectureNote/Moxin-Voice/target/debug/moxin-engine"),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private struct EngineStatus: Decodable {
    struct Model: Decodable {
        var files: String
        var loaded: Bool
    }

    var asr: Model
    var translator: Model
}

private struct EngineEvent: Decodable {
    var type: String
    var value: String?
    var text: String?
    var start: Double?
    var id: Int?
    var source: String?
    var translation: String?
    var end: Double?
    var tail: String?
    var rms: Double?
    var code: String?
}

private final class SendGate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false

    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return open
    }

    func openGate() {
        lock.lock()
        open = true
        lock.unlock()
    }

    func closeGate() {
        lock.lock()
        open = false
        lock.unlock()
    }
}

private final class MicrophoneCapture: @unchecked Sendable {
    var onSamples: (@Sendable (Data, Double) -> Void)?
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?

    func start(deviceUID: String?) throws {
        let input = engine.inputNode
        if let deviceUID {
            guard var device = AudioHardware.inputs().first(where: { $0.id == deviceUID })?.deviceID,
                  let unit = input.audioUnit else { throw MicrophoneError.unavailable }
            let result = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard result == noErr else { throw MicrophoneError.unavailable }
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target) else {
            throw MicrophoneError.unavailable
        }
        self.converter = converter
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1600, format: format) { [weak self] buffer, _ in
            self?.convert(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate) + 32
        guard let converter, let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            return
        }
        var consumed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = converted.floatChannelData?.pointee else { return }
        let count = Int(converted.frameLength)
        guard count > 0 else { return }
        var energy = 0.0
        for index in 0..<count {
            let sample = Double(channel[index])
            energy += sample * sample
        }
        let data = Data(bytes: channel, count: count * MemoryLayout<Float>.size)
        onSamples?(data, (energy / Double(count)).squareRoot())
    }
}

private enum MicrophoneError: Error {
    case unavailable
}
