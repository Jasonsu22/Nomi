import AppKit
import SwiftUI

/// AppKit owns row reuse and scroll geometry. SwiftUI only renders mounted rows.
struct ChatTranscript: NSViewRepresentable {
    var model: AppModel
    var session: ChatSession
    var pendingQuestion: String?
    var preparing: Set<UUID>
    var nextModel: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.appReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = ChatTableView()
        table.headerView = nil
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let column = NSTableColumn(identifier: .init("chat"))
        column.resizingMask = .autoresizingMask
        column.minWidth = 100
        column.width = 680
        table.addTableColumn(column)
        let scroll = ChatTranscriptScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table
        let coordinator = context.coordinator
        coordinator.table = table
        coordinator.scroll = scroll
        table.delegate = coordinator
        table.dataSource = coordinator
        table.onWidthChange = { [weak coordinator] in coordinator?.resize() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) { context.coordinator.update(self) }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.alive = false
        coordinator.table?.delegate = nil
        coordinator.table?.dataSource = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var table: ChatTableView?
        weak var scroll: NSScrollView?
        var alive = true
        private var value: ChatTranscript?
        private var rows: [TranscriptItem] = []
        private var heights: [UUID: CGFloat] = [:]
        private var pendingHeights: [UUID: CGFloat] = [:]
        private var scheduled = false
        private var width: CGFloat = 680
        private var initial = true

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            heights[rows[row].id] ?? 160
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let value else { return nil }
            let cell = (tableView.makeView(withIdentifier: .init("message"), owner: self) as? TranscriptCell) ?? TranscriptCell()
            cell.identifier = .init("message")
            configure(cell, item: rows[row], value: value)
            return cell
        }

        private func configure(_ cell: TranscriptCell, item: TranscriptItem, value: ChatTranscript) {
            let id = item.id
            let content = TranscriptRow(item: item, model: value.model)
                .environment(\.colorScheme, value.colorScheme)
                .environment(\.locale, value.locale)
                .environment(\.appReduceMotion, value.reduceMotion)
                .padding(.horizontal, Space.s5)
                .padding(.vertical, Space.s3)
                .frame(width: max(width, 100), alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [weak self] height in
                    self?.measured(id, height: height)
                }
                .id(id)
            cell.host.rootView = AnyView(content)
            cell.host.setFrameSize(NSSize(width: max(width, 100), height: heights[id] ?? 160))
            // A reused row has real text before its first paint, not a tiny async placeholder.
            let measured = cell.host.fittingSize.height
            if measured.isFinite, measured > 0 { self.measured(id, height: measured) }
            if let index = rows.firstIndex(where: { $0.id == id }) {
                let nearby = rows[max(0, index - 4)..<min(rows.count, index + 3)].compactMap { $0.turn?.answer }
                Task { await AnswerPreparation.prewarm(nearby) }
            }
        }

        func update(_ next: ChatTranscript) {
            guard let table else { return }
            let nextRows = TranscriptItem.items(next)
            let reset = value?.session.id != next.session.id
            let environmentChanged = value?.colorScheme != next.colorScheme || value?.locale != next.locale || value?.reduceMotion != next.reduceMotion
            value = next
            scroll?.appearance = NSAppearance(named: next.colorScheme == .dark ? .darkAqua : .aqua)
            guard reset || environmentChanged || nextRows != rows else { return }
            let anchor = captureAnchor()
            let old = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            for row in nextRows where old[row.id] != row { heights[row.id] = nil }
            rows = nextRows
            if reset || environmentChanged { heights.removeAll() }
            if reset { initial = true }
            table.reloadData()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.alive else { return }
                self.restore(anchor, bottom: self.initial)
                self.initial = false
            }
        }

        func resize() {
            guard let table, let value else { return }
            let next = table.tableColumns.first?.width ?? table.bounds.width
            guard next > 1, abs(width - next) > 0.5 else { return }
            let anchor = captureAnchor()
            width = next
            heights.removeAll()
            let visible = table.rows(in: table.visibleRect)
            if visible.location != NSNotFound {
                for row in visible.location..<min(NSMaxRange(visible), rows.count) {
                    if let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? TranscriptCell {
                        configure(cell, item: rows[row], value: value)
                    }
                }
            }
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: rows.indices))
            restore(anchor, bottom: initial)
        }

        private func measured(_ id: UUID, height: CGFloat) {
            guard height.isFinite, height > 0, abs((heights[id] ?? 0) - height) > 0.5 else { return }
            pendingHeights[id] = ceil(height)
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in self?.applyHeights() }
        }

        private func applyHeights() {
            scheduled = false
            guard alive, let table else { return }
            let anchor = captureAnchor()
            var changed = IndexSet()
            for (index, row) in rows.enumerated() {
                if let height = pendingHeights[row.id], heights[row.id] != height {
                    heights[row.id] = height
                    changed.insert(index)
                }
            }
            pendingHeights.removeAll()
            guard !changed.isEmpty else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                table.noteHeightOfRows(withIndexesChanged: changed)
            }
            restore(anchor, bottom: initial)
        }

        private struct Anchor {
            var id: UUID?
            var offset: CGFloat
            var bottom: Bool
        }

        private func captureAnchor() -> Anchor {
            guard let table, let scroll else { return Anchor(offset: 0, bottom: true) }
            let bounds = scroll.contentView.bounds
            let first = table.row(at: CGPoint(x: 0, y: bounds.minY))
            let id = rows.indices.contains(first) ? rows[first].id : nil
            let offset = first >= 0 ? bounds.minY - table.rect(ofRow: first).minY : 0
            return Anchor(id: id, offset: offset, bottom: table.bounds.height <= bounds.maxY + 80)
        }

        private func restore(_ anchor: Anchor, bottom: Bool = false) {
            guard let table, let scroll else { return }
            table.layoutSubtreeIfNeeded()
            let y: CGFloat
            if bottom || anchor.bottom {
                y = max(0, table.bounds.height - scroll.contentView.bounds.height)
            } else if let index = rows.firstIndex(where: { $0.id == anchor.id }) {
                y = table.rect(ofRow: index).minY + anchor.offset
            } else { return }
            let point = scroll.contentView.constrainBoundsRect(CGRect(origin: CGPoint(x: 0, y: y), size: scroll.contentView.bounds.size)).origin
            scroll.contentView.scroll(to: point)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

private struct TranscriptItem: Equatable {
    var id: UUID
    var turn: ChatTurn?
    var question: String?
    var previousModel: String?
    var modelName: String
    var preparing = false

    static func items(_ value: ChatTranscript) -> [Self] {
        var result = value.session.turns.enumerated().map { index, turn in
            Self(id: turn.id, turn: turn, previousModel: index > 0 ? value.session.turns[index - 1].modelName : nil,
                 modelName: turn.modelName, preparing: value.preparing.contains(turn.id))
        }
        let previous = value.session.turns.last?.modelName ?? ""
        if value.pendingQuestion != nil || (!previous.isEmpty && !value.nextModel.isEmpty && previous != value.nextModel) {
            result.append(Self(id: value.session.id, question: value.pendingQuestion, previousModel: value.session.turns.last?.modelName, modelName: value.nextModel))
        }
        return result
    }
}

private struct TranscriptRow: View {
    var item: TranscriptItem
    var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            if let previous = item.previousModel, !previous.isEmpty, !item.modelName.isEmpty, previous != item.modelName {
                ModelChangeNote(from: previous, to: item.modelName)
            }
            if let turn = item.turn { ChatTurnRow(turn: turn, model: model).equatable() }
            if let question = item.question { ChatPendingTurn(question: question, model: model) }
            if item.preparing {
                HStack(spacing: Space.s2) {
                    ProgressView().controlSize(.small)
                    Text(tr("正在准备图示…")).font(AppFont.secondary).foregroundStyle(AppColor.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

final class ChatTableView: NSTableView {
    var onWidthChange: (() -> Void)?
    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(frame.width - newSize.width) > 0.5
        super.setFrameSize(newSize)
        if changed { DispatchQueue.main.async { [weak self] in self?.onWidthChange?() } }
    }
}

private final class ChatTranscriptScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let table = documentView as? ChatTableView, contentSize.width > 1,
              abs(table.frame.width - contentSize.width) > 0.5 else { return }
        table.setFrameSize(NSSize(width: contentSize.width, height: table.frame.height))
    }
}

private final class TranscriptCell: NSView {
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    override init(frame: NSRect) {
        super.init(frame: frame)
        host.sizingOptions = [.intrinsicContentSize]
        host.autoresizingMask = [.width, .height]
        addSubview(host)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); host.frame = bounds }
}
