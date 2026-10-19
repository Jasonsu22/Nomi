import SwiftUI
import UniformTypeIdentifiers
import Observation

@MainActor @Observable
final class ChatComposerState {
    var draft = ""
    var focused = false
    var imageNotice: String?
}

struct ChatComposer: View {
    var model: AppModel
    var anchorMeetingID: UUID?
    @Bindable var state: ChatComposerState
    @Binding var scopePresented: Bool
    var onOpenScope: () -> Void
    private var embedded: Bool { anchorMeetingID != nil }
    private var session: ChatSession? { model.chat(anchoredTo: anchorMeetingID) }

    var body: some View {
        composer
            .onAppear { state.focused = true; restoreDraft() }
            .onChange(of: model.chatFocusRequest) { _, _ in state.focused = true }
            .onChange(of: model.chatDraftRestore) { _, _ in restoreDraft() }
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
            if let imageNotice = state.imageNotice {
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
                        text: $state.draft,
                        placeholder: tr("问点什么…"),
                        focused: state.focused,
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
            onOpenScope()
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
        let lines = max(1, state.draft.components(separatedBy: "\n").count)
        return min(96, max(36, CGFloat(lines) * 22 + 8))
    }

    private var canSend: Bool {
        let hasText = !state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !attachedImages.isEmpty) && model.canGenerateAssistant && model.chatGeneratingID == nil
    }

    private var showsCloudNotice: Bool {
        guard model.llmConfiguration.mode == .api, let profile = model.llmConfiguration.activeProfile, !profile.isLoopback else { return false }
        return (session?.turns.isEmpty ?? true) && model.pendingQuestion == nil
    }

    private var webHelp: String {
        model.webSearch.isActiveReady
            ? tr("允许模型上网查资料。")
            : tr("先在设置里配置一个搜索服务")
    }

    private func send() {
        guard model.chatGeneratingID == nil, let id = composerChatID() else { return }
        let images = model.composerImages[id] ?? []
        let text = state.draft
        guard model.ask(text, images: images, anchor: anchorMeetingID) else { return }
        state.draft = ""
        model.composerImages[id] = []
        state.imageNotice = nil
        state.focused = true
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
        state.imageNotice = intake.notice
    }

    private func removeImage(_ draft: ChatImageDraft) {
        guard let id = session?.id else { return }
        ChatImages.discard(draft)
        var next = model.composerImages[id] ?? []
        next.removeAll { $0.id == draft.id }
        model.composerImages[id] = next
        state.imageNotice = nil
    }

    private func removeLastImage() -> Bool {
        guard state.draft.isEmpty, let last = attachedImages.last else { return false }
        removeImage(last)
        return true
    }

    private func restoreDraft() {
        guard let text = model.chatDraftRestore else { return }
        state.draft = text
        model.chatDraftRestore = nil
        state.focused = true
    }

}
