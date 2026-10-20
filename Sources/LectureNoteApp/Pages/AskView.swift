import SwiftUI
import UniformTypeIdentifiers

struct AskView: View {
    var model: AppModel
    var anchorMeetingID: UUID? = nil
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var composerFocused = false
    @State private var scopePresented = false
    @State private var historyPresented = false
    @State private var historyShield = ClickShield()
    @State private var historyGate = HistoryClickGate()
    @State private var renaming = false
    @State private var renameID: UUID?
    @State private var renameDraft = ""
    @State private var deletingChat = false
    @State private var deleteID: UUID?
    @State private var imageNotice: String?

    private let examples = ["这门课的重点是什么？", "有哪些需要记住的术语？", "作业或下一步是什么？"]

    private var embedded: Bool { anchorMeetingID != nil }

    private var session: ChatSession? { model.chat(anchoredTo: anchorMeetingID) }

    var body: some View {
        Group {
            if embedded {
                VStack(spacing: 0) {
                    embeddedHeader
                    conversation
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.top, 28)
                        .padding(.bottom, Space.s4)
                    if showsSearchGuide {
                        searchGuide
                            .padding(.bottom, Space.s4)
                    }
                    conversation
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .padding(.bottom, Space.s5)
                }
                .pageColumn()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if let anchorMeetingID {
                model.ensureMeetingChat(anchorMeetingID)
            } else {
                model.ensureChat()
            }
            model.localModels.refresh()
            composerFocused = true
            restoreDraft()
        }
        .onChange(of: model.llmConfiguration.mode) { _, _ in
            Task { await model.refreshActiveAPIModels() }
        }
        .onChange(of: model.llmConfiguration.activeID) { _, _ in
            Task { await model.refreshActiveAPIModels() }
        }
        .onChange(of: model.chatFocusRequest) { _, _ in composerFocused = true }
        .onChange(of: model.chatDraftRestore) { _, _ in restoreDraft() }
        .alert(tr("重命名对话"), isPresented: $renaming) {
            TextField(tr("名称"), text: $renameDraft)
            Button(tr("取消"), role: .cancel) {}
            Button(tr("保存")) {
                if let renameID { model.renameChat(renameID, to: renameDraft) }
            }
        }
        .alert(tr("删除这场对话？"), isPresented: $deletingChat) {
            Button(tr("删除"), role: .destructive) {
                if let deleteID { model.deleteChat(deleteID) }
            }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("这场对话会从历史里去掉。"))
        }
    }

    private var header: some View {
        HStack(spacing: Space.s3) {
            Text(tr("提问"))
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.textPrimary)
                .contentShape(Rectangle())
                .onTapGesture { dismissPanels() }
            Spacer(minLength: Space.s3)
                .contentShape(Rectangle())
                .onTapGesture { dismissPanels() }
            historyButton
            AskIconButton(symbol: "plus", help: tr("新会话"), reduceMotion: reduceMotion) {
                scopePresented = false
                setHistory(false)
                model.beginNewChat(anchor: anchorMeetingID)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var embeddedHeader: some View {
        HStack(spacing: Space.s2) {
            Spacer(minLength: 0)
            historyButton
            AskIconButton(symbol: "plus", help: tr("新会话"), reduceMotion: reduceMotion) {
                scopePresented = false
                setHistory(false)
                model.beginNewChat(anchor: anchorMeetingID)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.top, Space.s2)
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if showEmpty {
                        emptyState
                    } else if let session {
                        ScrollView {
                            VStack(alignment: .leading, spacing: Space.s5) {
                                ForEach(Array(session.turns.enumerated()), id: \.element.id) { index, turn in
                                    if index > 0, modelDidChange(session.turns[index - 1].modelName, turn.modelName) {
                                        ModelChangeNote(from: session.turns[index - 1].modelName, to: turn.modelName)
                                    }
                                    turnView(turn)
                                    if model.preparingVisualTurnIDs.contains(turn.id) {
                                        HStack(spacing: Space.s2) {
                                            ProgressView().controlSize(.small)
                                            Text(tr("正在准备图示…"))
                                                .font(AppFont.secondary)
                                                .foregroundStyle(AppColor.textSecondary)
                                        }
                                    }
                                }
                                if model.chatGeneratingID == session.id, let question = model.pendingQuestion {
                                    if let previous = session.turns.last?.modelName, modelDidChange(previous, model.assistantModelName) {
                                        ModelChangeNote(from: previous, to: model.assistantModelName)
                                    }
                                    pendingView(question)
                                } else if let previous = session.turns.last?.modelName, modelDidChange(previous, model.assistantModelName) {
                                    ModelChangeNote(from: previous, to: model.assistantModelName)
                                }
                            }
                            .padding(Space.s5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .defaultScrollAnchor(.bottom)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if scopePresented {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { scopePresented = false }
                }
                if scopePresented, !embedded {
                    AskScopePopover(model: model) { scopePresented = false }
                        .padding(.leading, Space.s4)
                        .padding(.bottom, Space.s3)
                }
                if historyPresented {
                    historyPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, Space.s3)
                        .padding(.trailing, Space.s4)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
                }
            }
            if let error = model.chatError, model.chatGeneratingID == nil {
                Text(error)
                    .font(AppFont.secondary)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.s4)
                    .padding(.bottom, Space.s2)
            }
            composer
        }
    }

    private var showEmpty: Bool {
        let pending = model.chatGeneratingID == session?.id && model.pendingQuestion != nil
        return (session?.turns.isEmpty ?? true) && !pending
    }

    private var emptyState: some View {
        VStack(spacing: Space.s4) {
            Image(systemName: "text.bubble")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AppColor.accent)
                .frame(width: 56, height: 56)
                .background(AppColor.accentSoft, in: Circle())
            Text(embedded ? tr("根据这场会议的转写和资料回答。") : tr("根据你的会议和资料回答。"))
                .font(embedded ? AppFont.secondary : AppFont.sectionTitle)
                .foregroundStyle(embedded ? AppColor.textSecondary : AppColor.textPrimary)
                .multilineTextAlignment(.center)
            if !embedded {
            HStack(spacing: Space.s2) {
                ForEach(examples, id: \.self) { example in
                    Button {
                        draft = tr(example)
                        composerFocused = true
                    } label: {
                        Text(tr(example))
                            .font(AppFont.secondary)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColor.surfaceInset, in: Capsule())
                    }
                    .buttonStyle(.plain.clicking())
                }
            }
            }
        }
        .padding(.horizontal, embedded ? Space.s4 : Space.s6)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if showsCloudNotice, let name = model.llmConfiguration.activeProfile?.name {
                Text(hasScope
                    ? trf("会把所选会议和资料的文字发给 %@。", name)
                    : trf("这次只把问题发给 %@，不附带会议和资料。", name))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            HStack(alignment: .center, spacing: Space.s2) {
                if !embedded { scopeChip }
                webChip
                Spacer(minLength: Space.s2)
                modelMenu
            }
            if let imageNotice {
                Text(imageNotice)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            if !attachedImages.isEmpty, !modelSeesImages {
                Text(tr("当前模型看不到图片，图片只会留在对话里。"))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            HStack(alignment: .bottom, spacing: Space.s2) {
                attachButton
                VStack(alignment: .leading, spacing: 8) {
                    if !attachedImages.isEmpty {
                        ChatImageStrip(items: attachedImages, onRemove: removeImage)
                    }
                    AskComposerField(
                        text: $draft,
                        placeholder: tr("问点什么…"),
                        focused: composerFocused,
                        onSubmit: send,
                        onPasteImages: addPastedImages,
                        onRemoveLastImage: removeLastImage
                    )
                    .frame(height: composerHeight)
                }
                sendButton
            }
        }
        .padding(Space.s4)
        .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            let matched = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
            guard !matched.isEmpty else { return false }
            for provider in matched {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = item as? URL
                    }
                    guard let url else { return }
                    Task { @MainActor in addImages(urls: [url]) }
                }
            }
            return true
        }
        .padding(Space.s4)
    }

    private var scopeChip: some View {
        let title = session?.scope.chipTitle(
            meetings: model.chatMeetingItems(),
            sources: model.chatSourceItems(),
            categories: model.chatCategoryNames()
        ) ?? tr("选择范围")
        return Button {
            setHistory(false)
            scopePresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(AppFont.secondary.weight(.medium))
            .foregroundStyle(hasScope || scopePresented ? AppColor.accent : AppColor.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(hasScope || scopePresented ? AppColor.accentSoft : AppColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(hasScope || scopePresented ? Color.clear : AppColor.separator, lineWidth: 1))
            .fixedSize(horizontal: true, vertical: true)
        }
        .buttonStyle(.plain.clicking())
        .help(tr("选择范围"))
    }

    private var webChip: some View {
        let available = model.webSearch.isActiveReady
        let on = available && session?.allowsWeb == true
        return Button {
            model.setChatWeb(!on, anchor: anchorMeetingID)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text(tr("联网"))
            }
            .font(AppFont.secondary.weight(.medium))
            .foregroundStyle(on ? AppColor.accent : (available ? AppColor.textPrimary : AppColor.textSecondary))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(on ? AppColor.accentSoft : AppColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Color.clear : AppColor.separator, lineWidth: 1))
        }
        .buttonStyle(.plain.clicking())
        .disabled(!available)
        .help(webHelp)
    }

    private var modelMenu: some View {
        Menu {
            if model.llmConfiguration.mode == .local {
                ForEach(localChatModels) { item in
                    Button {
                        Task { await model.selectLocalModel(item, for: .assistant) }
                    } label: {
                        if item.id == LocalModelDefinition.selected(for: .assistant).id {
                            Label(item.name, systemImage: "checkmark")
                        } else {
                            Text(item.name)
                        }
                    }
                    .disabled(!model.canSwitchModels)
                }
            } else if let profile = model.llmConfiguration.activeProfile {
                ForEach(model.apiModelChoices, id: \.self) { modelID in
                    Button {
                        model.useAPIModel(modelID)
                    } label: {
                        if modelID == profile.modelID {
                            Label(modelID, systemImage: "checkmark")
                        } else {
                            Text(modelID)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(model.assistantModelName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(AppFont.secondary)
            .foregroundStyle(AppColor.textSecondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: embedded ? .infinity : nil, alignment: .trailing)
        .fixedSize(horizontal: !embedded, vertical: true)
        .clickCursor()
        .disabled(model.chatGeneratingID != nil || modelMenuIsEmpty)
    }

    private var localChatModels: [LocalModelDefinition] {
        let installed = LocalModelDefinition.catalog.filter {
            $0.supports(.assistant) && model.localModels.installed.contains($0.id)
        }
        let current = LocalModelDefinition.selected(for: .assistant)
        if installed.contains(where: { $0.id == current.id }) { return installed }
        return [current] + installed
    }

    private var modelMenuIsEmpty: Bool {
        if model.llmConfiguration.mode == .local { return localChatModels.isEmpty }
        return model.llmConfiguration.activeProfile == nil || model.apiModelChoices.isEmpty
    }

    private var sendButton: some View {
        let generating = model.chatGeneratingID == session?.id
        return Button {
            if generating { model.stopChat() } else { send() }
        } label: {
            Image(systemName: generating ? "stop.fill" : "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(generating || canSend ? AppColor.onAccent : AppColor.textSecondary)
                .frame(width: 32, height: 32)
                .background(generating || canSend ? AppColor.accent : AppColor.surface, in: Circle())
                .overlay(Circle().strokeBorder(generating || canSend ? Color.clear : AppColor.separator, lineWidth: 1))
        }
        .buttonStyle(.plain.clicking())
        .disabled(!generating && !canSend)
        .help(generating ? tr("停止") : tr("发送"))
        .accessibilityLabel(generating ? tr("停止") : tr("发送"))
    }

    private var hasScope: Bool {
        if let anchorMeetingID {
            let meeting = model.meetings.first { $0.id == anchorMeetingID }
            let hasText = meeting?.paragraphs.contains {
                !$0.renderedSource(language: meeting?.sourceLanguage ?? "zh").isEmpty
            } ?? false
            return hasText || !model.linkedSources(for: anchorMeetingID).isEmpty
        }
        guard let scope = session?.scope else { return false }
        return scope.includeAll || !scope.categoryIDs.isEmpty || scope.includesUncategorized
            || !scope.meetingIDs.isEmpty || !scope.sourceIDs.isEmpty
    }

    private var composerHeight: CGFloat {
        let lines = max(1, draft.components(separatedBy: "\n").count)
        return min(96, max(36, CGFloat(lines) * 22 + 8))
    }

    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !attachedImages.isEmpty) && model.canGenerateAssistant && model.chatGeneratingID == nil
    }

    private var showsCloudNotice: Bool {
        guard model.llmConfiguration.mode == .api, let profile = model.llmConfiguration.activeProfile, !profile.isLoopback else { return false }
        return (session?.turns.isEmpty ?? true) && model.pendingQuestion == nil
    }

    private var showsSearchGuide: Bool {
        !embedded && !model.webSearch.hasReadyProvider && !model.webSearch.guideDismissed
    }

    private var searchGuide: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text(tr("联网搜索需要你自己的搜索密钥。个人使用可以先用 Tavily，每月有免费额度，不用绑卡。"))
                .font(AppFont.secondary)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s3)
            Button(tr("以后再说")) { model.webSearch.dismissGuide() }
                .clickCursor()
            Button(tr("去设置")) {
                model.revealSearchSettings = true
                model.page = .settings
            }
            .buttonStyle(.borderedProminent.clicking())
        }
        .padding(Space.s4)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var webHelp: String {
        model.webSearch.isActiveReady
            ? tr("允许模型上网查资料。")
            : tr("先在设置里配置一个搜索服务")
    }

    private func turnView(_ turn: ChatTurn) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: Space.s2) {
                    if !turn.images.isEmpty {
                        StoredImageStrip(images: turn.images)
                    }
                    if !turn.question.isEmpty {
                        Text(turn.question)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            if let error = turn.error {
                Text(error)
                    .font(AppFont.secondary)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if !turn.answer.isEmpty {
                AnswerBody(source: turn.answer, citations: turn.citations) { citation in
                    model.openCitation(citation)
                }
                .frame(maxWidth: 680, alignment: .leading)
            }
        }
    }

    private func pendingView(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: Space.s2) {
                    if !model.pendingImageDrafts.isEmpty {
                        ChatImageStrip(items: model.pendingImageDrafts)
                    }
                    if !question.isEmpty {
                        Text(question)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            if model.pendingAnswer.isEmpty {
                HStack(spacing: Space.s2) {
                    ProgressView().controlSize(.small)
                    Text(tr("正在回答…"))
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                }
            } else {
                AnswerBody(source: model.pendingAnswer, streaming: true, citations: model.pendingCitations) { citation in
                    model.openCitation(citation)
                }
                    .frame(maxWidth: 680, alignment: .leading)
            }
        }
    }

    private var historyButton: some View {
        AskIconButton(symbol: "clock.arrow.circlepath", help: tr("历史会话"), reduceMotion: reduceMotion) {
            scopePresented = false
            if historyGate.suppressButton {
                historyGate.suppressButton = false
                return
            }
            setHistory(!historyPresented)
        }
        .background { ClickShieldAnchor(shield: historyShield) }
    }

    private var historyPanel: some View {
        AskHistoryPopover(
            model: model,
            anchorMeetingID: anchorMeetingID,
            currentID: session?.id,
            onRename: beginRename,
            onDelete: beginDelete
        ) {
            setHistory(false)
        }
        .fixedSize()
        .background {
            OutsideClickObserver(isActive: true, shield: historyShield) {
                historyGate.suppressButton = true
                setHistory(false)
                DispatchQueue.main.async { historyGate.suppressButton = false }
            }
        }
    }

    private func setHistory(_ shown: Bool) {
        guard shown != historyPresented else { return }
        withAnimation(Motion.layout(reduceMotion)) {
            historyPresented = shown
        }
    }

    private func dismissPanels() {
        guard scopePresented || historyPresented else { return }
        scopePresented = false
        if historyPresented { setHistory(false) }
    }

    private func modelDidChange(_ previous: String, _ next: String) -> Bool {
        !previous.isEmpty && !next.isEmpty && previous != next
    }

    private func send() {
        guard model.chatGeneratingID == nil, let id = composerChatID() else { return }
        let images = model.composerImages[id] ?? []
        let text = draft
        guard model.ask(text, images: images, anchor: anchorMeetingID) else { return }
        draft = ""
        model.composerImages[id] = []
        imageNotice = nil
        composerFocused = true
    }

    private var attachButton: some View {
        Button(action: pickImages) {
            Image(systemName: "paperclip")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain.clicking())
        .help(tr("添加图片"))
        .accessibilityLabel(tr("添加图片"))
    }

    private var attachedImages: [ChatImageDraft] {
        guard let id = session?.id else { return [] }
        return model.composerImages[id] ?? []
    }

    private var modelSeesImages: Bool {
        ChatImages.seesImages(mode: model.llmConfiguration.mode, modelID: model.llmConfiguration.activeProfile?.modelID ?? "")
    }

    private func composerChatID() -> UUID? {
        if let anchorMeetingID {
            model.ensureMeetingChat(anchorMeetingID)
            return model.meetingChatID[anchorMeetingID]
        }
        model.ensureChat()
        return model.currentChatID
    }

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.jpeg, .png, .gif, .webP, .heic, .tiff]
        panel.begin { response in
            guard response == .OK else { return }
            Task { @MainActor in addImages(urls: panel.urls) }
        }
    }

    private func addPastedImages(_ pasteboard: NSPasteboard) -> Bool {
        guard let id = composerChatID() else { return false }
        let existing = model.composerImages[id]?.count ?? 0
        guard let intake = ChatImages.intake(pasteboard: pasteboard, existing: existing) else { return false }
        accept(intake, id: id)
        return true
    }

    private func addImages(urls: [URL]) {
        guard let id = composerChatID() else { return }
        let existing = model.composerImages[id]?.count ?? 0
        accept(ChatImages.intake(urls: urls, existing: existing), id: id)
    }

    private func accept(_ intake: (drafts: [ChatImageDraft], notice: String?), id: UUID) {
        var next = model.composerImages[id] ?? []
        next.append(contentsOf: intake.drafts)
        model.composerImages[id] = next
        imageNotice = intake.notice
    }

    private func removeImage(_ draft: ChatImageDraft) {
        guard let id = session?.id else { return }
        ChatImages.discard(draft)
        var next = model.composerImages[id] ?? []
        next.removeAll { $0.id == draft.id }
        model.composerImages[id] = next
        imageNotice = nil
    }

    private func removeLastImage() -> Bool {
        guard draft.isEmpty, let last = attachedImages.last else { return false }
        removeImage(last)
        return true
    }

    private func restoreDraft() {
        guard let text = model.chatDraftRestore else { return }
        draft = text
        model.chatDraftRestore = nil
        composerFocused = true
    }

    private func beginRename(_ session: ChatSession) {
        Task { @MainActor in
            renameID = session.id
            renameDraft = session.displayTitle
            renaming = true
        }
    }

    private func beginDelete(_ session: ChatSession) {
        Task { @MainActor in
            deleteID = session.id
            deletingChat = true
        }
    }
}

private struct ModelChangeNote: View {
    var from: String
    var to: String

    var body: some View {
        HStack(spacing: Space.s3) {
            line
            ViewThatFits(in: .horizontal) {
                note(limit: 1)
                note(limit: 2)
            }
            .layoutPriority(1)
            line
        }
        .accessibilityElement(children: .combine)
    }

    private func note(limit: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cube")
            Text(trf("模型已从 %@ 换成 %@", from, to))
                .lineLimit(limit)
                .multilineTextAlignment(.center)
        }
        .font(AppFont.caption)
        .foregroundStyle(AppColor.textSecondary)
        .fixedSize(horizontal: limit == 1, vertical: false)
    }

    private var line: some View {
        Rectangle()
            .fill(AppColor.separator)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

private struct AskIconButton: View {
    var symbol: String
    var help: String
    var reduceMotion: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: 36, height: 36)
                .background(hovering ? AppColor.surfaceInset : AppColor.surface, in: Circle())
        }
        .buttonStyle(.plain.clicking())
        .help(help)
        .onHover { hovering = $0 }
        .animation(Motion.fade(reduceMotion), value: hovering)
    }
}

