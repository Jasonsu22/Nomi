import SwiftUI

struct AskView: View {
    var model: AppModel
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var composerFocused = false
    @State private var scopePresented = false
    @State private var historyPresented = false
    @State private var renaming = false
    @State private var renameID: UUID?
    @State private var renameDraft = ""
    @State private var deletingChat = false
    @State private var deleteID: UUID?

    private let examples = ["这门课的重点是什么？", "有哪些需要记住的术语？", "作业或下一步是什么？"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.bottom, Space.s4)
            conversation
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .padding(.bottom, Space.s5)
        }
        .pageColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            model.ensureChat()
            composerFocused = true
            restoreDraft()
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
            Spacer(minLength: Space.s3)
            AskIconButton(symbol: "clock.arrow.circlepath", help: tr("历史会话"), reduceMotion: reduceMotion) {
                scopePresented = false
                historyPresented.toggle()
            }
            AskIconButton(symbol: "plus", help: tr("新会话"), reduceMotion: reduceMotion) {
                scopePresented = false
                historyPresented = false
                model.beginNewChat()
            }
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if showEmpty {
                        emptyState
                    } else if let session = model.currentChat {
                        ScrollView {
                            VStack(alignment: .leading, spacing: Space.s5) {
                                ForEach(session.turns) { turn in
                                    turnView(turn)
                                }
                                if model.chatGeneratingID == session.id, let question = model.pendingQuestion {
                                    pendingView(question)
                                }
                            }
                            .padding(Space.s5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .defaultScrollAnchor(.bottom)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if scopePresented || historyPresented {
                    Color.black.opacity(0.001)
                        .onTapGesture {
                            scopePresented = false
                            historyPresented = false
                        }
                }
                if scopePresented {
                    AskScopePopover(model: model) { scopePresented = false }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, Space.s4)
                        .padding(.bottom, Space.s3)
                }
                if historyPresented {
                    AskHistoryPopover(model: model, onRename: beginRename, onDelete: beginDelete) {
                        historyPresented = false
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, Space.s3)
                    .padding(.trailing, Space.s4)
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
        let session = model.currentChat
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
            Text(tr("根据你的会议和资料回答。"))
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.textPrimary)
                .multilineTextAlignment(.center)
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
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Space.s6)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if showsCloudNotice, let name = model.llmConfiguration.activeProfile?.name {
                Text(trf("会把所选会议和资料的文字发给 %@。", name))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            HStack(alignment: .center, spacing: Space.s2) {
                scopeChip
                webChip
                Spacer(minLength: Space.s2)
                modelMenu
            }
            HStack(alignment: .bottom, spacing: Space.s2) {
                AskComposerField(
                    text: $draft,
                    placeholder: tr("问点什么…"),
                    focused: composerFocused,
                    onSubmit: send
                )
                .frame(height: composerHeight)
                sendButton
            }
        }
        .padding(Space.s4)
        .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(Space.s4)
    }

    private var scopeChip: some View {
        let title = model.currentChat?.scope.chipTitle(
            meetings: model.chatMeetingItems(),
            sources: model.chatSourceItems(),
            categories: model.chatCategoryNames()
        ) ?? tr("选择范围")
        return Button {
            historyPresented = false
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
        .buttonStyle(.plain)
        .help(tr("选择范围"))
    }

    private var webChip: some View {
        let available = model.webSearchSupport == .available
        let on = available && model.currentChat?.allowsWeb == true
        return Button {
            model.setChatWeb(!on)
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
        .buttonStyle(.plain)
        .disabled(!available)
        .help(webHelp)
    }

    private var modelMenu: some View {
        Menu {
            Button(LocalModelDefinition.selected(for: .assistant).name) {
                model.useLocalChatModel()
            }
            if !model.llmConfiguration.profiles.isEmpty { Divider() }
            ForEach(model.llmConfiguration.profiles) { profile in
                Button("\(profile.name) · \(profile.modelID)") {
                    model.useChatProfile(profile.id)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.assistantModelName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(AppFont.secondary)
            .foregroundStyle(AppColor.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.chatGeneratingID != nil)
    }

    private var sendButton: some View {
        let generating = model.chatGeneratingID == model.currentChat?.id
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
        .buttonStyle(.plain)
        .disabled(!generating && !canSend)
        .help(generating ? tr("停止") : tr("发送"))
        .accessibilityLabel(generating ? tr("停止") : tr("发送"))
    }

    private var hasScope: Bool {
        guard let scope = model.currentChat?.scope else { return false }
        return scope.includeAll || !scope.categoryIDs.isEmpty || scope.includesUncategorized
            || !scope.meetingIDs.isEmpty || !scope.sourceIDs.isEmpty
    }

    private var composerHeight: CGFloat {
        let lines = max(1, draft.components(separatedBy: "\n").count)
        return min(96, max(36, CGFloat(lines) * 22 + 8))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.canGenerateAssistant && model.chatGeneratingID == nil
    }

    private var showsCloudNotice: Bool {
        guard model.llmConfiguration.mode == .api, let profile = model.llmConfiguration.activeProfile, !profile.isLoopback else { return false }
        return (model.currentChat?.turns.isEmpty ?? true) && model.pendingQuestion == nil
    }

    private var webHelp: String {
        switch model.webSearchSupport {
        case .available: tr("允许模型上网查资料。")
        case .local: tr("本机模型不能联网，换成支持联网的 API 服务商后可用。")
        case .unsupported: tr("这个服务商还不能联网。")
        }
    }

    private func turnView(_ turn: ChatTurn) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Spacer(minLength: 80)
                Text(turn.question)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if let error = turn.error {
                Text(error)
                    .font(AppFont.secondary)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if !turn.answer.isEmpty {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(turn.answer)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: 680, alignment: .leading)
                    if !turn.citations.isEmpty {
                        ChipFlow(spacing: Space.s2) {
                            ForEach(turn.citations) { citation in
                                citationChip(citation)
                            }
                        }
                    }
                    Text(turn.modelName)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private func pendingView(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Spacer(minLength: 80)
                Text(question)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            HStack(spacing: Space.s2) {
                ProgressView().controlSize(.small)
                Text(tr("正在回答…"))
                    .font(AppFont.secondary)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private func citationChip(_ citation: ChatCitation) -> some View {
        let openable = model.citationIsOpenable(citation)
        let label = citation.detail.isEmpty || citation.detail == citation.title
            ? citation.title
            : "\(citation.title) · \(citation.detail)"
        let symbol = citation.url != nil ? "globe" : (citation.sourceID != nil ? "doc" : "clock")
        return Button { model.openCitation(citation) } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(label).lineLimit(1)
            }
            .font(AppFont.caption)
            .foregroundStyle(openable ? AppColor.accent : AppColor.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(openable ? AppColor.accentSoft : AppColor.surfaceInset, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!openable)
    }

    private func send() {
        guard model.chatGeneratingID == nil else { return }
        let text = draft
        guard model.ask(text) else { return }
        draft = ""
        composerFocused = true
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
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Motion.fade(reduceMotion), value: hovering)
    }
}

private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 640
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
