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

    /// Pages that stay built after their first visit so switching back is immediate.
    static let keptAlive: [AppPage] = [.meetings, .sources, .ask]

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
    /// The quick tutorial's current tip, or nil when it is not running.
    var tutorialStep: TutorialStop?
    var revealSearchSettings = false
    var revealMemorySettings = false
    let webSearch = SearchConfiguration()
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
    var openMeetingID: UUID? {
        didSet {
            if openMeetingID == nil { meetingCompact = false }
        }
    }
    var meetingCompact = false {
        didSet {
            if meetingCompact { windowAllowsCompact = true }
        }
    }
    /// Stays on until the window has finished growing back, so the minimum size does not jump.
    var windowAllowsCompact = false
    var exportError: String?
    var storageError: String?
    var sourceError: String?
    var sources: [KnowledgeSource] = [] {
        didSet { persistSources() }
    }
    private var sourcesPersistence = false
    var searchRequest = 0
    private(set) var appliedQuery = ""
    let engine: any TranscriptionEngine
    let audioInputs = AudioInputs()
    let localModels = LocalModelLibrary()
    let llmConfiguration = LLMConfiguration()
    let prompts = PromptPreferences()
    /// What Nomi has learned about the student. Kept on disk only for the real app, not previews and tests.
    private(set) var memory = UserMemory(file: nil)
    /// Each meeting's Q&A tab, loaded when first needed. The tab observes the object itself.
    @ObservationIgnored var qaStates: [UUID: MeetingQA] = [:]
    /// Checks the transcript for new questions while recording.
    @ObservationIgnored var questionScanTask: Task<Void, Never>?
    /// Answers queued questions one at a time.
    @ObservationIgnored var questionQueueTask: Task<Void, Never>?
    /// A Q&A job is generating on the local model, so other local work waits for it.
    @ObservationIgnored var questionWorkGenerating = false
    /// Scrolls a meeting's transcript to a moment, from the Q&A tab.
    var transcriptJump: TranscriptJump?
    /// Work that runs after an answer (chat summary, then memory), if it is waiting or running.
    @ObservationIgnored var afterAnswerTask: Task<Void, Never>?
    /// That work has started generating, so a local question waits for it instead of cancelling it.
    @ObservationIgnored var afterAnswerGenerating = false
    /// Summary passes that failed in a row, per chat. A chat stops trying after a few.
    @ObservationIgnored var summaryFailures: [UUID: Int] = [:]
    /// Learning passes that failed in a row. Each failure waits for more turns before trying again.
    @ObservationIgnored var memoryFailures = 0
    var assistantStates: [UUID: MeetingAssistantState] = [:]
    var chats: [ChatSession] = []
    var currentChatID: UUID?
    /// The open chat for each meeting's own ask panel.
    var meetingChatID: [UUID: UUID] = [:]
    var meetingLinks: [UUID: [UUID]] = [:] {
        didSet { persistMeetingLinks() }
    }
    private var meetingLinksReady = false
    var chatGeneratingID: UUID?
    var pendingQuestion: String?
    var pendingAnswer = ""
    var pendingCitations: [ChatCitation] = []
    var pendingImageDrafts: [ChatImageDraft] = []
    var composerImages: [UUID: [ChatImageDraft]] = [:]
    /// Messages sent while an answer was coming, for every chat, oldest first. Kept in memory only.
    var chatQueue: [QueuedPrompt] = []
    /// Chats whose queue waits for the student after a Stop or an error.
    var queuePaused: Set<UUID> = []
    var enlargedImage: NSImage?
    var enlargedImageName = "image.png"
    var enlargedImageURL: URL?
    /// Turns whose demonstration is being written by a separate request.
    var preparingVisualTurnIDs: Set<UUID> = []
    var chatError: String?
    var chatDraftRestore: String?
    var chatFocusRequest = 0
    @ObservationIgnored var chatTask: Task<Void, Never>?
    @ObservationIgnored var visualTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var localVisualBusy = false
    var chatsReady = false
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
        // A crash or force-quit while preparing used to leave empty "0 sec" meetings behind.
        self.meetings = meetings ?? snapshot?.meetings.filter { !$0.paragraphs.isEmpty || $0.duration > 0 } ?? SampleMeetings.make()
        self.categories = categories ?? snapshot?.categories ?? SampleMeetings.categories()
        self.filter = CategoryFilter.load()
        self.grouping = MeetingGrouping.load()
        if case .failure = stored {
            storageError = tr("无法读取本地会议记录，原文件已保留。")
        } else {
            persistenceEnabled = usesStorage
        }
        if usesStorage {
            do {
                sources = try SourceStore.load()
                sourcesPersistence = true
                // Reads file text ahead of time, so the first library search does not wait on every PDF.
                let files = sources
                Task.detached(priority: .background) {
                    for file in files { _ = await SourceTextCache.shared.blocks(for: file) }
                }
            } catch {
                sourceError = tr("无法读取资料库，原文件已保留。")
            }
            do {
                chats = try ChatStore.load().sorted { $0.updatedAt > $1.updatedAt }
                chatsReady = true
                currentChatID = chats.first { $0.anchorMeetingID == nil }?.id
            } catch {
                chatError = tr("无法读取对话记录，原文件已保留。")
            }
            meetingLinks = MeetingSourceLinkStore.load()
            meetingLinksReady = true
            memory = UserMemory()
        }
        if case .category(let id) = self.filter, self.category(for: id) == nil {
            self.filter = .all
            self.filter.save()
        }
        engine.onFinished = { [weak self] paragraphs, duration in
            self?.finishLiveMeeting(paragraphs: paragraphs, duration: duration)
        }
        engine.transcript.onCommitted = { [weak self] in
            self?.schedulePersistence()
        }
    }

    /// A chat that is still answering does not hold up a recording.
    var canStart: Bool { engine.canStart && localModels.deletingID == nil }

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

    /// Failures stay on screen. A finished, healthy load is allowed to leave.
    var statusStays: Bool {
        switch engine.session.phase {
        case .preparing, .listening, .stopping:
            return true
        case .idle:
            if engine.loadError != nil { return true }
            switch engine.readiness {
            case .ready: return false
            case .preview, .preparing, .sourceOnly, .asrMissing, .unavailable:
                return true
            }
        }
    }

    var statusIsError: Bool {
        guard engine.session.phase == .idle else { return false }
        if engine.loadError != nil { return true }
        switch engine.readiness {
        case .asrMissing, .unavailable: return true
        case .preview, .preparing, .ready, .sourceOnly: return false
        }
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
        engine.recordingURL = nextAudioFile(for: &meeting)
        engine.sourceLanguage = meeting.sourceLanguage
        engine.targetLanguage = meeting.targetLanguage
        engine.inputDeviceUID = device?.id
        recordingSetupPresented = false
        recordingResumeID = nil
        resumedMeetingSnapshot = nil
        meetings.insert(meeting, at: 0)
        liveMeetingID = meeting.id
        startLiveQuestionScan(meeting.id)
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
        engine.recordingURL = nextAudioFile(for: &meetings[index])
        meetings[index].isLive = true
        liveMeetingID = id
        startLiveQuestionScan(id)
        openMeetingID = id
        page = .meetings
        recordingSetupPresented = false
        recordingResumeID = nil
        engine.start(resuming: history, at: offset)
    }

    func stopTranscription() {
        engine.stop()
    }

    /// Each recording run gets its own file. ADTS (.aac) stays readable if the app dies
    /// mid-recording; an unfinished .m4a has no index and cannot be opened.
    private func nextAudioFile(for meeting: inout Meeting) -> URL? {
        guard persistenceEnabled else { return nil }
        let name = "audio-\((meeting.audioFiles?.count ?? 0) + 1).aac"
        meeting.audioFiles = (meeting.audioFiles ?? []) + [name]
        return MeetingStore.audioDirectory(for: meeting.id).appendingPathComponent(name)
    }

    private func removeAudio(of meeting: Meeting, except kept: [String]? = nil) {
        let directory = MeetingStore.audioDirectory(for: meeting.id)
        guard let kept else {
            try? FileManager.default.removeItem(at: directory)
            return
        }
        for name in meeting.audioFiles ?? [] where !kept.contains(name) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    func togglePause() {
        engine.togglePause()
    }

    func openMeeting(_ id: UUID) {
        openMeetingID = id
        page = .meetings
    }

    func startTutorial() {
        tutorialStep = TutorialStop.allCases.first
    }

    /// Shows the meeting being recorded, from whichever page is open.
    func openLiveMeeting() {
        guard let liveMeetingID, meetings.contains(where: { $0.id == liveMeetingID }) else { return }
        openMeeting(liveMeetingID)
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
        ChatStore.flush()
        memory.flush()
        MeetingQAStore.flush()
        ChatImages.removeTemporary()
        (engine as? LocalEngine)?.shutdown()
    }

    private func schedulePersistence() {
        guard persistenceEnabled else { return }
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.persistMeetings(inBackground: true)
        }
    }

    private func persistMeetings(inBackground: Bool = false) {
        guard persistenceEnabled else { return }
        persistenceTask?.cancel()
        let saved: [Meeting] = meetings.compactMap { meeting in
            guard meeting.id == liveMeetingID else { return meeting }
            let paragraphs = engine.transcript.snapshot(at: engine.session.elapsed)
            let hasText = paragraphs.contains { !$0.renderedSource(language: meeting.sourceLanguage).isEmpty }
            guard hasText else { return resumedMeetingSnapshot }
            var saved = meeting
            saved.paragraphs = paragraphs
            saved.duration = max(saved.duration, engine.session.elapsed, paragraphs.flatMap(\.commits).map(\.end).max() ?? 0)
            saved.isLive = false
            return saved
        }
        let snapshot = MeetingStore.Snapshot(meetings: saved, categories: categories)
        let message = tr("会议保存失败，请导出备份后重试。")
        if inBackground {
            MeetingStore.saveInBackground(snapshot) { [weak self] in
                Task { @MainActor in self?.storageError = message }
            }
            return
        }
        do {
            try MeetingStore.save(snapshot)
        } catch {
            storageError = message
        }
    }

    func assign(meeting id: UUID, category categoryID: UUID?) {
        assign(meetings: [id], category: categoryID)
    }

    func assign(meetings ids: Set<UUID>, category categoryID: UUID?) {
        guard !ids.isEmpty else { return }
        var updated = meetings
        var changed = false
        for index in updated.indices where ids.contains(updated[index].id) && updated[index].categoryID != categoryID {
            updated[index].categoryID = categoryID
            changed = true
        }
        guard changed else { return }
        meetings = updated
        syncLinkedSources(of: ids, to: categoryID)
    }

    func linkedSources(for meetingID: UUID) -> [KnowledgeSource] {
        let ids = meetingLinks[meetingID] ?? []
        return ids.compactMap { id in sources.first { $0.id == id } }
    }

    func importLinkedSources(_ urls: [URL], meetingID: UUID) {
        guard let meeting = meetings.first(where: { $0.id == meetingID }) else { return }
        var added: [UUID] = []
        var rejected = false
        for url in urls {
            guard SourceStore.accepts(url) else {
                rejected = true
                continue
            }
            do {
                let source = try SourceStore.stage(url, categoryID: meeting.categoryID)
                sources.append(source)
                added.append(source.id)
            } catch {
                sourceError = error.localizedDescription
            }
        }
        if rejected {
            sourceError = tr("暂时只收 PDF、幻灯片、文档和图片。")
        }
        guard !added.isEmpty else { return }
        var links = meetingLinks[meetingID] ?? []
        links.append(contentsOf: added)
        meetingLinks[meetingID] = links
    }

    func linkSource(_ sourceID: UUID, to meetingID: UUID) {
        guard let meeting = meetings.first(where: { $0.id == meetingID }),
              sources.contains(where: { $0.id == sourceID }) else { return }
        var links = meetingLinks[meetingID] ?? []
        guard !links.contains(sourceID) else { return }
        links.append(sourceID)
        meetingLinks[meetingID] = links
        guard let index = sources.firstIndex(where: { $0.id == sourceID }),
              sources[index].categoryID != meeting.categoryID else { return }
        sources[index].categoryID = meeting.categoryID
    }

    func unlinkSource(_ sourceID: UUID, from meetingID: UUID) {
        meetingLinks[meetingID]?.removeAll { $0 == sourceID }
        if meetingLinks[meetingID]?.isEmpty == true {
            meetingLinks[meetingID] = nil
        }
    }

    private func syncLinkedSources(of meetingIDs: Set<UUID>, to categoryID: UUID?) {
        var updated = sources
        var changed = false
        for meetingID in meetingIDs {
            for sourceID in meetingLinks[meetingID] ?? [] {
                guard let index = updated.firstIndex(where: { $0.id == sourceID }),
                      updated[index].categoryID != categoryID else { continue }
                updated[index].categoryID = categoryID
                changed = true
            }
        }
        if changed { sources = updated }
    }

    private func persistMeetingLinks() {
        guard meetingLinksReady else { return }
        do { try MeetingSourceLinkStore.save(meetingLinks) }
        catch { sourceError = tr("资料保存失败，请重试。") }
    }

    func deleteMeetings(_ ids: Set<UUID>) {
        for id in ids {
            deleteMeeting(id)
        }
    }

    func deleteMeeting(_ id: UUID) {
        guard id != liveMeetingID, assistantStates[id]?.isGenerating != true else { return }
        if let meeting = meetings.first(where: { $0.id == id }) { removeAudio(of: meeting) }
        meetings.removeAll { $0.id == id }
        assistantStates[id] = nil
        forgetQA(id)
        meetingLinks[id] = nil
        meetingChatID[id] = nil
        if openMeetingID == id {
            openMeetingID = nil
        }
    }

    @discardableResult
    func addCategory(name: String, colorIndex: Int, symbol: String, select: Bool = true) -> UUID? {
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
        if select { filter = .category(category.id) }
        return category.id
    }

    func placeCategory(_ id: UUID, at targetID: UUID) {
        guard let updated = MeetingCategory.placing(categories, moving: id, at: targetID) else { return }
        categories = updated
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
        if sources.contains(where: { $0.categoryID == id }) {
            var updated = sources
            for index in updated.indices where updated[index].categoryID == id {
                updated[index].categoryID = nil
            }
            sources = updated
        }
        if case .category(let current) = filter, current == id {
            filter = .uncategorized
        }
    }

    func commitSources(_ staged: [KnowledgeSource]) {
        guard !staged.isEmpty else { return }
        sources.insert(contentsOf: staged, at: 0)
    }

    func assign(source id: UUID, category categoryID: UUID?) {
        assign(sources: [id], category: categoryID)
    }

    func assign(sources ids: Set<UUID>, category categoryID: UUID?) {
        guard !ids.isEmpty else { return }
        var updated = sources
        var changed = false
        for index in updated.indices where ids.contains(updated[index].id) && updated[index].categoryID != categoryID {
            updated[index].categoryID = categoryID
            changed = true
        }
        guard changed else { return }
        sources = updated
    }

    func rename(source id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = sources.firstIndex(where: { $0.id == id }) else { return }
        sources[index].title = trimmed
    }

    func deleteSource(_ id: UUID) {
        deleteSources([id])
    }

    func deleteSources(_ ids: Set<UUID>) {
        let removing = sources.filter { ids.contains($0.id) }
        guard !removing.isEmpty else { return }
        for source in removing {
            SourceStore.remove(source)
        }
        sources.removeAll { ids.contains($0.id) }
        var links = meetingLinks
        for key in links.keys {
            links[key]?.removeAll { ids.contains($0) }
            if links[key]?.isEmpty == true { links[key] = nil }
        }
        meetingLinks = links
    }

    func downloadSourcesByCategory(_ ids: Set<UUID>? = nil, prompt: String? = nil) {
        let chosen = ids.map { ids in sources.filter { ids.contains($0.id) } } ?? sources
        let files = chosen.map { source in
            let folder = source.categoryID.flatMap { category(for: $0)?.name } ?? tr("未分类")
            return SourceExportFile(sourceURL: SourceStore.fileURL(for: source), folder: folder, fileName: source.fileName)
        }
        guard !files.isEmpty else { return }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else {
            sourceError = tr("找不到窗口，无法打开保存面板。")
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt ?? tr("下载")
        panel.message = tr("按分类建文件夹，把资料复制进去。")
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try SourceStore.exportGrouped(files, into: url)
            } catch {
                Task { @MainActor in
                    self.sourceError = error.localizedDescription
                }
            }
        }
    }

    func discardSources(_ staged: [KnowledgeSource]) {
        for source in staged {
            SourceStore.remove(source)
        }
    }

    private func persistSources() {
        guard sourcesPersistence else { return }
        do {
            try SourceStore.save(sources)
        } catch {
            sourceError = tr("资料保存失败，请重试。")
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
        engine.recordingURL = nil
        if paragraphs.isEmpty, let saved = resumedMeetingSnapshot {
            removeAudio(of: meetings[index], except: saved.audioFiles ?? [])
            meetings[index].audioFiles = saved.audioFiles
            meetings[index].paragraphs = saved.paragraphs
            meetings[index].duration = saved.duration
            meetings[index].sourceLanguage = saved.sourceLanguage
            meetings[index].targetLanguage = saved.targetLanguage
            meetings[index].inputDeviceName = saved.inputDeviceName
            meetings[index].isLive = false
        } else if !hasText && duration <= 0 {
            removeAudio(of: meetings[index])
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
        finishQuestionScan(id)
    }

    /// The meeting being recorded, if any.
    var recordingMeetingID: UUID? { liveMeetingID }
}
