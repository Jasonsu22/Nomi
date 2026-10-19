import SwiftUI

struct MeetingsPage: View {
    @Bindable var model: AppModel
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            MeetingListView(model: model, reduceMotion: reduceMotion)
                .opacity(model.openMeetingID == nil ? 1 : 0)
                .allowsHitTesting(model.openMeetingID == nil)
                .accessibilityHidden(model.openMeetingID != nil)
            if let meetingID = model.openMeetingID {
                MeetingDetailView(model: model, meetingID: meetingID, reduceMotion: reduceMotion)
                    .id(meetingID)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
            }
        }
    }
}

struct MeetingListView: View {
    @Bindable var model: AppModel
    var reduceMotion: Bool
    @FocusState private var searchFocused: Bool
    @Namespace private var chipNamespace
    @State private var creating = false
    @State private var editing: MeetingCategory?
    @State private var draft = CategoryDraft()
    @State private var renaming: Meeting?
    @State private var renameDraft = ""
    @State private var resettingTime: Meeting?
    @State private var deletingMeeting: Meeting?
    @State private var deletingCategory: MeetingCategory?
    @State private var managing = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var confirmingBulkDelete = false
    @State private var movingIDs: Set<UUID> = []
    @State private var creatingForMove = false

    var body: some View {
        let visible = model.visibleMeetings
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                SearchField(text: $model.query, isFocused: $searchFocused)
                chips
                if visible.isEmpty {
                    Text(tr("没有匹配的会议"))
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Space.s4)
                } else {
                    sections(visible)
                }
            }
            .pageColumn()
            .padding(.top, 28)
            .padding(.bottom, Space.s7)
        }
        .onChange(of: model.searchRequest) { _, _ in
            searchFocused = true
        }
        .sheet(item: $resettingTime) { meeting in
            StartTimeEditor(date: Binding(
                get: { model.meetings.first { $0.id == meeting.id }?.startedAt ?? meeting.startedAt },
                set: { model.setStartTime(meeting: meeting.id, to: $0) }
            )) {
                resettingTime = nil
            }
            .frame(width: 320)
        }
        .alert(tr("重命名"), isPresented: renamingPresented) {
            TextField(tr("名称"), text: $renameDraft)
            Button(tr("确定")) {
                if let renaming {
                    model.rename(id: renaming.id, to: renameDraft)
                }
            }
            Button(tr("取消"), role: .cancel) {}
        }
        .alert(tr("删除这场会议？"), isPresented: deletingMeetingPresented) {
            Button(tr("删除"), role: .destructive) {
                if let deletingMeeting {
                    removeMeetings([deletingMeeting.id])
                }
            }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("转写会一起删掉。"))
        }
        .confirmationDialog(
            trf("删除分类「%@」？", deletingCategory?.name ?? ""),
            isPresented: deletingCategoryPresented,
            titleVisibility: .visible
        ) {
            Button(tr("删除分类"), role: .destructive) {
                if let deletingCategory {
                    model.deleteCategory(deletingCategory.id)
                }
            }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("这个分类下的会议和资料会变成未分类。"))
        }
        .sheet(isPresented: $creatingForMove) {
            CategoryEditor(title: tr("新建分类"), draft: $draft) {
                if let id = model.addCategory(
                    name: draft.name,
                    colorIndex: draft.colorIndex,
                    symbol: draft.symbol,
                    select: false
                ) {
                    move(movingIDs, to: id)
                }
                creatingForMove = false
                movingIDs = []
            }
        }
        .alert(trf("删除这 %d 场会议？", selectedIDs.count), isPresented: $confirmingBulkDelete) {
            Button(tr("删除"), role: .destructive) {
                removeMeetings(selectedIDs, leaveManageMode: true)
            }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("转写和录音会一起删掉，删掉之后无法恢复。"))
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text(tr("会议"))
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: Space.s3)
            TrailingBarSwap(managing: managing, reduceMotion: reduceMotion) {
                HStack(spacing: Space.s3) {
                    PillButton(title: tr("管理")) {
                        selectedIDs.removeAll()
                        managing = true
                    }
                    groupingToggle
                }
            } manage: {
                HStack(spacing: Space.s3) {
                    Text(trf("已选 %d", selectedIDs.count))
                        .font(AppFont.secondary.weight(.medium))
                        .foregroundStyle(AppColor.textSecondary)
                    PillButton(title: tr("全选")) { selectAllVisible() }
                    PillButton(title: tr("完成")) { endManaging() }
                    PillButton(title: tr("导出")) {
                        model.export(model.meetings.filter { selectedIDs.contains($0.id) })
                    }
                    .help(tr("把选中的会议存成 Markdown"))
                    .disabled(selectedIDs.isEmpty)
                    .opacity(selectedIDs.isEmpty ? 0.4 : 1)
                    PillMenu(title: tr("移到分类"), enabled: !selectedIDs.isEmpty) {
                        categoryMoveItems(for: selectedIDs)
                    }
                    PillButton(title: tr("删除"), tint: .red) { confirmingBulkDelete = true }
                        .disabled(selectedIDs.isEmpty)
                        .opacity(selectedIDs.isEmpty ? 0.4 : 1)
                }
            }
        }
        // The time/category capsule is taller than the text buttons. Without a
        // fixed height, hiding it in manage mode shortens this row and the
        // search field and list move up.
        .frame(height: 36)
    }

    private var groupingToggle: some View {
        HStack(spacing: 2) {
            groupingButton(.time, tr("时间"))
            groupingButton(.category, tr("分类"))
        }
        .padding(3)
        .background(AppColor.surface, in: Capsule())
    }

    private func groupingButton(_ grouping: MeetingGrouping, _ title: String) -> some View {
        let selected = model.grouping == grouping
        return Button {
            withAnimation(Motion.layout(reduceMotion)) {
                model.grouping = grouping
            }
        } label: {
            Text(title)
                .font(AppFont.secondary.weight(.medium))
                .foregroundStyle(selected ? AppColor.onSelection : AppColor.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(selected ? AppColor.selection : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain.clicking())
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                chip(title: trf("全部 %d", model.count(in: .all)), dot: nil, filter: .all)
                ForEach(model.categories.sorted { $0.sortOrder < $1.sortOrder }) { category in
                    chip(
                        title: "\(category.name) \(model.count(in: .category(category.id)))",
                        dot: CategoryPalette.ink(category.colorIndex),
                        filter: .category(category.id)
                    )
                    .contextMenu {
                        Button(tr("编辑")) {
                            draft = CategoryDraft(name: category.name, colorIndex: category.colorIndex, symbol: category.symbol)
                            editing = category
                        }
                        Button(role: .destructive) {
                            deletingCategory = category
                        } label: {
                            Text(tr("删除")).foregroundStyle(.red)
                        }
                    }
                    .popover(isPresented: editingPresented(category), arrowEdge: .bottom) {
                        CategoryEditor(title: tr("编辑分类"), draft: $draft) {
                            model.updateCategory(category.id, name: draft.name, colorIndex: draft.colorIndex, symbol: draft.symbol)
                            editing = nil
                        }
                    }
                    .categoryDrag(category.id, reduceMotion: reduceMotion) { dragged, target in
                        model.placeCategory(dragged, at: target)
                    }
                    .help(tr("拖动调整顺序"))
                }
                chip(
                    title: trf("未分类 %d", model.count(in: .uncategorized)),
                    dot: CategoryPalette.ink(CategoryPalette.uncategorizedIndex),
                    filter: .uncategorized
                )
                newCategoryButton
            }
        }
    }

    private func chip(title: String, dot: Color?, filter: CategoryFilter) -> some View {
        let selected = model.activeFilter == filter
        return Button {
            withAnimation(Motion.layout(reduceMotion)) {
                model.filter = filter
            }
        } label: {
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(dot).frame(width: 8, height: 8)
                }
                Text(title)
                    .font(AppFont.secondary.weight(.medium))
            }
            .foregroundStyle(selected ? AppColor.onSelection : AppColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background {
                if selected {
                    Capsule()
                        .fill(AppColor.selection)
                        .matchedGeometryEffect(id: "category", in: chipNamespace)
                }
            }
        }
        .buttonStyle(.plain.clicking())
    }

    private var newCategoryButton: some View {
        Button {
            draft = CategoryDraft(
                name: "",
                colorIndex: model.categories.count % CategoryPalette.swatches.count,
                symbol: CategorySymbols.all[0]
            )
            creating = true
        } label: {
            Text(tr("＋ 新建分类"))
                .font(AppFont.secondary.weight(.medium))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .overlay {
                    Capsule().strokeBorder(AppColor.outline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
        }
        .buttonStyle(.plain.clicking())
        .popover(isPresented: $creating, arrowEdge: .bottom) {
            CategoryEditor(title: tr("新建分类"), draft: $draft) {
                model.addCategory(name: draft.name, colorIndex: draft.colorIndex, symbol: draft.symbol)
                creating = false
            }
        }
    }

    private func sections(_ meetings: [Meeting]) -> some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            ForEach(sectionModels(meetings)) { section in
                VStack(alignment: .leading, spacing: Space.s3) {
                    CategorySectionTitle(title: section.title, count: section.meetings.count, colorIndex: section.colorIndex)
                    if section.showsNow {
                        NowDivider()
                    }
                    VStack(spacing: Space.s3) {
                        ForEach(section.meetings) { meeting in
                            card(meeting)
                                .transition(removalTransition)
                        }
                    }
                    .animation(Motion.layout(reduceMotion), value: section.meetings.map(\.id))
                }
                .transition(.opacity)
            }
        }
    }

    /// The removed card fades. The cards under it move up in the same animation,
    /// instead of the gap closing on the next frame.
    private var removalTransition: AnyTransition {
        .asymmetric(
            insertion: insertionTransition(reduceMotion: reduceMotion),
            removal: .opacity
        )
    }

    private func removeMeetings(_ ids: Set<UUID>, leaveManageMode: Bool = false) {
        let removed = ids
        // The alert dismisses in a transaction that turns animations off.
        // Wait until that transaction ends, then delete.
        Task { @MainActor in
            withAnimation(Motion.layout(reduceMotion)) {
                model.deleteMeetings(removed)
                selectedIDs.subtract(removed)
            }
            guard leaveManageMode else { return }
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 0.32))
            managing = false
            selectedIDs.removeAll()
        }
    }

    private func card(_ meeting: Meeting) -> some View {
        let category = model.category(for: meeting.categoryID)
        return MeetingCard(
            meeting: meeting,
            symbol: category?.symbol ?? CategoryPalette.uncategorizedSymbol,
            colorIndex: category?.colorIndex ?? CategoryPalette.uncategorizedIndex,
            reduceMotion: reduceMotion,
            selected: managing && !meeting.isLive ? selectedIDs.contains(meeting.id) : nil
        ) {
            if managing {
                guard !meeting.isLive else { return }
                if selectedIDs.contains(meeting.id) {
                    selectedIDs.remove(meeting.id)
                } else {
                    selectedIDs.insert(meeting.id)
                }
            } else {
                withAnimation(Motion.layout(reduceMotion)) {
                    model.openMeeting(meeting.id)
                }
            }
        }
        .contextMenu {
            Button(tr("打开")) {
                withAnimation(Motion.layout(reduceMotion)) {
                    model.openMeeting(meeting.id)
                }
            }
            Button(tr("重命名")) {
                renameDraft = meeting.title
                renaming = meeting
            }
            Button(tr("重设时间")) {
                resettingTime = meeting
            }
            Menu(tr("移到分类")) {
                categoryMoveItems(for: moveTargets(meeting))
            }
            Button(tr("导出")) {
                model.export([meeting])
            }
            if !meeting.isLive {
                Button(role: .destructive) {
                    deletingMeeting = meeting
                } label: {
                    Text(tr("删除")).foregroundStyle(.red)
                }
            }
        }
    }

    /// A selected row moves the whole selection. Any other row moves only itself.
    private func moveTargets(_ meeting: Meeting) -> Set<UUID> {
        if managing, selectedIDs.contains(meeting.id) {
            return selectedIDs
        }
        return [meeting.id]
    }

    @ViewBuilder
    private func categoryMoveItems(for ids: Set<UUID>) -> some View {
        Button(tr("未分类")) { move(ids, to: nil) }
        ForEach(model.categories.sorted { $0.sortOrder < $1.sortOrder }) { category in
            Button(category.name) { move(ids, to: category.id) }
        }
        Divider()
        Button {
            movingIDs = ids
            draft = CategoryDraft(
                name: "",
                colorIndex: model.categories.count % CategoryPalette.swatches.count,
                symbol: CategorySymbols.all[0]
            )
            creatingForMove = true
        } label: {
            Label(tr("新建分类"), systemImage: "plus")
        }
    }

    private func move(_ ids: Set<UUID>, to categoryID: UUID?) {
        guard !ids.isEmpty else { return }
        withAnimation(Motion.layout(reduceMotion)) {
            model.assign(meetings: ids, category: categoryID)
        }
    }

    private func sectionModels(_ meetings: [Meeting]) -> [MeetingSection] {
        switch model.grouping {
        case .time:
            return timeSections(meetings)
        case .category:
            return categorySections(meetings)
        }
    }

    private func timeSections(_ meetings: [Meeting]) -> [MeetingSection] {
        let calendar = Calendar.current
        let today = meetings.filter { calendar.isDateInToday($0.startedAt) }.sorted(by: sortMeetings)
        let earlier = meetings.filter { !calendar.isDateInToday($0.startedAt) }.sorted { $0.startedAt > $1.startedAt }
        let searching = !model.appliedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var sections: [MeetingSection] = []
        if !today.isEmpty {
            sections.append(MeetingSection(id: "today", title: tr("今天"), colorIndex: nil, meetings: today, showsNow: !searching))
        }
        if !earlier.isEmpty {
            sections.append(MeetingSection(id: "earlier", title: tr("更早"), colorIndex: nil, meetings: earlier, showsNow: false))
        }
        return sections
    }

    private func categorySections(_ meetings: [Meeting]) -> [MeetingSection] {
        var sections: [MeetingSection] = []
        for category in model.categories.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let items = meetings.filter { $0.categoryID == category.id }.sorted(by: sortMeetings)
            guard !items.isEmpty else { continue }
            sections.append(MeetingSection(id: category.id.uuidString, title: category.name, colorIndex: category.colorIndex, meetings: items, showsNow: false))
        }
        let loose = meetings.filter { $0.categoryID == nil }.sorted(by: sortMeetings)
        if !loose.isEmpty {
            sections.append(MeetingSection(id: "none", title: tr("未分类"), colorIndex: CategoryPalette.uncategorizedIndex, meetings: loose, showsNow: false))
        }
        return sections
    }

    private func sortMeetings(_ lhs: Meeting, _ rhs: Meeting) -> Bool {
        if lhs.isLive != rhs.isLive { return lhs.isLive && !rhs.isLive }
        return lhs.startedAt > rhs.startedAt
    }

    private func selectAllVisible() {
        selectedIDs = Set(model.visibleMeetings.filter { !$0.isLive }.map(\.id))
    }

    private func endManaging() {
        managing = false
        selectedIDs.removeAll()
    }

    private var renamingPresented: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deletingMeetingPresented: Binding<Bool> {
        Binding(get: { deletingMeeting != nil }, set: { if !$0 { deletingMeeting = nil } })
    }

    private var deletingCategoryPresented: Binding<Bool> {
        Binding(get: { deletingCategory != nil }, set: { if !$0 { deletingCategory = nil } })
    }

    private func editingPresented(_ category: MeetingCategory) -> Binding<Bool> {
        Binding(
            get: { editing?.id == category.id },
            set: { if !$0 { editing = nil } }
        )
    }
}

private struct MeetingSection: Identifiable {
    var id: String
    var title: String
    var colorIndex: Int?
    var meetings: [Meeting]
    var showsNow: Bool
}
