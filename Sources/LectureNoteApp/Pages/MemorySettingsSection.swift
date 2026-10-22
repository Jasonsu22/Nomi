import SwiftUI

/// What Nomi has learned about the student, with a switch, editing, pinning and deleting.
struct MemorySettingsSection: View {
    var model: AppModel
    @State private var confirmingClear = false

    private var memory: UserMemory { model.memory }

    var body: some View {
        SettingsSection(tr("记忆")) {
            SettingsRow(tr("自动记忆")) {
                SettingsSwitch(label: tr("自动记忆"), isOn: Binding(get: { model.memoryEnabled }, set: { memory.setEnabled($0) }))
            }
            if memory.items.isEmpty {
                Text(model.memoryEnabled ? tr("还没有记忆。多聊几次，Nomi 会慢慢了解你的习惯。") : tr("自动记忆已关闭。"))
                    .font(AppFont.secondary)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingsRowPadding()
            } else {
                ForEach(sortedItems) { item in MemoryRow(item: item, memory: memory) }
            }
        } footer: {
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(tr("Nomi 会从对话里记下你的偏好、课程和目标，只存在这台 Mac 上。使用 API 模型时，相关记忆会随问题发送。"))
                Spacer(minLength: Space.s3)
                if !memory.items.isEmpty {
                    Button(tr("清空记忆"), role: .destructive) { confirmingClear = true }
                        .buttonStyle(.link.clicking())
                        .foregroundStyle(.red)
                }
            }
        }
        .alert(tr("清空所有记忆？"), isPresented: $confirmingClear) {
            Button(tr("清空"), role: .destructive) { memory.clear() }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("Nomi 会忘记目前学到的内容，之后从新的对话重新学习。"))
        }
    }

    /// Pinned first, then the most recently learned.
    private var sortedItems: [MemoryItem] {
        memory.items.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}

private struct MemoryRow: View {
    var item: MemoryItem
    var memory: UserMemory
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: Space.s3) {
            Text(item.kind.title)
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(AppColor.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppColor.accentSoft, in: Capsule())
                .fixedSize()
            TextField(tr("记忆内容"), text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(AppFont.body)
                .foregroundStyle(AppColor.textPrimary)
                .focused($editing)
                .onSubmit(commit)
                .onChange(of: editing) { _, focused in if !focused { commit() } }
            Button { memory.togglePin(item.id) } label: {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .foregroundStyle(item.pinned ? AppColor.accent : AppColor.textSecondary)
            }
            .buttonStyle(.plain.clicking())
            .help(item.pinned ? tr("取消置顶") : tr("置顶：每次都告诉模型"))
            Button { memory.delete(item.id) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(AppColor.textSecondary)
            }
            .buttonStyle(.plain.clicking())
            .help(tr("删除这条记忆"))
        }
        .settingsRowPadding()
        .onAppear { draft = item.text }
        .onChange(of: item.text) { _, text in if !editing { draft = text } }
    }

    private func commit() {
        guard draft != item.text else { return }
        memory.update(item.id, text: draft)
    }
}
