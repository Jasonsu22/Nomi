import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import OSLog
import SwiftUI

@MainActor
@Observable
final class LocalEngine: TranscriptionEngine {
    let transcript = LiveTranscript()
    let level = LevelMeter()
    let session = SessionState()

    private(set) var loadError: String?
    private(set) var readiness: EngineReadiness = .preparing
    private(set) var modelStatus: LocalModelRuntimeStatus?
    private(set) var isChangingModel = false
    private(set) var isGenerating = false
    var sourceLanguage = "zh"
    var targetLanguage = "en"
    var inputDeviceUID: String?
    var recordingURL: URL?
    var onFinished: (@MainActor ([Paragraph], TimeInterval) -> Void)?
    private static let logger = Logger(subsystem: "local.nomi.preview", category: "Engine")

    var canStart: Bool {
        process?.isRunning == true && session.phase == .idle && !isChangingModel && !isGenerating && (readiness == .ready || readiness == .sourceOnly)
    }

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var lifetimePipe: Pipe?
    @ObservationIgnored private var logHandle: FileHandle?
    @ObservationIgnored private var shuttingDown = false
    @ObservationIgnored private var restartAttempts = 0
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var launchID = UUID()
    @ObservationIgnored private var stdout = Data()
    @ObservationIgnored private var port: Int?
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var receiveTask: Task<Void, Never>?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var recordingID = UUID()
    @ObservationIgnored private let microphone = MicrophoneCapture()
    @ObservationIgnored private let sendGate = SendGate()

