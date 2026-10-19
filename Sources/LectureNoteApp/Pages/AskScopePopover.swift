import SwiftUI

enum ScopeColumn: Hashable {
    case all
    case category(UUID)
    case uncategorized
}

struct AskScopePopover: View {
    var model: AppModel
    var onClose: () -> Void
    @State private var column: ScopeColumn = .all

    private var meetings: [ScopeItem] { model.chatMeetingItems() }
    private var sources: [ScopeItem] { model.chatSourceItems() }
    private var scope: ChatScope { model.currentChat?.scope ?? ChatScope() }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                categoryColumn
                    .frame(width: 188)
                Divider()
                detailColumn
            }
            .frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: Space.s3) {
                Spacer()
                Button(tr("清空")) { change { $0.clear() } }
                    .buttonStyle(.plain)
                    .font(AppFont.secondary.weight(.medium))
                    .foregroundStyle(AppColor.textSecondary)
                Button(tr("完成")) { onClose() }
                    .buttonStyle(.plain)
                    .font(AppFont.secondary.weight(.medium))
                    .foregroundStyle(AppColor.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(AppColor.accent, in: Capsule())
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
        }
        .frame(width: 520, height: 360)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(AppColor.separator))
        .shadow(color: .black.opacity(0.16), radius: 22, y: 10)
    }

    private var categoryColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                categoryRow(
                    title: tr("全部"),
                    count: meetings.filter { !$0.live }.count + sources.count,
                    state: scope.stateAll(meetings: meetings, sources: sources),
                    dot: nil,
                    selected: column == .all
                ) {
                    change { $0.toggleAll(meetings: meetings, sources: sources) }
                } browse: {
                    column = .all
                }
                ForEach(model.categories.sorted { $0.sortOrder < $1.sortOrder }) { category in
                    categoryRow(
                        title: category.name,
                        count: count(in: category.id),
                        state: scope.state(of: category.id, meetings: meetings, sources: sources),
                        dot: CategoryPalette.ink(category.colorIndex),
                        selected: column == .category(category.id)
                    ) {
                        change { $0.toggleCategory(category.id, meetings: meetings, sources: sources) }
                    } browse: {
                        column = .category(category.id)
                    }
                }
                categoryRow(
                    title: tr("未分类"),
                    count: count(in: nil),
                    state: scope.state(of: nil, meetings: meetings, sources: sources),
                    dot: CategoryPalette.ink(CategoryPalette.uncategorizedIndex),
                    selected: column == .uncategorized
                ) {
                    change { $0.toggleCategory(nil, meetings: meetings, sources: sources) }
                } browse: {
                    column = .uncategorized
                }
            }
            .padding(Space.s2)
        }
    }

    private var detailColumn: some View {
        let rows = visibleContent
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(columnTitle)
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Space.s3)
                if column != .all {
                    Button(tr("全选这个分类")) { toggleBrowsedCategory() }
                        .buttonStyle(.plain)
                        .font(AppFont.secondary.weight(.medium))
                        .foregroundStyle(AppColor.accent)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s2)
            ScrollView {
                if rows.meetings.isEmpty && rows.sources.isEmpty {
                    Text(tr("这个分类里还没有内容。"))
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.s4)
                        .padding(.top, Space.s3)
                } else {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        if !rows.meetings.isEmpty {
                            meetingSection(rows.meetings)
                        }
                        if !rows.sources.isEmpty {
                            sourceSection(rows.sources)
                        }
                    }
                    .padding(.horizontal, Space.s3)
                    .padding(.bottom, Space.s3)
                }
            }
        }
    }

    private var columnTitle: String {
        switch column {
        case .all: tr("全部")
        case .category(let id): model.category(for: id)?.name ?? tr("分类")
        case .uncategorized: tr("未分类")
        }
    }

    private var visibleContent: (meetings: [Meeting], sources: [KnowledgeSource]) {
        switch column {
        case .all:
            return (model.meetings, model.sources)
        case .category(let id):
            return (
                model.meetings.filter { $0.categoryID == id },
                model.sources.filter { $0.categoryID == id }
            )
        case .uncategorized:
            return (
                model.meetings.filter { $0.categoryID == nil },
                model.sources.filter { $0.categoryID == nil }
            )
        }
    }

    private func meetingSection(_ items: [Meeting]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tr("会议"))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, Space.s2)
            ForEach(items) { meeting in
                itemRow(
                    title: meeting.title,
                    detail: meeting.isLive ? tr("录制中") : formatMonthDay(meeting.startedAt),
                    state: meetingState(meeting),
                    enabled: !meeting.isLive
                ) {
                    guard let item = meetings.first(where: { $0.id == meeting.id }) else { return }
                    change { $0.toggleMeeting(item, meetings: meetings, sources: sources) }
                }
            }
        }
    }

    private func sourceSection(_ items: [KnowledgeSource]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tr("资料"))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, Space.s2)
            ForEach(items) { item in
                itemRow(
                    title: item.title,
                    detail: formatMonthDay(item.importedAt),
                    state: sourceState(item),
                    enabled: true
                ) {
                    guard let scopeItem = sources.first(where: { $0.id == item.id }) else { return }
                    change { $0.toggleSource(scopeItem, meetings: meetings, sources: sources) }
                }
            }
        }
    }

    private func meetingState(_ meeting: Meeting) -> ScopeCheck {
        guard !meeting.isLive else { return .off }
        return scope.selectedMeetings(meetings).contains(meeting.id) ? .on : .off
    }

    private func sourceState(_ source: KnowledgeSource) -> ScopeCheck {
        scope.selectedSources(sources).contains(source.id) ? .on : .off
    }

    private func categoryRow(
        title: String,
        count: Int,
        state: ScopeCheck,
        dot: Color?,
        selected: Bool,
        toggle: @escaping () -> Void,
        browse: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Space.s2) {
            ScopeCheckBox(state: state, action: toggle)
            Button(action: browse) {
                HStack(spacing: Space.s2) {
                    if let dot {
                        Circle().fill(dot).frame(width: 8, height: 8)
                    }
                    Text(title)
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: Space.s2)
                    Text("\(count)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 6)
        .background(selected ? AppColor.surfaceInset : Color.clear, in: RoundedRectangle(cornerRadius: Radius.tag, style: .continuous))
    }

    private func itemRow(title: String, detail: String, state: ScopeCheck, enabled: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: Space.s2) {
                Image(systemName: state == .on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(state == .on ? AppColor.accent : AppColor.textSecondary)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.secondary)
                        .foregroundStyle(enabled ? AppColor.textPrimary : AppColor.textSecondary)
                        .lineLimit(1)
                    Text(detail)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s2)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }

    private func count(in category: UUID?) -> Int {
        meetings.filter { !$0.live && $0.categoryID == category }.count + sources.filter { $0.categoryID == category }.count
    }

    private func toggleBrowsedCategory() {
        switch column {
        case .all:
            change { $0.toggleAll(meetings: meetings, sources: sources) }
        case .category(let id):
            change { $0.toggleCategory(id, meetings: meetings, sources: sources) }
        case .uncategorized:
            change { $0.toggleCategory(nil, meetings: meetings, sources: sources) }
        }
    }

    private func change(_ body: (inout ChatScope) -> Void) {
        var next = scope
        body(&next)
        model.updateChatScope(next)
    }
}

struct ScopeCheckBox: View {
    var state: ScopeCheck
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(state == .off ? AppColor.textSecondary : AppColor.accent)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private var symbol: String {
        switch state {
        case .on: "checkmark.circle.fill"
        case .mixed: "minus.circle.fill"
        case .off: "circle"
        }
    }
}
