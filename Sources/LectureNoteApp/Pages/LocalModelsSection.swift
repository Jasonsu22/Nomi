import AppKit
import SwiftUI

struct LocalModelsSection: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(tr("本地模型"))
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.textPrimary)
            VStack(spacing: 0) {
                LocalModelPicker(model: model, role: .asr)
                Rectangle().fill(AppColor.separator).frame(height: 1).padding(.leading, Space.s4)
                LocalModelPicker(model: model, role: .translator)
            }
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            HStack {
                Text(tr("下载一次，即可在本机离线使用。"))
                Spacer()
                Button(tr("打开模型文件夹")) {
                    let root = LocalModelDefinition.root
                    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(root)
                }
                .buttonStyle(.link.clicking())
            }
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
            if model.engine.session.phase != .idle {
                Text(tr("录制结束后可以切换模型。"))
                    .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            }
        }
        .onAppear { model.localModels.refresh() }
    }
}

struct LocalModelPicker: View {
    var model: AppModel
    var role: LocalModelRole
    @State private var showingModels = false
    @State private var deletingModel: LocalModelDefinition?
    @State private var modelListHeight: CGFloat = 0

    private var runtime: LocalModelRuntimeStatus.Model? {
        (model.engine as? LocalEngine)?.modelStatus?.model(for: role)
    }

    private var current: LocalModelDefinition {
        LocalModelDefinition.catalog.first { item in
            item.supports(role) && item.directory.path == runtime?.path
        } ?? LocalModelDefinition.selected(for: role)
    }

    private var status: String {
        if model.localModels.deletingID == current.id { return tr("正在删除…") }
        if isSwitchingRole {
            return tr("正在加载…")
        }
        if model.engine.readiness == .preparing { return tr("正在加载…") }
        if runtime?.loaded == true { return tr("使用中") }
        if runtime?.error != nil { return tr("加载失败") }
        return model.localModels.installed.contains(current.id) ? tr("未加载") : tr("未下载")
    }

    private var isSwitchingRole: Bool {
        model.localModels.switchingID != nil && model.localModels.switchingRole == role
    }

    var body: some View {
        HStack(spacing: Space.s4) {
            Text(role.title).font(AppFont.body).foregroundStyle(AppColor.textPrimary)
            Spacer()
            Button {
                model.localModels.refresh()
                showingModels = true
            } label: {
                HStack(spacing: Space.s3) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(current.name).font(AppFont.secondary.weight(.medium)).foregroundStyle(AppColor.textPrimary)
                        Text(status).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(AppColor.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain.clicking())
            .accessibilityLabel(trf("选择%@", role.title))
            .popover(isPresented: $showingModels, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(role.title)
                        .font(AppFont.sectionTitle).padding(Space.s4)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(LocalModelDefinition.catalog.filter { $0.supports(role) }) { item in option(item) }
                        }
                        .onGeometryChange(for: CGFloat.self) { geometry in
                            geometry.size.height
                        } action: { height in
                            modelListHeight = height
                        }
                    }
                    .frame(height: min(400, modelListHeight))
                    Text(tr("来源：Hugging Face。下载完成后点击「使用」切换。"))
                        .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                        .padding(Space.s4)
                }
                .frame(width: 440)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
        .alert(tr("删除本地模型？"), isPresented: Binding(get: { deletingModel != nil }, set: { if !$0 { deletingModel = nil } }), presenting: deletingModel) { item in
            Button(tr("删除"), role: .destructive) { Task { await model.deleteLocalModel(item) } }
            Button(tr("取消"), role: .cancel) {}
        } message: { item in
            Text(trf("将卸载 %@ 并移到废纸篓。使用此模型的功能会暂停，可重新下载或从废纸篓恢复。", item.name))
        }
    }

    private func option(_ item: LocalModelDefinition) -> some View {
        let installed = model.localModels.installed.contains(item.id)
        let active = !isSwitchingRole && runtime?.loaded == true && runtime?.path == item.directory.path
        let progress = model.localModels.downloads[item.id]
        let switching = model.localModels.switchingID == item.id
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .center, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(AppFont.body.weight(.medium)).foregroundStyle(AppColor.textPrimary)
                    Text("\(item.quantization) · \(item.sizeLabel)")
                        .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                    Link(tr("查看模型"), destination: URL(string: "https://huggingface.co/\(item.repository)")!)
                        .font(AppFont.caption)
                        .clickCursor()
                }
                Spacer()
                VStack(alignment: .center, spacing: Space.s2) {
                    if switching {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(tr("正在加载…"))
                    } else if progress != nil {
                        Button(tr("取消")) { model.localModels.cancel(item) }
                    } else if active {
                        Label(tr("使用中"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppColor.accent)
                            .frame(minWidth: 60, alignment: .center)
                    } else if installed {
                        Button {
                            Task { await model.selectLocalModel(item, for: role) }
                        } label: {
                            Text(tr("使用")).frame(minWidth: 60)
                        }
                        .disabled(!model.canSwitchModels)
                    } else {
                        Button {
                            model.localModels.download(item)
                        } label: {
                            Label(model.localModels.errors[item.id] == nil ? tr("下载") : tr("重试"), systemImage: "arrow.down.circle")
                                .frame(minWidth: 60, alignment: .center)
                        }
                    }
                    if installed {
                        Button(role: .destructive) {
                            showingModels = false
                            deletingModel = item
                        } label: {
                            Label(tr("删除"), systemImage: "trash")
                                .foregroundStyle(.red)
                                .frame(minWidth: 60)
                        }
                        .tint(.red)
                        .disabled(!model.canSwitchModels)
                    }
                }
                .font(AppFont.caption)
                .controlSize(.small)
                .buttonStyle(.bordered.clicking())
            }
            if let progress {
                if progress.total > 0 {
                    ProgressView(value: progress.fraction).tint(AppColor.accent)
                    Text(progress.verifying ? tr("正在校验文件…") : "\(ByteCountFormatter.string(fromByteCount: progress.completed, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: progress.total, countStyle: .file))")
                        .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                } else {
                    HStack(spacing: Space.s2) {
                        ProgressView().controlSize(.small)
                        Text(tr("正在获取下载信息…")).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            if let error = model.localModels.errors[item.id] ?? (runtime?.path == item.directory.path ? runtime?.error : nil) {
                Text(error).font(AppFont.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }
}