    static func launchIfAvailable() -> LocalEngine? {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return nil }
        let engine = LocalEngine()
        engine.launch()
        return engine
    }

    func start(resuming paragraphs: [Paragraph] = [], at offset: TimeInterval = 0) {
        guard canStart else { return }
        loadError = nil
        transcript.setSourceLanguage(sourceLanguage)
        transcript.reset(keeping: paragraphs, at: offset)
        session.begin(at: offset)
        recordingID = UUID()
        let id = recordingID
        openTask?.cancel()
        openTask = Task { await openSession(id: id) }
    }

    func stop() {
        guard session.phase == .preparing || session.phase == .listening else { return }
        sendGate.closeGate()
        openTask?.cancel()
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
        try? lifetimePipe?.fileHandleForWriting.close()
        try? logHandle?.close()
    }

    func shutdown() {
        shuttingDown = true
        restartTask?.cancel()
        openTask?.cancel()
        stopTask?.cancel()
        receiveTask?.cancel()
        sendGate.closeGate()
        microphone.stop()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        // EOF tells the bundled engine to stop its entire private process group.
        try? lifetimePipe?.fileHandleForWriting.close()
        lifetimePipe = nil
        try? logHandle?.close()
        logHandle = nil
    }

    private func launch() {
        guard let url = Self.binaryURL() else {
            readiness = .unavailable
            loadError = tr("引擎没有启动")
            return
        }
        readiness = .preparing
        loadError = nil
        stdout = Data()
        port = nil
        token = nil
        launchID = UUID()
        let id = launchID
        let process = Process()
        process.executableURL = url
        process.currentDirectoryURL = url.deletingLastPathComponent()
        process.arguments = [
            "--managed-by-app",
            "--port", "0",
            "--asr-model", LocalModelDefinition.selected(for: .asr).directory.path,
            "--llm-model", LocalModelDefinition.selected(for: .translator).directory.path,
            "--assistant-model", LocalModelDefinition.selected(for: .assistant).directory.path,
        ]
        let output = Pipe()
        let lifetime = Pipe()
        lifetimePipe = lifetime
        process.standardInput = lifetime
        process.standardOutput = output
        logHandle = Self.openLog()
        process.standardError = logHandle ?? FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            Task { @MainActor in
                guard let self, self.launchID == id, !self.shuttingDown else { return }
                self.consume(data)
            }
        }
        process.terminationHandler = { [weak self] terminated in
            let pid = terminated.processIdentifier
            Task { @MainActor in
                self?.backendExited(pid: pid)
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            try? lifetime.fileHandleForWriting.close()
            lifetimePipe = nil
            readiness = .unavailable
            loadError = tr("引擎没有启动")
        }
    }

    private func backendExited(pid: Int32) {
        guard !shuttingDown, process?.processIdentifier == pid else { return }
        process = nil
        port = nil
        token = nil
        modelStatus = nil
        try? lifetimePipe?.fileHandleForWriting.close()
        lifetimePipe = nil
        try? logHandle?.close()
        logHandle = nil
        readiness = .unavailable
        loadError = tr("引擎没有启动")
        if session.phase != .idle {
            finish(duration: session.phase == .stopping ? session.elapsed : session.beginStopping())
        }
        guard restartAttempts < 1 else { return }
        restartAttempts += 1
        readiness = .preparing
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, !self.shuttingDown else { return }
            self.launch()
        }
    }

    private static func openLog() -> FileHandle? {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Nomi")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("engine.log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try? FileHandle(forWritingTo: url)
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
            guard self.port == port, self.token == token, !shuttingDown else { return }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                readiness = .unavailable
                return
            }
            let status = try JSONDecoder().decode(LocalModelRuntimeStatus.self, from: data)
            apply(status)
        } catch {
            guard self.port == port, self.token == token, !shuttingDown else { return }
            readiness = .unavailable
        }
    }

    private func apply(_ status: LocalModelRuntimeStatus) {
        modelStatus = status
        guard status.asr.loaded else {
            readiness = status.asr.files == "missing" ? .asrMissing : .unavailable
            if readiness == .unavailable { loadError = tr("识别模型没有加载") }
            return
        }
        loadError = nil
        readiness = status.translator.loaded ? .ready : .sourceOnly
    }

    func selectModel(_ model: LocalModelDefinition, for role: LocalModelRole) async throws {
        guard session.phase == .idle, !isChangingModel, let port, let token else {
            throw NSError(domain: "Nomi.Models", code: 1, userInfo: [NSLocalizedDescriptionKey: tr("引擎还没准备好")])
        }
        isChangingModel = true
        defer { isChangingModel = false }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/models/select")!, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["role": role.rawValue, "path": model.directory.path])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                let message = String(data: data, encoding: .utf8) ?? tr("模型加载失败，请重试。")
                throw NSError(domain: "Nomi.Models", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
            }
            let status = try JSONDecoder().decode(LocalModelRuntimeStatus.self, from: data)
            apply(status)
            guard status.model(for: role)?.loaded == true else {
                throw NSError(domain: "Nomi.Models", code: 3, userInfo: [NSLocalizedDescriptionKey: tr("模型加载失败，请重试。")])
            }
        } catch {
            await refreshStatus()
            throw error
        }
    }

    func unloadModel(at path: URL) async throws {
        let data = try await modelRequest(path: "models/unload-path", body: ["path": path.path])
        apply(try JSONDecoder().decode(LocalModelRuntimeStatus.self, from: data))
    }

    func generate(system: String, prompt: String) async throws -> String {
        guard session.phase == .idle, !isGenerating, !isChangingModel else { throw llmError(tr("请等待录制或本地模型操作结束。")) }
        isGenerating = true
        defer { isGenerating = false }
        let data = try await modelRequest(path: "assistant/generate", body: ["system": system, "prompt": prompt, "max_tokens": 2048])
        struct Reply: Decodable { var text: String; var status: LocalModelRuntimeStatus }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        apply(reply.status)
        guard !reply.text.isEmpty else { throw llmError(tr("模型未返回文字，请重试。")) }
        return reply.text
    }

    private func modelRequest(path: String, body: [String: Any]) async throws -> Data {
        guard let port, let token else { throw llmError(tr("引擎还没准备好")) }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/\(path)")!, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw llmError(String(data: data, encoding: .utf8) ?? tr("本地模型请求失败。"))
        }
        return data
    }

    private func openSession(id: UUID) async {
        let allowed = await Self.requestMicrophone()
        guard !Task.isCancelled, recordingID == id, session.phase == .preparing else { return }
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
            guard recordingID == id, !Task.isCancelled else { return }
            failStart(tr("连接转录服务失败"))
            return
        }
        guard !Task.isCancelled, recordingID == id, session.phase == .preparing else {
            socket.cancel(with: .goingAway, reason: nil)
            return
        }
        receive()
        microphone.onSamples = { [weak self] data, rms in
            Task { @MainActor in
                guard let self, self.recordingID == id else { return }
                self.forward(data, rms: rms)
            }
        }
        microphone.onFailure = { [weak self] message in
            Task { @MainActor in
                guard let self, self.recordingID == id, self.session.phase == .listening || self.session.phase == .preparing else { return }
                self.loadError = message
                self.stop()
            }
        }
        if let recordingURL {
            do {
                microphone.recorder = try AudioFileRecorder(url: recordingURL, gate: sendGate)
            } catch {
                // Transcription still works without the audio file.
                Self.logger.error("Could not create audio file: \(String(describing: error), privacy: .public)")
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
        level.recordMicrophoneRMS(rms)
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
                    guard !Task.isCancelled, self.socket === socket, !self.shuttingDown else { return }
                    self.loadError = tr("连接转录服务失败")
                    self.finish(duration: self.session.phase == .stopping ? self.session.elapsed : self.session.beginStopping())
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
            // The local microphone drives the meter; inference replies can lag.
            break
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
        openTask?.cancel()
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
        openTask?.cancel()
        receiveTask?.cancel()
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
        var candidates: [URL?] = [
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("moxin-engine"),
        ]
        #if DEBUG
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates += [
            ProcessInfo.processInfo.environment["NOMI_ENGINE"].map { URL(fileURLWithPath: $0) },
            project.appendingPathComponent("Backend/target/debug/moxin-engine"),
        ]
        #endif
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
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

/// Installed outside the main actor. `AVAudioNodeTapBlock` is non-Sendable, and a
/// closure created on the main actor crashes when Core Audio calls it.
private func installMicrophoneTap(on input: AVAudioInputNode, format: AVAudioFormat, processor: MicrophonePCMProcessor) {
    // format: nil keeps the node's previous graph rate. After setDeviceID that
    // rate no longer matches the hardware, and engine.start() fails with -10868.
    input.installTap(onBus: 0, bufferSize: 1600, format: format) { buffer, _ in
        processor.convert(buffer)
    }
}

@MainActor
private final class MicrophoneCapture {
    var onSamples: (@Sendable (Data, Double) -> Void)?
    var onFailure: (@Sendable (String) -> Void)?
    /// Survives device-change restarts of the capture engine; released by `stop()`.
    var recorder: AudioFileRecorder?
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var watchdog: Task<Void, Never>?
    private static let logger = Logger(subsystem: "local.nomi.preview", category: "AudioInput")

    func start(deviceUID: String?) throws {
        stopCapture()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let deviceID: AudioDeviceID
        if let deviceUID {
            guard let device = AudioHardware.inputs().first(where: { $0.id == deviceUID }) else {
                throw MicrophoneError.unavailable
            }
            deviceID = device.deviceID
        } else {
            deviceID = AudioHardware.defaultInputID()
        }
        guard deviceID != 0 else { throw MicrophoneError.unavailable }
        // Avoid reconfiguring an already selected device, which can stop the I/O unit.
        if input.auAudioUnit.deviceID != deviceID {
            try input.auAudioUnit.setDeviceID(deviceID)
        }
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw MicrophoneError.unavailable }
        let processor = MicrophonePCMProcessor(onSamples: onSamples, onFailure: onFailure, recorder: recorder)
        // The tap block is non-Sendable, so a closure formed on the main actor is
        // isolated there. The audio thread then traps in swift_task_checkIsolated.
        installMicrophoneTap(on: input, format: format, processor: processor)
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            Self.logger.error("Microphone failed to start: \(String(describing: error), privacy: .public)")
            throw error
        }
        self.engine = engine
        Self.logger.info("Microphone started: device=\(deviceID), rate=\(format.sampleRate), channels=\(format.channelCount)")
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self, weak engine] _ in
            Task { @MainActor in
                guard let self, let engine, self.engine === engine, !engine.isRunning else { return }
                do {
                    try self.start(deviceUID: deviceUID)
                } catch {
                    self.onFailure?(tr("音频设备连接已改变，请重新选择输入源。"))
                }
            }
        }
        watchdog = Task { [weak self, weak engine] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, let engine, self.engine === engine, !processor.hasReceivedAudio else { return }
            Self.logger.error("Microphone started but did not deliver PCM buffers")
            self.onFailure?(tr("麦克风未收到音频数据，请重新选择输入源。"))
        }
    }

    func stop() {
        stopCapture()
        recorder?.close()
        recorder = nil
    }

    private func stopCapture() {
        watchdog?.cancel()
        watchdog = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
    }
}

