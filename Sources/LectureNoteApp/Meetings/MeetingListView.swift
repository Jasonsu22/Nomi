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
    @State private var deletingMeeting: Meeting?
    @State private var deletingCategory: MeetingCategory?

    var body: some View {
        let visible = model.visibleMeetings
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                SearchField(text: $model.query, isFocused: $searchFocused)
                chips
                if visible.isEmpty {
                    Text("没有匹配的会议")
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
        .alert("重命名", isPresented: renamingPresented) {
            TextField("名称", text: $renameDraft)
            Button("确定") {
                if let renaming {
                    model.rename(id: renaming.id, to: renameDraft)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("删除这场会议？", isPresented: deletingMeetingPresented) {
            Button("删除", role: .destructive) {
                if let deletingMeeting {
                    model.deleteMeeting(deletingMeeting.id)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("转写会一起删掉。")
        }
        .confirmationDialog(
            "删除分类「\(deletingCategory?.name ?? "")」？",
            isPresented: deletingCategoryPresented,
            titleVisibility: .visible
        ) {
            Button("删除分类", role: .destructive) {
                if let deletingCategory {
                    model.deleteCategory(deletingCategory.id)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这个分类下的会议会变成未分类。")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text("会议")
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: Space.s3)
            PillButton(title: "导出") {
                model.export(model.visibleMeetings)
            }
            .help("把当前筛选出的会议存成 Markdown")
            groupingToggle
        }
    }

    private var groupingToggle: some View {
        HStack(spacing: 2) {
            groupingButton(.time, "时间")
            groupingButton(.category, "分类")
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
                .font(AppFont.caption)
                .foregroundStyle(selected ? AppColor.onSelection : AppColor.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(selected ? AppColor.selection : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                chip(title: "全部 \(model.count(in: .all))", dot: nil, filter: .all)
                ForEach(model.categories.sorted { $0.sortOrder < $1.sortOrder }) { category in
                    chip(
                        title: "\(category.name) \(model.count(in: .category(category.id)))",
                        dot: CategoryPalette.ink(category.colorIndex),
                        filter: .category(category.id)
                    )
                    .contextMenu {
                        Button("编辑") {
                            draft = CategoryDraft(name: category.name, colorIndex: category.colorIndex, symbol: category.symbol)
                            editing = category
                        }
                        Button("删除", role: .destructive) {
                            deletingCategory = category
                        }
                    }
                    .popover(isPresented: editingPresented(category), arrowEdge: .bottom) {
                        CategoryEditor(title: "编辑分类", draft: $draft) {
                            model.updateCategory(category.id, name: draft.name, colorIndex: draft.colorIndex, symbol: draft.symbol)
                            editing = nil
                        }
                    }
                }
                chip(
                    title: "未分类 \(model.count(in: .uncategorized))",
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
        .buttonStyle(.plain)
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
            Text("＋ 新建分类")
                .font(AppFont.secondary.weight(.medium))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .overlay {
                    Capsule().strokeBorder(AppColor.outline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $creating, arrowEdge: .bottom) {
            CategoryEditor(title: "新建分类", draft: $draft) {
                model.addCategory(name: draft.name, colorIndex: draft.colorIndex, symbol: draft.symbol)
                creating = false
            }
        }
    }

    private func sections(_ meetings: [Meeting]) -> some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            ForEach(sectionModels(meetings)) { section in
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s2) {
                        if let colorIndex = section.colorIndex {
                            Circle().fill(CategoryPalette.ink(colorIndex)).frame(width: 8, height: 8)
                        }
                        Text(section.title)
                            .font(AppFont.sectionTitle)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("\(section.meetings.count)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    if section.showsNow {
                        NowDivider()
                    }
                    VStack(spacing: Space.s3) {
                        ForEach(section.meetings) { meeting in
                            card(meeting)
                                .transition(insertionTransition(reduceMotion: reduceMotion))
                        }
                    }
                }
            }
        }
    }

    private func card(_ meeting: Meeting) -> some View {
        let category = model.category(for: meeting.categoryID)
        return MeetingCard(
            meeting: meeting,
            symbol: category?.symbol ?? CategoryPalette.uncategorizedSymbol,
            colorIndex: category?.colorIndex ?? CategoryPalette.uncategorizedIndex,
            reduceMotion: reduceMotion
        ) {
            withAnimation(Motion.layout(reduceMotion)) {
                model.openMeeting(meeting.id)
            }
        }
        .contextMenu {
            Button("打开") {
                withAnimation(Motion.layout(reduceMotion)) {
                    model.openMeeting(meeting.id)
                }
            }
            Button("重命名") {
                renameDraft = meeting.title
                renaming = meeting
            }
            Menu("移到分类") {
                Button("未分类") {
                    model.assign(meeting: meeting.id, category: nil)
                }
                ForEach(model.categories) { category in
                    Button(category.name) {
                        model.assign(meeting: meeting.id, category: category.id)
                    }
                }
            }
            Button("导出") {
                model.export([meeting])
            }
            if !meeting.isLive {
                Button("删除", role: .destructive) {
                    deletingMeeting = meeting
                }
            }
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
            sections.append(MeetingSection(id: "today", title: "今天", colorIndex: nil, meetings: today, showsNow: !searching))
        }
        if !earlier.isEmpty {
            sections.append(MeetingSection(id: "earlier", title: "更早", colorIndex: nil, meetings: earlier, showsNow: false))
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
            sections.append(MeetingSection(id: "none", title: "未分类", colorIndex: CategoryPalette.uncategorizedIndex, meetings: loose, showsNow: false))
        }
        return sections
    }

    private func sortMeetings(_ lhs: Meeting, _ rhs: Meeting) -> Bool {
        if lhs.isLive != rhs.isLive { return lhs.isLive && !rhs.isLive }
        return lhs.startedAt > rhs.startedAt
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
