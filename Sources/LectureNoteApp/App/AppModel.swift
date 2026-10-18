import AppKit
import Foundation
import UniformTypeIdentifiers

enum AppPage: String, CaseIterable, Identifiable {
    case meetings
    case ask
    case sources
    case help
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meetings: tr("会议")
        case .ask: tr("提问")
        case .sources: tr("资料")
        case .help: tr("帮助")
        case .settings: tr("设置")
        }
    }

    var symbol: String {
        switch self {
        case .meetings: "calendar"
        case .ask: "text.bubble"
        case .sources: "folder"
        case .help: "questionmark.circle"
        case .settings: "gearshape"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var page: AppPage = .meetings
    var meetings: [Meeting] {
        didSet { schedulePersistence() }
    }
    var categories: [MeetingCategory] {
        didSet { schedulePersistence() }
    }
    var query = "" {
        didSet { scheduleSearch() }
    }
    var filter: CategoryFilter {
        didSet { filter.save() }
    }
    var grouping: MeetingGrouping {
        didSet { grouping.save() }
    }
    var openMeetingID: UUID?
    var exportError: String?
    var storageError: String?
    var searchRequest = 0
    private(set) var appliedQuery = ""
    let engine: any TranscriptionEngine
    let audioInputs = AudioInputs()
    let localModels = LocalModelLibrary()
    let llmConfiguration = LLMConfiguration()
    var assistantStates: [UUID: MeetingAssistantState] = [:]
    var recordingSetupPresented = false
    private(set) var recordingResumeID: UUID?
    var recordingSourceLanguage: String {
        didSet { UserDefaults.standard.set(recordingSourceLanguage, forKey: LectureLanguages.sourceKey) }
    }
    var recordingTargetLanguage: String {
        didSet { UserDefaults.standard.set(recordingTargetLanguage, forKey: LectureLanguages.targetKey) }
    }

    private var liveMeetingID: UUID?
    private var resumedMeetingSnapshot: Meeting?
    private var searchTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var persistenceEnabled = false

    init(engine: (any TranscriptionEngine)? = nil, meetings: [Meeting]? = nil, categories: [MeetingCategory]? = nil) {
        let usesStorage = engine == nil && meetings == nil && categories == nil
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        let stored = usesStorage ? Result { try MeetingStore.load() } : .success(nil)
        let snapshot = try? stored.get()
        let engine = engine ?? LocalEngine.launchIfAvailable() ?? ReplayEngine()
        self.engine = engine
        let pair = LectureLanguages.currentPair()
        recordingSourceLanguage = pair.source
        recordingTargetLanguage = pair.target
        self.meetings = meetings ?? snapshot?.meetings ?? SampleMeetings.make()
        self.categories = categories ?? snapshot?.categories ?? SampleMeetings.categories()
        self.filter = CategoryFilter.load()
        self.grouping = MeetingGrouping.load()
        if case .failure = stored {
            storageError = tr("无法读取本地会议记录，原文件已保留。")
        } else {
            persistenceEnabled = usesStorage
        }
        if case .category(let id) = self.filter, self.category(for: id) == nil {
            self.filter = .all
            self.filter.save()
        }
        engine.onFinished = { [weak self] paragraphs, duration in
            self?.finishLiveMeeting(paragraphs: paragraphs, duration: duration)
        }
    }

    var canStart: Bool { engine.canStart && localModels.deletingID == nil && !assistantIsBusy }

    var canSwitchModels: Bool {
        engine.session.phase == .idle && localModels.switchingID == nil
            && localModels.deletingID == nil && !assistantIsBusy
            && engine.readiness != .preparing && engine is LocalEngine
    }

    func selectLocalModel(_ model: LocalModelDefinition, for requestedRole: LocalModelRole? = nil) async {
        let role = requestedRole ?? model.role
        guard canSwitchModels, let engine = engine as? LocalEngine else { return }
        guard LocalModelFiles.isComplete(model) else {
            localModels.refresh()
            localModels.errors[model.id] = tr("模型文件不完整，请重新下载。")
            return
        }
        localModels.switchingID = model.id
        localModels.switchingRole = role
        localModels.errors[model.id] = nil
        defer { localModels.switchingID = nil; localModels.switchingRole = nil }
        do {
            try await engine.selectModel(model, for: role)
            localModels.rememberSelection(model, for: role)
        } catch {
            localModels.errors[model.id] = error.localizedDescription
        }
    }

    func deleteLocalModel(_ model: LocalModelDefinition) async {
        guard canSwitchModels, let engine = engine as? LocalEngine else { return }
        localModels.deletingID = model.id
        localModels.errors[model.id] = nil
        defer { localModels.deletingID = nil }
        do {
            try await engine.unloadModel(at: model.directory)
            try localModels.trash(model)
        } catch { localModels.errors[model.id] = error.localizedDescription }
    }

    var statusTitle: String {
        switch engine.session.phase {
        case .preparing: return tr("准备中")
        case .listening: return engine.session.isPaused ? tr("已暂停") : tr("正在转录")
        case .stopping: return tr("正在保存")
        case .idle:
            if engine.readiness == .preview, engine.loadError != nil { return tr("示例加载失败") }
            if let loadError = engine.loadError, engine.readiness != .preview { return loadError }
            switch engine.readiness {
            case .preview: return tr("预览 · 示例回放")
            case .preparing: return tr("准备中")
            case .ready: return tr("本机 · 模型就绪")
            case .sourceOnly: return tr("本机 · 只出原文")
            case .asrMissing: return tr("缺少识别模型")
            case .unavailable: return tr("引擎未启动")
            }
        }
    }

    var statusIsLive: Bool {
        engine.session.phase == .listening && !engine.session.isPaused
    }

    var visibleMeetings: [Meeting] {
        meetings.filter { matches($0) }
    }

    func count(in filter: CategoryFilter) -> Int {
        meetings.filter { categoryMatches($0, filter: filter) }.count
    }

    func category(for id: UUID?) -> MeetingCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    func categoryName(for meeting: Meeting) -> String? {
        category(for: meeting.categoryID)?.name
    }

    func select(_ page: AppPage) {
        if page == .meetings, self.page == .meetings {
            openMeetingID = nil
        }
        self.page = page
    }

    var resumableMeeting: Meeting? {
        guard page == .meetings, let openMeetingID else { return nil }
        return meetings.first { $0.id == openMeetingID && !$0.isLive }
    }

    var recordingSetupMeeting: Meeting? {
        meetings.first { $0.id == recordingResumeID }
    }

    var recordingActionTitle: String {
        resumableMeeting == nil ? tr("开始转录") : tr("继续录制")
    }

    func performRecordingAction() {
        if let meeting = resumableMeeting {
            if canRecord {
                resumeTranscription(meeting.id)
            } else {
                prepareRecording(resuming: meeting.id)
            }
        } else {
            prepareRecording()
        }
    }

    func prepareRecording(resuming id: UUID? = nil) {
        guard engine.session.phase == .idle else { return }
        audioInputs.refresh()
        recordingResumeID = id
        recordingSetupPresented = true
    }

    func cancelRecordingSetup() {
        recordingSetupPresented = false
        recordingResumeID = nil
    }

    var canRecord: Bool {
        canStart && (engine.readiness == .preview || audioInputs.selectedDevice != nil)
    }

    func startTranscription(title: String? = nil, categoryID: UUID? = nil, startedAt: Date? = nil) {
        guard canRecord else { return }
        if let id = recordingResumeID, let index = meetings.firstIndex(where: { $0.id == id }) {
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { meetings[index].title = trimmed }
            meetings[index].categoryID = category(for: categoryID)?.id
            if let startedAt { meetings[index].startedAt = startedAt }
            resumeTranscription(id)
            return
        }
        let device = audioInputs.selectedDevice
        var meeting = Meeting.live(sourceLanguage: recordingSourceLanguage, targetLanguage: recordingTargetLanguage, inputDeviceName: device?.name)
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty { meeting.title = trimmedTitle }
        meeting.categoryID = category(for: categoryID)?.id
        if let startedAt { meeting.startedAt = startedAt }
        engine.sourceLanguage = meeting.sourceLanguage
        engine.targetLanguage = meeting.targetLanguage
        engine.inputDeviceUID = device?.id
        recordingSetupPresented = false
        recordingResumeID = nil
        resumedMeetingSnapshot = nil
        meetings.insert(meeting, at: 0)
        liveMeetingID = meeting.id
        openMeetingID = meeting.id
        page = .meetings
        engine.start()
    }

    private func resumeTranscription(_ id: UUID) {
        guard canRecord, let index = meetings.firstIndex(where: { $0.id == id && !$0.isLive }) else { return }
        let saved = meetings[index]
        let offset = max(saved.duration, saved.paragraphs.flatMap(\.commits).map(\.end).max() ?? 0)
        let history = saved.paragraphs.map { paragraph in
            var paragraph = paragraph
            paragraph.sourceLanguage = paragraph.sourceLanguage ?? saved.sourceLanguage
            paragraph.targetLanguage = paragraph.targetLanguage ?? saved.targetLanguage
            return paragraph
        }
        resumedMeetingSnapshot = saved
        let device = audioInputs.selectedDevice
        engine.sourceLanguage = recordingSourceLanguage
        engine.targetLanguage = recordingTargetLanguage
        engine.inputDeviceUID = device?.id
        meetings[index].sourceLanguage = recordingSourceLanguage
        meetings[index].targetLanguage = recordingTargetLanguage
        meetings[index].inputDeviceName = device?.name
        meetings[index].isLive = true
        liveMeetingID = id
        openMeetingID = id
        page = .meetings
        recordingSetupPresented = false
        recordingResumeID = nil
        engine.start(resuming: history, at: offset)
    }

    func stopTranscription() {
        engine.stop()
    }

    func togglePause() {
        engine.togglePause()
    }

    func openMeeting(_ id: UUID) {
        openMeetingID = id
        page = .meetings
    }

    func closeMeeting() {
        openMeetingID = nil
    }

    func rename(id: UUID, to title: String) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        meetings[index].title = title
    }

    func setStartTime(meeting id: UUID, to date: Date) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        meetings[index].startedAt = date
    }

    func shutdown() {
        persistMeetings()
        (engine as? LocalEngine)?.shutdown()
    }

    private func schedulePersistence() {
        guard persistenceEnabled else { return }
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.persistMeetings()
        }
    }

    private func persistMeetings() {
        guard persistenceEnabled else { return }
        persistenceTask?.cancel()
        let saved = meetings.map { meeting in
            guard meeting.id == liveMeetingID else { return meeting }
            var saved = meeting
            saved.paragraphs = engine.transcript.snapshot(at: engine.session.elapsed)
            saved.duration = max(saved.duration, engine.session.elapsed)
            saved.isLive = false
            return saved
        }
        do {
            try MeetingStore.save(.init(meetings: saved, categories: categories))
        } catch {
            storageError = tr("会议保存失败，请导出备份后重试。")
        }
    }

    func assign(meeting id: UUID, category categoryID: UUID?) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        meetings[index].categoryID = categoryID
    }

    func deleteMeeting(_ id: UUID) {
        guard id != liveMeetingID, assistantStates[id]?.isGenerating != true else { return }
        meetings.removeAll { $0.id == id }
        assistantStates[id] = nil
        if openMeetingID == id {
            openMeetingID = nil
        }
    }

    @discardableResult
    func addCategory(name: String, colorIndex: Int, symbol: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let category = MeetingCategory(
            id: UUID(),
            name: trimmed,
            colorIndex: colorIndex,
            symbol: symbol,
            sortOrder: (categories.map(\.sortOrder).max() ?? -1) + 1
        )
        categories.append(category)
        filter = .category(category.id)
        return category.id
    }

    func updateCategory(_ id: UUID, name: String, colorIndex: Int, symbol: String) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        categories[index].name = trimmed
        categories[index].colorIndex = colorIndex
        categories[index].symbol = symbol
    }

    func deleteCategory(_ id: UUID) {
        categories.removeAll { $0.id == id }
        for index in meetings.indices where meetings[index].categoryID == id {
            meetings[index].categoryID = nil
        }
        if case .category(let current) = filter, current == id {
            filter = .uncategorized
        }
    }

    func requestSearch() {
        page = .meetings
        openMeetingID = nil
        searchRequest += 1
    }

    func copyTranscript(_ meeting: Meeting) {
        let text = meeting.paragraphs.map { paragraph in
            let source = paragraph.renderedSource(language: meeting.sourceLanguage)
            let translation = paragraph.renderedTranslation(language: meeting.targetLanguage)
            return translation.isEmpty ? source : "\(source)\n\(translation)"
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func export(_ items: [Meeting]) {
        guard !items.isEmpty else { return }
        let markdown = items.map { $0.markdown(categoryName: categoryName(for: $0)) }.joined(separator: "\n")
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else {
            exportError = tr("找不到窗口，无法打开保存面板。")
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = exportFilename(for: items)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Task { @MainActor in
                    self.exportError = error.localizedDescription
                }
            }
        }
    }

    var activeFilter: CategoryFilter {
        if case .category(let id) = filter, category(for: id) == nil {
            return .all
        }
        return filter
    }

    private func matches(_ meeting: Meeting) -> Bool {
        guard categoryMatches(meeting, filter: activeFilter) else { return false }
        let trimmed = appliedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if meeting.title.localizedStandardContains(trimmed) { return true }
        if let name = categoryName(for: meeting), name.localizedStandardContains(trimmed) { return true }
        return meeting.paragraphs.contains { paragraph in
            paragraph.renderedSource(language: meeting.sourceLanguage).localizedStandardContains(trimmed)
                || paragraph.renderedTranslation(language: meeting.targetLanguage).localizedStandardContains(trimmed)
        }
    }

    private func categoryMatches(_ meeting: Meeting, filter: CategoryFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .uncategorized:
            return meeting.categoryID == nil
        case .category(let id):
            return meeting.categoryID == id
        }
    }

    private func scheduleSearch() {
        let text = query
        searchTask?.cancel()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appliedQuery = ""
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.appliedQuery = text
        }
    }

    private func exportFilename(for items: [Meeting]) -> String {
        let raw: String
        if items.count == 1 {
            raw = items[0].title
        } else if case .category(let id) = activeFilter, let name = category(for: id)?.name {
            raw = name
        } else {
            raw = tr("会议记录")
        }
        let cleaned = raw.replacingOccurrences(of: "/", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? tr("会议记录") : cleaned) + ".md"
    }

    private func finishLiveMeeting(paragraphs: [Paragraph], duration: TimeInterval) {
        guard let id = liveMeetingID, let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        let hasText = paragraphs.contains { !$0.renderedSource(language: meetings[index].sourceLanguage).isEmpty }
        if paragraphs.isEmpty, let saved = resumedMeetingSnapshot {
            meetings[index].paragraphs = saved.paragraphs
            meetings[index].duration = saved.duration
            meetings[index].sourceLanguage = saved.sourceLanguage
            meetings[index].targetLanguage = saved.targetLanguage
            meetings[index].inputDeviceName = saved.inputDeviceName
            meetings[index].isLive = false
        } else if !hasText && duration <= 0 {
            meetings.remove(at: index)
            if openMeetingID == id { openMeetingID = nil }
        } else {
            meetings[index].paragraphs = paragraphs
            meetings[index].duration = max(duration, paragraphs.flatMap(\.commits).map(\.end).max() ?? 0)
            meetings[index].isLive = false
        }
        liveMeetingID = nil
        resumedMeetingSnapshot = nil
        persistMeetings()
    }
}
