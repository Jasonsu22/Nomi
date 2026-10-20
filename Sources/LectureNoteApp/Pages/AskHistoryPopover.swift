import SwiftUI

struct AskHistoryPopover: View {
    var model: AppModel
    var anchorMeetingID: UUID? = nil
    var currentID: UUID? = nil
    var onRename: (ChatSession) -> Void
    var onDelete: (ChatSession) -> Void
    var onClose: () -> Void
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(tr("搜索对话"), text: $query)
                .textFieldStyle(.plain)
                .font(AppFont.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                .padding(Space.s3)
            if filtered.isEmpty {
                Text(tr("还没有对话"))
                    .font(AppFont.secondary)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.s3) {
                        ForEach(groups, id: \.title) { group in
                            Text(group.title)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                                .padding(.horizontal, Space.s2)
                            ForEach(group.sessions) { session in
                                AskHistoryRow(
                                    title: session.displayTitle,
                                    subtitle: subtitle(session),
                                    time: formatRelativeTime(session.updatedAt),
                                    current: session.id == (currentID ?? model.currentChatID),
                                    onOpen: {
                                        model.openChat(session.id, forAnchor: anchorMeetingID)
                                        onClose()
                                    },
                                    onRename: { onRename(session) },
                                    onDelete: { onDelete(session) }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, Space.s2)
                    .padding(.bottom, Space.s3)
                }
            }
        }
        .frame(width: anchorMeetingID == nil ? 360 : 300, height: filtered.isEmpty ? 220 : (anchorMeetingID == nil ? 420 : 320))
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(AppColor.separator))
        .shadow(color: .black.opacity(0.16), radius: 22, y: 10)
    }

    private var pool: [ChatSession] {
        model.chatHistory(anchoredTo: anchorMeetingID)
    }

    private var filtered: [ChatSession] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return pool }
        return pool.filter { session in
            session.displayTitle.localizedStandardContains(needle)
                || session.turns.contains { $0.question.localizedStandardContains(needle) || $0.answer.localizedStandardContains(needle) }
        }
    }

    private var groups: [(title: String, sessions: [ChatSession])] {
        let calendar = Calendar.current
        let buckets: [(String, (Date) -> Bool)] = [
            (tr("今天"), calendar.isDateInToday),
            (tr("昨天"), calendar.isDateInYesterday),
            (tr("更早"), { !calendar.isDateInToday($0) && !calendar.isDateInYesterday($0) }),
        ]
        return buckets.compactMap { title, match in
            let sessions = filtered.filter { match($0.updatedAt) }
            return sessions.isEmpty ? nil : (title, sessions)
        }
    }

    private func subtitle(_ session: ChatSession) -> String {
        if let id = session.anchorMeetingID, let meeting = model.meetings.first(where: { $0.id == id }) {
            return meeting.title
        }
        return session.scope.chipTitle(
            meetings: model.chatMeetingItems(),
            sources: model.chatSourceItems(),
            categories: model.chatCategoryNames()
        )
    }

}

private struct AskHistoryRow: View {
    var title: String
    var subtitle: String
    var time: String
    var current: Bool
    var onOpen: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppFont.secondary.weight(.medium))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(time)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    if current {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColor.accent)
                    }
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Radius.tag, style: .continuous))
        }
        .buttonStyle(.plain.clicking())
        .onHover { hovering = $0 }
        .animation(Motion.fade(reduceMotion), value: hovering)
        .contextMenu {
            Button(tr("重命名"), action: onRename)
            Button(tr("删除"), role: .destructive, action: onDelete)
        }
    }

    private var fill: Color {
        if current {
            return hovering ? AppColor.selection : AppColor.accentSoft
        }
        return hovering ? AppColor.surfaceInset : Color.clear
    }
}
