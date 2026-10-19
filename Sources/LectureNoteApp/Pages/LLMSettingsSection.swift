import SwiftUI

struct LLMSettingsSection: View {
    var model: AppModel
    @State private var editingProfile: LLMAPIProfile?
    @State private var confirmation: Confirmation?
    @State private var error: String?

    private enum Confirmation {
        case mode(LLMMode), activate(LLMAPIProfile), delete(LLMAPIProfile)
        var title: String {
            switch self {
            case .mode: tr("切换大模型来源？")
            case .activate: tr("使用此 API 配置？")
            case .delete: tr("删除 API 配置？")
            }
        }
        var message: String {
            switch self {
            case .mode(.local): tr("提问和摘要将使用本地模型。识别和翻译不受影响。")
            case .mode(.api): tr("提问和摘要会将相关会议文字发送到你选择的 API 服务。识别和翻译继续在本机运行。")
            case .activate(let profile): trf("后续提问和摘要将使用 %@（%@），相关会议文字会发送到此地址。", profile.name, profile.baseURL)
            case .delete(let profile): trf("删除 %@ 的地址、模型选择和已保存的 API 密钥。此操作不会删除会议。", profile.name)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(tr("提问与摘要大模型")).font(AppFont.sectionTitle).foregroundStyle(AppColor.textPrimary)
            HStack {
                Picker(tr("大模型来源"), selection: Binding(get: { model.llmConfiguration.mode }, set: { confirmation = .mode($0) })) {
                    ForEach(LLMMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .clickCursor()
                .disabled(model.assistantIsBusy)
                Spacer(minLength: 0)
            }
            if model.llmConfiguration.mode == .local {
                LocalModelPicker(model: model, role: .assistant)
                    .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                Text(tr("本地模型直接在这台 Mac 上运行。Qwen3.5 的模型文件可以与翻译共用。"))
                    .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: Space.s3) {
                    ForEach(model.llmConfiguration.profiles) { profile in
                        HStack(spacing: Space.s3) {
                            Button { confirmation = .activate(profile) } label: {
                                HStack(spacing: Space.s2) {
                                    Image(systemName: model.llmConfiguration.activeID == profile.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(AppColor.accent)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.name).font(AppFont.body).foregroundStyle(AppColor.textPrimary)
                                        Text(profile.modelID).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain.clicking())
                            Spacer()
                            Button(tr("编辑")) { editingProfile = profile }
                                .clickCursor()
                            Button(role: .destructive) { confirmation = .delete(profile) } label: {
                                Label(tr("删除"), systemImage: "trash")
                                    .foregroundStyle(.red)
                            }
                            .clickCursor()
                            .tint(.red)
                        }
                        .disabled(model.assistantIsBusy)
                    }
                    Button {
                        editingProfile = LLMAPIProfile(providerID: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1")
                    } label: { Label(tr("添加 API 配置"), systemImage: "plus") }
                    .clickCursor()
                    .disabled(model.assistantIsBusy)
                    if model.llmConfiguration.activeProfile == nil {
                        Text(tr("添加并选择一个 API 配置后，即可使用提问和摘要。"))
                            .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s4)
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            Text(tr("此切换只用于提问和摘要，语音识别和翻译模型保持独立。"))
                .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            if let error { Text(error).font(AppFont.caption).foregroundStyle(.red) }
        }
        .sheet(item: $editingProfile) { profile in APIProfileEditor(profile: profile, configuration: model.llmConfiguration) }
        .alert(confirmation?.title ?? "", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), presenting: confirmation) { action in
            if case .delete = action {
                Button(tr("删除"), role: .destructive) { apply(action) }
            } else {
                Button(tr("确认")) { apply(action) }
            }
            Button(tr("取消"), role: .cancel) {}
        } message: { Text($0.message) }
    }

    private func apply(_ action: Confirmation) {
        error = nil
        do {
            switch action {
            case .mode(let mode): model.llmConfiguration.setMode(mode)
            case .activate(let profile): model.llmConfiguration.activate(profile.id)
            case .delete(let profile): try model.llmConfiguration.delete(profile)
            }
        } catch { self.error = error.localizedDescription }
    }
}

private struct APIProfileEditor: View {
    let configuration: LLMConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LLMAPIProfile
    @State private var key = ""
    @State private var modelEntry = ""
    @State private var availableModels: [String] = []
    @State private var fetching = false
    @State private var error: String?
    @State private var confirmation: Action?
    private enum Action: Equatable { case save, fetch }

    init(profile: LLMAPIProfile, configuration: LLMConfiguration) {
        self.configuration = configuration
        _draft = State(initialValue: profile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(tr("API 配置")).font(AppFont.sectionTitle)
            VStack(alignment: .leading, spacing: 12) {
                fieldRow(tr("服务商预设")) {
                    Picker(tr("服务商预设"), selection: $draft.providerID) {
                        ForEach(LLMProviderPreset.all) { item in Text(tr(item.name)).tag(item.id) }
                    }
                    .labelsHidden()
                    .clickCursor()
                }
                .onChange(of: draft.providerID) { _, value in
                    guard let preset = LLMProviderPreset.all.first(where: { $0.id == value }) else { return }
                    draft.name = tr(preset.name)
                    draft.baseURL = preset.baseURL
                    draft.format = preset.format
                    draft.modelID = ""
                    draft.savedModelIDs = []
                    key = ""
                    modelEntry = ""
                    availableModels = []
                }
                fieldRow(tr("配置名称")) {
                    TextField(tr("配置名称"), text: $draft.name)
                }
                fieldRow("API Base URL") {
                    TextField("API Base URL", text: $draft.baseURL)
                }
                fieldRow(tr("接口格式")) {
                    Picker(tr("接口格式"), selection: $draft.format) {
                        ForEach(LLMAPIFormat.allCases) { format in Text(format.title).tag(format) }
                    }
                    .labelsHidden()
                    .clickCursor()
                }
                fieldRow(tr("API 密钥")) {
                    SecureField(tr("API 密钥"), text: $key)
                }
                HStack(alignment: .top, spacing: 12) {
                    Text(tr("模型列表"))
                        .frame(width: Self.labelWidth, alignment: .trailing)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            TextField(tr("模型 ID"), text: $modelEntry)
                                .onSubmit(addEnteredModel)
                                .frame(maxWidth: .infinity)
                            Button(action: addEnteredModel) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.borderless.clicking())
                            .disabled(modelEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help(tr("添加模型"))
                        }
                        ForEach(modelChoices, id: \.self) { id in
                            HStack(spacing: 8) {
                                Button {
                                    draft.modelID = id
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: draft.modelID == id ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(AppColor.accent)
                                        Text(id)
                                            .font(AppFont.secondary)
                                            .foregroundStyle(AppColor.textPrimary)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                }
                                .buttonStyle(.plain.clicking())
                                Button {
                                    removeModel(id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(AppColor.textSecondary)
                                }
                                .buttonStyle(.plain.clicking())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .disabled(fetching)
            .onAppear {
                if !draft.modelID.isEmpty, !draft.savedModelIDs.contains(draft.modelID) {
                    draft.savedModelIDs.insert(draft.modelID, at: 0)
                }
            }
            if let error { Text(error).font(AppFont.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button(tr("获取模型列表")) { prepare(.fetch) }
                    .clickCursor()
                    .disabled(fetching)
                if fetching { ProgressView().controlSize(.small) }
                Spacer()
                Button(tr("取消")) { dismiss() }
                    .clickCursor()
                    .keyboardShortcut(.cancelAction)
                Button(tr("保存")) { prepare(.save) }
                    .buttonStyle(.borderedProminent.clicking())
                    .disabled(fetching)
            }
        }
        .padding(Space.s5)
        .frame(width: 540)
        .alert(confirmation == .save ? tr("保存 API 配置？") : tr("连接此 API 服务？"), isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), presenting: confirmation) { action in
            Button(tr("确认")) {
                if action == .save { save() }
                else { Task { await fetchModels() } }
            }
            Button(tr("取消"), role: .cancel) {}
        } message: { action in
            Text(action == .save
                 ? trf("保存 %@（%@）及所选模型。使用 API 提问和摘要时，相关会议文字将发送到此地址。", draft.name, draft.baseURL)
                 : trf("将连接 %@ 获取模型列表，并向此地址发送所填密钥。此次不会发送会议内容。", draft.baseURL))
        }
    }

    private static let labelWidth: CGFloat = 148

    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: Self.labelWidth, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var modelChoices: [String] {
        var choices = draft.savedModelIDs
        for id in availableModels where !choices.contains(id) {
            choices.append(id)
        }
        return choices
    }

    private func addEnteredModel() {
        let id = modelEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        if !draft.savedModelIDs.contains(id) {
            draft.savedModelIDs.append(id)
        }
        draft.modelID = id
        modelEntry = ""
    }

    private func removeModel(_ id: String) {
        draft.savedModelIDs.removeAll { $0 == id }
        availableModels.removeAll { $0 == id }
        if draft.modelID == id {
            draft.modelID = modelChoices.first ?? ""
        }
    }

    private func prepare(_ action: Action) {
        addEnteredModel()
        do { draft = try draft.validated(requireModel: action == .save); error = nil; confirmation = action }
        catch { self.error = error.localizedDescription }
    }

    private func save() {
        do { try configuration.save(draft, key: key); key = ""; dismiss() }
        catch { self.error = error.localizedDescription }
    }

    private func fetchModels() async {
        fetching = true
        defer { fetching = false }
        do {
            var secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if secret.isEmpty, configuration.profiles.contains(where: { $0.id == draft.id && $0.baseURL == draft.baseURL }) {
                secret = try LLMKeychain.read(draft)
            }
            guard draft.isLoopback || !secret.isEmpty else { throw llmError(tr("请输入 API 密钥。")) }
            availableModels = try await RemoteLLMClient.models(profile: draft, key: secret)
            for id in availableModels where !draft.savedModelIDs.contains(id) {
                draft.savedModelIDs.append(id)
            }
            if draft.modelID.isEmpty, let first = draft.savedModelIDs.first {
                draft.modelID = first
            }
            if availableModels.isEmpty { error = tr("服务未返回模型列表，可以手动填写模型 ID。") }
        } catch { self.error = error.localizedDescription }
    }
}
