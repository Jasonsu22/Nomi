import SwiftUI

/// Settings › Live speakers: tell speakers apart while recording, and which model does it. The model
/// is chosen like the local language model: a row showing the one in use, and a popover listing each
/// model with Download, Use and Delete. Each model is a separate download kept in Application
/// Support/FluidAudio; none ship with Nomi.
struct SpeakerModelsSection: View {
    @AppStorage(SpeakerModelKind.enabledKey) private var enabled = true

    var body: some View {
        SettingsSection(tr("实时区分说话人（实验）")) {
            SettingsRow(tr("录音时标出说话人"), detail: tr("在这台 Mac 上边录边分出每个人的声音，转写里每段话前会标出说话人 1、2、3…（你标出自己后会显示“我”），可以右键改名。下一次开始录音时生效。")) {
                SettingsSwitch(label: tr("录音时标出说话人"), isOn: $enabled)
            }
            SpeakerModelPicker()
        } footer: {
            Text(tr("三个模型都在两节真实课堂录音上测过，和录音结束后的分析结果一致率在 92%–100%。"))
        }
    }
}

struct SpeakerModelPicker: View {
    @AppStorage(SpeakerModelKind.choiceKey) private var chosen = SpeakerModelKind.standard.rawValue
    @State private var showingModels = false
    @State private var downloading: Set<SpeakerModelKind> = []
    @State private var failed: [SpeakerModelKind: String] = [:]
    @State private var deleting: SpeakerModelKind?
    /// Bumped after a download or removal, so the rows read the disk again.
    @State private var refresh = 0

    private var current: SpeakerModelKind { SpeakerModelKind(rawValue: chosen) ?? .standard }

    private var status: String {
        _ = refresh
        if downloading.contains(current) { return tr("正在下载…") }
        return current.isDownloaded ? tr("使用中") : tr("未下载")
    }

    var body: some View {
        SettingsRow(tr("说话人模型")) {
            Button {
                showingModels = true
            } label: {
                SettingsPopUpLabel {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(current.title).font(AppFont.secondary.weight(.medium)).foregroundStyle(AppColor.textPrimary)
                        Text(status).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("选择说话人模型"))
            .popover(isPresented: $showingModels, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(tr("说话人模型"))
                        .font(AppFont.sectionTitle).padding(Space.s4)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(SpeakerModelKind.allCases) { option($0) }
                    }
                    .id(refresh)
                    Text(tr("来源：Hugging Face。下载完成后点击「使用」切换，下一次开始录音时生效。"))
                        .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                        .padding(Space.s4)
                }
                .frame(width: 440)
            }
        }
        .alert(tr("删除说话人模型？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { kind in
            Button(tr("删除"), role: .destructive) {
                kind.remove()
                if chosen == kind.rawValue { chosen = SpeakerModelKind.standard.rawValue }
                refresh += 1
            }
            Button(tr("取消"), role: .cancel) {}
        } message: { kind in
            Text(trf("将删除 %@。之后录音时用它区分说话人需要重新下载。", kind.title))
        }
    }

    private func option(_ kind: SpeakerModelKind) -> some View {
        let installed = kind.isDownloaded
        let active = chosen == kind.rawValue && installed
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .center, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title).font(AppFont.body.weight(.medium)).foregroundStyle(AppColor.textPrimary)
                    Text("\(kind.detail) · \(kind.size)")
                        .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(tr("查看模型"), destination: kind.page)
                        .font(AppFont.caption)
                        .clickCursor()
                }
                Spacer()
                VStack(alignment: .center, spacing: Space.s2) {
                    if downloading.contains(kind) {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(tr("正在下载…"))
                    } else if active {
                        Label(tr("使用中"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppColor.accent)
                            .frame(minWidth: 60, alignment: .center)
                    } else if installed {
                        Button {
                            chosen = kind.rawValue
                        } label: {
                            Text(tr("使用")).frame(minWidth: 60)
                        }
                    } else {
                        Button {
                            download(kind)
                        } label: {
                            Label(failed[kind] == nil ? tr("下载") : tr("重试"), systemImage: "arrow.down.circle")
                                .frame(minWidth: 60, alignment: .center)
                        }
                    }
                    if installed && !downloading.contains(kind) {
                        Button(role: .destructive) {
                            showingModels = false
                            deleting = kind
                        } label: {
                            Label(tr("删除"), systemImage: "trash")
                                .foregroundStyle(.red)
                                .frame(minWidth: 60)
                        }
                        .tint(.red)
                    }
                }
                .font(AppFont.caption)
                .controlSize(.small)
                .buttonStyle(.bordered.clicking())
            }
            if let error = failed[kind] {
                Text(error).font(AppFont.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private func download(_ kind: SpeakerModelKind) {
        downloading.insert(kind)
        failed[kind] = nil
        Task {
            do {
                _ = try await kind.load()
                chosen = kind.rawValue
            } catch {
                failed[kind] = trf("下载失败：%@", error.localizedDescription)
            }
            downloading.remove(kind)
            refresh += 1
        }
    }
}
