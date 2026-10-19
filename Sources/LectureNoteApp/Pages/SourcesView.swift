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
        PageScaffold(title: tr("资料")) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    HStack(spacing: Space.s3) {
                        SearchField(text: $query, isFocused: $searchFocused, prompt: tr("搜索资料"))
                        addButton
                    }
                    chips
                    summary
                    if visible.isEmpty {
                        empty
                    } else {
                        table
                    }
                }
                .pageColumn()
                .padding(.bottom, Space.s7)
            }
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
        .alert(tr("资料"), isPresented: sourceErrorPresented) {
            Button(tr("好"), role: .cancel) { model.sourceError = nil }
        } message: {
            Text(model.sourceError ?? "")
        }
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
            self.filter = filter
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
            sortControl
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
            sort = option
        } label: {
            Text(title)
                .font(AppFont.secondary.weight(.medium))
                .foregroundStyle(selected ? AppColor.onSelection : AppColor.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 26)
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

    private var table: some View {
        VStack(spacing: 0) {
            tableHeader
            ForEach(visible) { source in
                Rectangle().fill(AppColor.separator).frame(height: 1)
                sourceRow(source)
            }
        }
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var tableHeader: some View {
        HStack(spacing: Space.s3) {
            Text(tr("名称"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(tr("时间"))
                .frame(width: 110, alignment: .leading)
            Text(tr("分类"))
                .frame(width: 120, alignment: .leading)
            Text(tr("操作"))
                .frame(width: 64, alignment: .trailing)
        }
        .font(AppFont.caption)
        .foregroundStyle(AppColor.textSecondary)
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private func sourceRow(_ source: KnowledgeSource) -> some View {
        HStack(spacing: Space.s3) {
            Button {
                NSWorkspace.shared.open(SourceStore.fileURL(for: source))
            } label: {
                HStack(spacing: Space.s3) {
                    sourceIcon(source.fileName)
                    Text(source.title)
                        .font(AppFont.secondary.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatRelativeTime(source.importedAt))
                .frame(width: 110, alignment: .leading)
            categoryMenu(source)
                .frame(width: 120, alignment: .leading)
            HStack(spacing: Space.s2) {
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
            .frame(width: 64, alignment: .trailing)
        }
        .font(AppFont.caption)
        .foregroundStyle(AppColor.textSecondary)
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
        .contextMenu {
            Button(tr("打开")) {
                NSWorkspace.shared.open(SourceStore.fileURL(for: source))
            }
            Button(tr("重命名")) {
                renameDraft = source.title
                renaming = source
            }
            Menu(tr("移到分类")) {
                categoryButtons(for: source)
            }
            Button(tr("在 Finder 中显示")) {
                NSWorkspace.shared.activateFileViewerSelecting([SourceStore.fileURL(for: source)])
            }
            Button(role: .destructive) {
                deleting = source
            } label: {
                Text(tr("删除")).foregroundStyle(.red)
            }
        }
    }

    private func categoryMenu(_ source: KnowledgeSource) -> some View {
        Menu {
            categoryButtons(for: source)
        } label: {
            HStack(spacing: 4) {
                Text(model.category(for: source.categoryID)?.name ?? tr("未分类"))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(AppColor.textPrimary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private func categoryButtons(for source: KnowledgeSource) -> some View {
        Button(tr("未分类")) { model.assign(source: source.id, category: nil) }
        ForEach(model.categories.sorted { $0.sortOrder < $1.sortOrder }) { category in
            Button(category.name) { model.assign(source: source.id, category: category.id) }
        }
        Divider()
        Button {
            draft = CategoryDraft(
                name: "",
                colorIndex: model.categories.count % CategoryPalette.swatches.count,
                symbol: CategorySymbols.all[0]
            )
            creating = true
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

    private func discardIfNeeded() {
        guard !committed else {
            committed = false
            return
        }
        model.discardSources(staged)
        staged = []
    }

    private func receiveDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                Task { @MainActor in
                    stage([url])
                }
            }
        }
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
            if staged.isEmpty {
                Button { picking = true } label: {
                    VStack(spacing: Space.s2) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 22, weight: .medium))
                        Text(tr("选择 PDF、幻灯片、文档或图片"))
                            .font(AppFont.secondary)
                    }
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(AppColor.outline, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach($staged) { $source in
                        pendingRow($source)
                    }
                }
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                Button { picking = true } label: {
                    Label(tr("继续添加"), systemImage: "plus")
                        .font(AppFont.secondary.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.accent)
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

    private var creatingPresented: Binding<Bool> {
        Binding(get: { creatingFor != nil }, set: { if !$0 { creatingFor = nil } })
    }
}