private final class MicrophonePCMProcessor: @unchecked Sendable {
    private let onSamples: (@Sendable (Data, Double) -> Void)?
    private let onFailure: (@Sendable (String) -> Void)?
    private let recorder: AudioFileRecorder?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var reportedFailure = false
    private let lock = NSLock()
    private var receivedAudio = false

    var hasReceivedAudio: Bool {
        lock.lock()
        defer { lock.unlock() }
        return receivedAudio
    }

    init(onSamples: (@Sendable (Data, Double) -> Void)?, onFailure: (@Sendable (String) -> Void)?, recorder: AudioFileRecorder?) {
        self.onSamples = onSamples
        self.onFailure = onFailure
        self.recorder = recorder
    }

    func convert(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { fail(); return }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate)) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { fail(); return }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, status != .error else { fail(); return }
        recorder?.write(converted)
        guard let channel = converted.floatChannelData?.pointee else { return }
        let count = Int(converted.frameLength)
        guard count > 0 else { return }
        lock.lock()
        receivedAudio = true
        lock.unlock()
        var energy = 0.0
        for index in 0..<count {
            let sample = Double(channel[index])
            energy += sample * sample
        }
        onSamples?(Data(bytes: channel, count: count * MemoryLayout<Float>.size), (energy / Double(count)).squareRoot())
    }

    private func fail() {
        guard !reportedFailure else { return }
        reportedFailure = true
        onFailure?(tr("音频格式转换失败，请重新开始录音。"))
    }
}

private enum MicrophoneError: Error {
    case unavailable
}

/// Encodes the 16 kHz mono stream to AAC on the tap thread. Writes are skipped
/// while the gate is closed, so paused time is not in the file.
private final class AudioFileRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private let gate: SendGate
    private var failed = false

    fileprivate init(url: URL, gate: SendGate) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        self.gate = gate
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        guard gate.isOpen else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let file, !failed else { return }
        do { try file.write(from: buffer) } catch { failed = true }
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        file?.close()
        file = nil
    }
}
