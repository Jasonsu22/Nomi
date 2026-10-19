import SwiftUI

struct AskView: View {
    var model: AppModel
    var anchorMeetingID: UUID? = nil
    var onHistoryChange: (Bool) -> Void = { _ in }
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var composerState = ChatComposerState()
    @State private var scopePresented = false
    @State private var historyPresented = false
    @State private var historyShield = ClickShield()
    @State private var historyGate = HistoryClickGate()
    @State private var renaming = false
    @State private var renameID: UUID?
    @State private var renameDraft = ""
    @State private var deletingChat = false
    @State private var deleteID: UUID?

    private let examples = ["这门课的重点是什么？", "有哪些需要记住的术语？", "作业或下一步是什么？"]

    private var embedded: Bool { anchorMeetingID != nil }

    private var session: ChatSession? { model.chat(anchoredTo: anchorMeetingID) }

    var body: some View {
        Group {
            if embedded {
                VStack(spacing: 0) {
                    embeddedHeader
                    HStack(alignment: .top, spacing: historyPresented ? Space.s2 : 0) {
                        conversation
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if historyPresented {
                            historyPanel
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
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
                    HStack(alignment: .top, spacing: historyPresented ? Space.s3 : 0) {
                        conversation
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)
                            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        if historyPresented {
                            historyPanel
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
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
        }
        .onChange(of: model.llmConfiguration.mode) { _, _ in
            Task { await model.refreshActiveAPIModels() }
        }
        .onChange(of: model.llmConfiguration.activeID) { _, _ in
            Task { await model.refreshActiveAPIModels() }
        }
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
                        ChatTranscript(model: model, session: session,
                                       pendingQuestion: model.chatGeneratingID == session.id ? model.pendingQuestion : nil,
                                       preparing: model.preparingVisualTurnIDs,
                                       nextModel: model.assistantModelName)
                            .id(session.id)
                            .task(id: session.id) {
                                await AnswerPreparation.prewarm(session.turns.suffix(24).reversed().map(\.answer))
                            }
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
            }
            if let error = model.chatError, model.chatGeneratingID == nil {
                Text(error)
                    .font(AppFont.secondary)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.s4)
                    .padding(.bottom, Space.s2)
            }
            ChatComposer(model: model, anchorMeetingID: anchorMeetingID, state: composerState, scopePresented: $scopePresented) {
                setHistory(false)
            }
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
                        composerState.draft = tr(example)
                        composerState.focused = true
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
        .padding(.top, Space.s2)
        .padding(.trailing, embedded ? Space.s2 : 0)
        .padding(.bottom, Space.s2)
        .fixedSize(horizontal: true, vertical: false)
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
        if shown { onHistoryChange(true) }
        withAnimation(Motion.layout(reduceMotion)) {
            historyPresented = shown
        }
        if !shown { onHistoryChange(false) }
    }

    private func dismissPanels() {
        guard scopePresented || historyPresented else { return }
        scopePresented = false
        if historyPresented { setHistory(false) }
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

struct ModelChangeNote: View {
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

