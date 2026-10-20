import SwiftUI

/// Messages waiting for the current answer to finish, shown above the composer.
struct ChatQueueList: View {
    var model: AppModel
    var chatID: UUID
    /// Moves a queued message back into the composer for editing.
    var onEdit: (QueuedPrompt) -> Void

    private var items: [QueuedPrompt] { model.queued(in: chatID) }
    private var paused: Bool { model.queuePaused.contains(chatID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Space.s2) {
                Text(paused ? trf("已暂停 · %d 条", items.count) : trf("排队中 %d 条", items.count))
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
                if paused {
                    Button(tr("继续")) { model.resumeQueue(chatID) }
                        .buttonStyle(.link.clicking())
                        .font(AppFont.caption)
                }
                Spacer(minLength: 0)
                Button(tr("全部清除")) { model.clearQueue(chatID) }
                    .buttonStyle(.plain.clicking())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                        row(item, number: offset + 1)
                            .draggable(item.id.uuidString)
                            .dropDestination(for: String.self) { dropped, _ in
                                guard let raw = dropped.first, let id = UUID(uuidString: raw) else { return false }
                                model.moveQueued(id, toOffset: offset)
                                return true
                            }
                    }
                }
            }
            .frame(maxHeight: min(CGFloat(items.count), 3) * 30)
        }
    }

    private func row(_ item: QueuedPrompt, number: Int) -> some View {
        HStack(spacing: Space.s2) {
            Text("\(number)")
                .font(AppFont.caption.monospacedDigit())
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 14, alignment: .trailing)
            if !item.images.isEmpty {
                Label("\(item.images.count)", systemImage: "photo")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .labelStyle(.titleAndIcon)
            }
            Text(item.text.isEmpty ? tr("图片") : item.text)
                .font(AppFont.secondary)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Space.s2)
            icon("pencil", help: tr("编辑")) { onEdit(item) }
            icon("arrow.uturn.right", help: tr("立即发送")) { model.sendQueuedNow(item.id) }
            icon("xmark", help: tr("移除")) { model.removeQueued(item.id) }
        }
        .padding(.horizontal, Space.s2)
        .frame(height: 28)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func icon(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain.clicking())
        .help(help)
        .accessibilityLabel(help)
    }
}
