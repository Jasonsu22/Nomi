import SwiftUI
import UniformTypeIdentifiers

struct SourcesView: View {
    @Bindable var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var filter: CategoryFilter = .all
    @State private var sort: SourceSort = .imported
    @State private var adding = false
    @State private var staged: [KnowledgeSource] = []
    @State private var committed = false
    @State private var renaming: KnowledgeSource?
    @State private var renameDraft = ""
    @State private var deleting: KnowledgeSource?
    @State private var creating = false
    @State private var draft = CategoryDraft()
    @State private var dropTargeted = false
    @State private var managing = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var confirmingBulkDelete = false
    @State private var groupByCategory = true
    @State private var movingIDs: Set<UUID> = []
    @State private var creatingForMove = false
    @Environment(\.appReduceMotion) private var reduceMotion
    @Namespace private var chipNamespace

    private var visible: [KnowledgeSource] {
        let matched = model.sources.matching(query: query, filter: activeFilter)
        switch sort {
        case .name:
            return matched.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .imported:
            return matched.sorted { $0.importedAt > $1.importedAt }
        }
    }

    private var activeFilter: CategoryFilter {
        if case .category(let id) = filter, model.category(for: id) == nil { return .all }
        return filter
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                HStack(spacing: Space.s3) {
                    SearchField(text: $query, isFocused: $searchFocused, prompt: tr("搜索资料"))
                    addButton
                }
                chips
                summary
                if visible.isEmpty {
                    empty
                } else if groupByCategory {
                    groups
                } else {
                    sourceCard(visible)
                }
            }
            .pageColumn()
            .padding(.top, 28)
            .padding(.bottom, Space.s7)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            receiveDrop(providers)
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(AppColor.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(Space.s4)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $adding, onDismiss: discardIfNeeded) {
            AddSourceSheet(model: model, staged: $staged) { urls in
                stage(urls)
            } onCommit: {
                committed = true
                model.commitSources(staged)
                staged = []
                adding = false
            }
        }
        .alert(tr("重命名"), isPresented: renamingPresented) {
            TextField(tr("名称"), text: $renameDraft)
            Button(tr("确定")) {
                if let renaming { model.rename(source: renaming.id, to: renameDraft) }
            }
            Button(tr("取消"), role: .cancel) {}
        }
        .alert(tr("删除这份资料？"), isPresented: deletingPresented) {
            Button(tr("删除"), role: .destructive) {
                if let deleting { model.deleteSource(deleting.id) }
            }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("资料库里的副本会被删掉，原来的文件还在。"))
        }
        .alert(trf("删除这 %d 份资料？", selectedIDs.count), isPresented: $confirmingBulkDelete) {
            Button(tr("删除"), role: .destructive) {
                removeSources(selectedIDs, leaveManageMode: true)
            }
            Button(tr("取消"), role: .cancel) {}
        } message: {
            Text(tr("资料库里的副本会被删掉，原来的文件还在。"))
        }
        .sheet(isPresented: $creatingForMove) {
            CategoryEditor(title: tr("新建分类"), draft: $draft) {
                let ids = movingIDs
                if let id = model.addCategory(name: draft.name, colorIndex: draft.colorIndex, symbol: draft.symbol, select: false) {
                    withAnimation(Motion.layout(reduceMotion)) {
                        model.assign(sources: ids, category: id)
                    }
                }
                movingIDs = []
            }
        }
        .alert(tr("资料"), isPresented: sourceErrorPresented) {
            Button(tr("好"), role: .cancel) { model.sourceError = nil }
        } message: {
            Text(model.sourceError ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text(tr("资料"))
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: Space.s3)
            if managing {
                Text(trf("已选 %d", selectedIDs.count))
                    .font(AppFont.secondary.weight(.medium))
                    .foregroundStyle(AppColor.textSecondary)
                PillButton(title: tr("全选")) { selectAllVisible() }
                PillButton(title: tr("完成")) { endManaging() }
                PillButton(title: tr("导出")) {
                    model.downloadSourcesByCategory(selectedIDs, prompt: tr("导出"))
                }
                .help(tr("把选中的资料按分类复制出去。"))
                .disabled(selectedIDs.isEmpty)
                .opacity(selectedIDs.isEmpty ? 0.4 : 1)
                PillMenu(title: tr("移到分类"), enabled: !selectedIDs.isEmpty) {
                    categoryMoveItems(for: selectedIDs)
                }
                PillButton(title: tr("删除"), tint: .red) { confirmingBulkDelete = true }
                    .disabled(selectedIDs.isEmpty)
                    .opacity(selectedIDs.isEmpty ? 0.4 : 1)
            } else {
                PillButton(title: tr("下载")) { model.downloadSourcesByCategory() }
                    .help(tr("按分类建文件夹，把资料复制进去。"))
                    .disabled(model.sources.isEmpty)
                    .opacity(model.sources.isEmpty ? 0.4 : 1)
                PillButton(title: tr("管理")) {
                    selectedIDs.removeAll()
                    managing = true
                }
                sortControl
                categoryToggle
            }
        }
        .frame(height: 36)
    }

    private var categoryToggle: some View {
        Button {
            withAnimation(Motion.layout(reduceMotion)) {
                groupByCategory.toggle()
            }
        } label: {
            Text(tr("分类"))
                .font(AppFont.secondary.weight(.medium))
                .foregroundStyle(groupByCategory ? AppColor.onSelection : AppColor.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(groupByCategory ? AppColor.selection : Color.clear, in: Capsule())
                .padding(3)
                .background(AppColor.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(tr("按分类分组"))
    }

    private var addButton: some View {
        Button {
            openAdd()
        } label: {
            Label(tr("添加资料"), systemImage: "plus")
                .font(AppFont.secondary.weight(.semibold))
                .foregroundStyle(AppColor.onAccent)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(AppColor.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                chip(title: trf("全部 %d", model.sources.count), dot: nil, filter: .all)
                ForEach(model.categories.sorted { $0.sortOrder < $1.sortOrder }) { category in
                    chip(
                        title: "\(category.name) \(model.sources.filter { $0.categoryID == category.id }.count)",
                        dot: CategoryPalette.ink(category.colorIndex),
                        filter: .category(category.id)
                    )
                    .categoryDrag(category.id, reduceMotion: reduceMotion) { dragged, target in
                        model.placeCategory(dragged, at: target)
                    }
                    .help(tr("拖动调整顺序"))
                }
                chip(
                    title: trf("未分类 %d", model.sources.filter { $0.categoryID == nil }.count),
                    dot: CategoryPalette.ink(CategoryPalette.uncategorizedIndex),
                    filter: .uncategorized
                )
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
                .buttonStyle(.plain)
                .popover(isPresented: $creating, arrowEdge: .bottom) {
                    CategoryEditor(title: tr("新建分类"), draft: $draft) {
                        if let id = model.addCategory(name: draft.name, colorIndex: draft.colorIndex, symbol: draft.symbol, select: false) {
                            filter = .category(id)
                        }
                        creating = false
                    }
                }
            }
        }
    }

    private func chip(title: String, dot: Color?, filter: CategoryFilter) -> some View {
        let selected = activeFilter == filter
        return Button {
            withAnimation(Motion.layout(reduceMotion)) {
                self.filter = filter
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
                        .matchedGeometryEffect(id: "source-category", in: chipNamespace)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        HStack(spacing: Space.s3) {
            Text(summaryText)
                .font(AppFont.secondary)
                .foregroundStyle(AppColor.textSecondary)
            if activeFilter != .all {
                Button(tr("查看会议")) {
                    model.filter = activeFilter
                    model.openMeetingID = nil
                    model.page = .meetings
                }
                .buttonStyle(.plain)
                .font(AppFont.secondary.weight(.medium))
                .foregroundStyle(AppColor.accent)
            }
            Spacer()
        }
    }

    private var summaryText: String {
        switch activeFilter {
        case .all:
            return trf("%d 份资料", visible.count)
        case .uncategorized:
            return trf("%d 份资料 · 未分类会议 %d 场", visible.count, model.count(in: .uncategorized))
        case .category:
            return trf("%d 份资料 · 这个分类里有 %d 场会议", visible.count, model.count(in: activeFilter))
        }
    }

    private var sortControl: some View {
        HStack(spacing: 2) {
            sortButton(.name, tr("名称"))
            sortButton(.imported, tr("时间"))
        }
        .padding(3)
        .background(AppColor.surface, in: Capsule())
    }

    private func sortButton(_ option: SourceSort, _ title: String) -> some View {
        let selected = sort == option
        return Button {
            withAnimation(Motion.layout(reduceMotion)) {
                sort = option
            }
        } label: {
            Text(title)
                .font(AppFont.secondary.weight(.medium))
                .foregroundStyle(selected ? AppColor.onSelection : AppColor.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(selected ? AppColor.selection : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(model.sources.isEmpty ? tr("还没有资料") : tr("没有匹配的资料"))
                .font(AppFont.sectionTitle)
            Text(tr("把课件加到课程分类里。分类和会议是同一套，一份资料就对应这个课的转录。"))
                .font(AppFont.secondary)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s5)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var groups: some View {
        let sections = sourceSections(visible)
        return VStack(alignment: .leading, spacing: Space.s5) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: Space.s3) {
                    CategorySectionTitle(title: section.title, count: section.sources.count, colorIndex: section.colorIndex)
                    sourceCard(section.sources)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.layout(reduceMotion), value: sections.map(\.id))
    }

    private func sourceSections(_ sources: [KnowledgeSource]) -> [SourceSection] {
        var sections: [SourceSection] = []
        for category in model.categories.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let items = sources.filter { $0.categoryID == category.id }
            guard !items.isEmpty else { continue }
            sections.append(SourceSection(id: category.id.uuidString, title: category.name, colorIndex: category.colorIndex, sources: items))
        }
        let loose = sources.filter { $0.categoryID == nil }
        if !loose.isEmpty {
            sections.append(SourceSection(id: "none", title: tr("未分类"), colorIndex: CategoryPalette.uncategorizedIndex, sources: loose))
        }
        return sections
    }

    private func sourceCard(_ sources: [KnowledgeSource]) -> some View {
        VStack(spacing: 0) {
            ForEach(sources) { source in
                if source.id != sources.first?.id {
                    Rectangle().fill(AppColor.separator).frame(height: 1)
                }
                sourceRow(source)
                    .transition(.opacity)
            }
        }
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .animation(Motion.layout(reduceMotion), value: sources.map(\.id))
    }

    private func sourceRow(_ source: KnowledgeSource) -> some View {
        HStack(spacing: Space.s3) {
            Button {
                activate(source)
            } label: {
                HStack(spacing: 0) {
                    SelectionMark(
                        selected: managing ? selectedIDs.contains(source.id) : nil,
                        reduceMotion: reduceMotion
                    )
                    HStack(spacing: Space.s3) {
                    sourceIcon(source.fileName)
                    Text(source.title)
                        .font(AppFont.secondary.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(formatRelativeTime(source.importedAt))
                        .frame(width: 110, alignment: .leading)
                    }
                }
                .animation(Motion.layout(reduceMotion), value: managing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { sourceMenu(source) }
            if !managing {
                HStack(spacing: Space.s2) {
                Menu {
                    categoryMoveItems(for: [source.id])
                } label: {
                    Image(systemName: "tag")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(tr("移到分类"))
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([SourceStore.fileURL(for: source)])
                } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(AppColor.textSecondary)
                }
                .buttonStyle(.plain)
                .help(tr("在 Finder 中显示"))
                Button {
                    deleting = source
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help(tr("删除"))
                }
                .frame(width: 128, alignment: .leading)
            }
        }
        .font(AppFont.caption)
        .foregroundStyle(AppColor.textSecondary)
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .modifier(RowHover(reduceMotion: reduceMotion))
        .contextMenu { sourceMenu(source) }
    }

    @ViewBuilder
    private func sourceMenu(_ source: KnowledgeSource) -> some View {
        Button(tr("重命名")) { presentRename(source) }
        Menu(tr("移到分类")) {
            categoryMoveItems(for: moveTargets(source))
        }
        Button(tr("下载")) { download(source) }
        Button(role: .destructive) { presentDelete(source) } label: {
            Text(tr("删除")).foregroundStyle(.red)
        }
    }

    private func activate(_ source: KnowledgeSource) {
        if managing {
            if selectedIDs.contains(source.id) {
                selectedIDs.remove(source.id)
            } else {
                selectedIDs.insert(source.id)
            }
            return
        }
        NSWorkspace.shared.open(SourceStore.fileURL(for: source))
    }

    private func moveTargets(_ source: KnowledgeSource) -> Set<UUID> {
        if managing, selectedIDs.contains(source.id) {
            return selectedIDs
        }
        return [source.id]
    }

    private func selectAllVisible() {
        selectedIDs = Set(visible.map(\.id))
    }

    private func endManaging() {
        managing = false
        selectedIDs.removeAll()
    }

    private func removeSources(_ ids: Set<UUID>, leaveManageMode: Bool) {
        let removed = ids
        Task { @MainActor in
            withAnimation(Motion.layout(reduceMotion)) {
                model.deleteSources(removed)
                selectedIDs.subtract(removed)
            }
            guard leaveManageMode else { return }
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 0.32))
            managing = false
            selectedIDs.removeAll()
        }
    }

    /// The menu closes in the same turn it sets state, which swallows the alert.
    private func presentRename(_ source: KnowledgeSource) {
        Task { @MainActor in
            renameDraft = source.title
            renaming = source
        }
    }

    private func presentDelete(_ source: KnowledgeSource) {
        Task { @MainActor in
            deleting = source
        }
    }

    private func download(_ source: KnowledgeSource) {
        let file = SourceStore.fileURL(for: source)
        let name = source.fileName
        Task { @MainActor in
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else {
                model.sourceError = tr("找不到窗口，无法打开保存面板。")
                return
            }
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            panel.nameFieldStringValue = name
            if let type = UTType(filenameExtension: (name as NSString).pathExtension) {
                panel.allowedContentTypes = [type]
            }
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let destination = panel.url else { return }
                guard destination.standardizedFileURL != file.standardizedFileURL else { return }
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: file, to: destination)
                } catch {
                    Task { @MainActor in
                        model.sourceError = error.localizedDescription
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func categoryMoveItems(for ids: Set<UUID>) -> some View {
        Button(tr("未分类")) {
            let ids = ids
            Task { @MainActor in
                withAnimation(Motion.layout(reduceMotion)) {
                    model.assign(sources: ids, category: nil)
                }
            }
        }
        ForEach(model.categories.sorted { $0.sortOrder < $1.sortOrder }) { category in
            Button(category.name) {
                let ids = ids
                let categoryID = category.id
                Task { @MainActor in
                    withAnimation(Motion.layout(reduceMotion)) {
                        model.assign(sources: ids, category: categoryID)
                    }
                }
            }
        }
        Divider()
        Button {
            let ids = ids
            Task { @MainActor in
                draft = CategoryDraft(
                    name: "",
                    colorIndex: model.categories.count % CategoryPalette.swatches.count,
                    symbol: CategorySymbols.all[0]
                )
                movingIDs = ids
                creatingForMove = true
            }
        } label: {
            Label(tr("新建分类"), systemImage: "plus")
        }
    }

    private func sourceIcon(_ fileName: String) -> some View {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let symbol = switch ext {
        case "pdf": "doc.richtext"
        case "ppt", "pptx", "key": "rectangle.on.rectangle"
        case "png", "jpg", "jpeg", "heic": "photo"
        default: "doc"
        }
        return Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(ext == "pdf" ? Color(red: 0.86, green: 0.32, blue: 0.28) : AppColor.textSecondary)
            .frame(width: 22)
    }

    private func openAdd() {
        committed = false
        staged = []
        adding = true
    }

    private var defaultCategoryID: UUID? {
        if case .category(let id) = activeFilter { return id }
        return nil
    }

    private func stage(_ urls: [URL]) {
        var added: [KnowledgeSource] = []
        var rejected = false
        for url in urls {
            guard SourceStore.accepts(url) else {
                rejected = true
                continue
            }
            do {
                added.append(try SourceStore.stage(url, categoryID: defaultCategoryID))
            } catch {
                model.sourceError = error.localizedDescription
            }
        }
        if rejected {
            model.sourceError = tr("暂时只收 PDF、幻灯片、文档和图片。")
        }
        guard !added.isEmpty else { return }
        staged.append(contentsOf: added)
        committed = false
        adding = true
    }

    private func receiveDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = fileURL(fromDroppedItem: item) else { return }
                Task { @MainActor in
                    stage([url])
                }
            }
        }
    }

    private func discardIfNeeded() {
        guard !committed else {
            committed = false
            return
        }
        model.discardSources(staged)
        staged = []
    }

    private var renamingPresented: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deletingPresented: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var sourceErrorPresented: Binding<Bool> {
        Binding(get: { model.sourceError != nil }, set: { if !$0 { model.sourceError = nil } })
    }
}

private struct SourceSection: Identifiable {
    var id: String
    var title: String
    var colorIndex: Int?
    var sources: [KnowledgeSource]
}

private enum SourceSort {
    case name
    case imported
}

private struct AddSourceSheet: View {
    @Bindable var model: AppModel
    @Binding var staged: [KnowledgeSource]
    var onStage: ([URL]) -> Void
    var onCommit: () -> Void
    @State private var picking = false
    @State private var dropTargeted = false
    @State private var creatingFor: UUID?
    @State private var draft = CategoryDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(tr("添加资料"))
                .font(AppFont.detailTitle)
            Text(tr("文件会复制进资料库，原来的文件还在原处。分类和会议用的是同一套。"))
                .font(AppFont.secondary)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            dropBox
            if !staged.isEmpty {
                VStack(spacing: 0) {
                    ForEach($staged) { $source in
                        pendingRow($source)
                    }
                }
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                    receiveDrop(providers)
                    return true
                }
            }
            HStack {
                Spacer()
                Button(tr("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(tr("添加")) { onCommit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(staged.isEmpty || staged.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.s5)
        .frame(width: 520)
        .foregroundStyle(AppColor.textPrimary)
        .background(AppColor.canvas)
        .fileImporter(isPresented: $picking, allowedContentTypes: SourceStore.allowedTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                onStage(urls)
            } else if case .failure(let error) = result {
                model.sourceError = error.localizedDescription
            }
        }
        .popover(isPresented: creatingPresented, arrowEdge: .bottom) {
            CategoryEditor(title: tr("新建分类"), draft: $draft) {
                if let id = model.addCategory(name: draft.name, colorIndex: draft.colorIndex, symbol: draft.symbol, select: false),
                   let target = creatingFor,
                   let index = staged.firstIndex(where: { $0.id == target }) {
                    staged[index].categoryID = id
                }
                creatingFor = nil
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    private var dropBox: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 22, weight: .medium))
            Text(tr("把 PDF、幻灯片、文档或图片拖到这里，或点击选择"))
                .font(AppFont.secondary)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(dropTargeted ? AppColor.accent : AppColor.textSecondary)
        .padding(.horizontal, Space.s4)
        .frame(maxWidth: .infinity)
        .frame(height: staged.isEmpty ? 140 : 96)
        .background(
            (dropTargeted ? AppColor.accent.opacity(0.08) : AppColor.surfaceInset),
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(
                    dropTargeted ? AppColor.accent : AppColor.outline,
                    style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [5, 4])
                )
        }
        .overlay {
            FileDropBox(
                isTargeted: { dropTargeted = $0 },
                onClick: { picking = true },
                onDrop: onStage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(tr("把 PDF、幻灯片、文档或图片拖到这里，或点击选择"))
    }

    private func pendingRow(_ source: Binding<KnowledgeSource>) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                TextField(tr("名称"), text: source.title)
                    .textFieldStyle(.plain)
                    .font(AppFont.secondary.weight(.semibold))
                Picker(tr("分类"), selection: source.categoryID) {
                    Text(tr("未分类")).tag(nil as UUID?)
                    ForEach(model.categories.sorted { $0.sortOrder < $1.sortOrder }) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Spacer(minLength: Space.s2)
            Button {
                draft = CategoryDraft(
                    name: "",
                    colorIndex: model.categories.count % CategoryPalette.swatches.count,
                    symbol: CategorySymbols.all[0]
                )
                creatingFor = source.wrappedValue.id
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.textSecondary)
            .help(tr("新建分类"))
            Button {
                model.discardSources([source.wrappedValue])
                staged.removeAll { $0.id == source.wrappedValue.id }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help(tr("删除"))
        }
        .padding(Space.s4)
    }

    private func receiveDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = fileURL(fromDroppedItem: item) else { return }
                Task { @MainActor in
                    onStage([url])
                }
            }
        }
    }

    private var creatingPresented: Binding<Bool> {
        Binding(get: { creatingFor != nil }, set: { if !$0 { creatingFor = nil } })
    }
}

private struct RowHover: ViewModifier {
    var reduceMotion: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(hovering ? AppColor.surfaceInset : Color.clear)
            .onHover { hovering = $0 }
            .animation(Motion.fade(reduceMotion), value: hovering)
    }
}
