import AppKit
import SwiftUI

struct MeetingDetailView: View {
    private static let sideWidthKey = "nomi.meetingSideWidth"

    @Bindable var model: AppModel
    var meetingID: UUID
    var reduceMotion: Bool
    @State private var titleDraft = ""
    @State private var sidePreference: Bool?
    @State private var sideWidth: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: MeetingDetailView.sideWidthKey)
        return stored > 0 ? stored : 340
    }()
    @State private var showingLanguages = false
    @State private var showingStartTime = false
    @State private var creatingCategory = false
    @State private var categoryDraft = CategoryDraft()
    @FocusState private var titleFocused: Bool

    var body: some View {
        Group {
            if let meeting = model.meetings.first(where: { $0.id == meetingID }) {
                detail(meeting)
            }
        }
    }

    private func detail(_ meeting: Meeting) -> some View {
        GeometryReader { proxy in
            let showSide = sideVisible(width: proxy.size.width)
            VStack(alignment: .leading, spacing: 0) {
                header(meeting, width: proxy.size.width, showSide: showSide)
                    .padding(.horizontal, 24)
                    .padding(.top, Space.s4)
                    .padding(.bottom, Space.s4)
                HStack(alignment: .top, spacing: 0) {
                    TranscriptCard(
                        meeting: meeting,
                        transcript: model.engine.transcript,
                        reduceMotion: reduceMotion,
                        canCompare: proxy.size.width >= 1100,
                        onCopy: { model.copyTranscript($0) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if showSide {
                        let range = sideRange(total: proxy.size.width)
                        let width = min(max(sideWidth, range.lowerBound), range.upperBound)
                        ColumnSplitHandle(width: $sideWidth, range: range) {
                            persistSideWidth()
                        }
                        .frame(width: 16)
                        .frame(maxHeight: .infinity)
                        .pointerStyle(.columnResize)
                        DetailSidePanel(model: model, meeting: meeting, reduceMotion: reduceMotion, onPreferredSideWidth: { needed in
                            ensureSideWidth(needed, total: proxy.size.width)
                        }) {
                            withAnimation(Motion.layout(reduceMotion)) {
                                sidePreference = false
                            }
                        }
                        .frame(width: width, alignment: .top)
                        .frame(maxHeight: .infinity)
                        .clipped()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            titleDraft = meeting.title
            model.audioInputs.refresh()
        }
    }

    private func header(_ meeting: Meeting, width: CGFloat, showSide: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .center, spacing: Space.s3) {
                Button {
                    withAnimation(Motion.layout(reduceMotion)) {
                        model.closeMeeting()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(AppColor.surface, in: Circle())
                }
                .buttonStyle(.plain.clicking())
                .accessibilityLabel(tr("返回会议列表"))

                CategoryIcon(
                    symbol: model.category(for: meeting.categoryID)?.symbol ?? CategoryPalette.uncategorizedSymbol,
                    colorIndex: model.category(for: meeting.categoryID)?.colorIndex ?? CategoryPalette.uncategorizedIndex
                )

                TextField(tr("未命名会议"), text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(AppFont.detailTitle)
                    .foregroundStyle(AppColor.textPrimary)
                    .focused($titleFocused)
                    .background(OutsideClickObserver(isActive: titleFocused) {
                        titleFocused = false
                    })
                    .onSubmit { titleFocused = false }
                    .onChange(of: titleDraft) { _, newValue in
                        model.rename(id: meeting.id, to: newValue)
                    }

                Spacer(minLength: Space.s2)
                Button {
                    model.meetingCompact = true
                } label: {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(AppColor.surface, in: Circle())
                }
                .buttonStyle(.plain.clicking())
                .accessibilityLabel(tr("缩小窗口"))
                .help(tr("缩小窗口"))
                if !showSide {
                    Button {
                        withAnimation(Motion.layout(reduceMotion)) {
                            sidePreference = true
                        }
                    } label: {
                        Image(systemName: "sidebar.trailing")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(AppColor.surface, in: Circle())
                    }
                    .buttonStyle(.plain.clicking())
                    .accessibilityLabel(tr("打开侧栏"))
                    .help(width < 760 ? tr("窗口再宽一点才能打开侧栏") : tr("打开侧栏"))
                    .disabled(width < 760)
                }
            }

            HStack(spacing: Space.s2) {
                Button {
                    showingStartTime = true
                } label: {
                    metaChip(formatStartStamp(meeting.startedAt))
                }
                .buttonStyle(.plain.clicking())
                .help(tr("重设时间"))
                .popover(isPresented: $showingStartTime, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    StartTimeEditor(date: startTimeBinding(meeting)) {
                        showingStartTime = false
                    }
                }
                categoryChip(meeting)
                Button {
                    showingLanguages = true
                } label: {
                    metaChip("\(languageName(model.recordingSourceLanguage)) → \(languageName(model.recordingTargetLanguage))")
                }
                .buttonStyle(.plain.clicking())
                .popover(isPresented: $showingLanguages, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        RecordingLanguagePicker(source: $model.recordingSourceLanguage, target: $model.recordingTargetLanguage)
                            .disabled(model.engine.session.phase != .idle)
                    }
                    .padding(Space.s4)
                    .frame(width: 300)
                }
                audioInputChip
            }
        }
    }

    private func startTimeBinding(_ meeting: Meeting) -> Binding<Date> {
        Binding(
            get: { model.meetings.first { $0.id == meeting.id }?.startedAt ?? meeting.startedAt },
            set: { model.setStartTime(meeting: meeting.id, to: $0) }
        )
    }

    private func categoryChip(_ meeting: Meeting) -> some View {
        Menu {
            Button(tr("未分类")) {
                model.assign(meeting: meeting.id, category: nil)
            }
            ForEach(model.categories) { category in
                Button(category.name) {
                    model.assign(meeting: meeting.id, category: category.id)
                }
            }
            Divider()
            Button {
                categoryDraft = CategoryDraft(
                    colorIndex: model.categories.count % CategoryPalette.swatches.count
                )
                creatingCategory = true
            } label: {
                Label(tr("新建分类"), systemImage: "plus")
            }
        } label: {
            metaLabel(model.categoryName(for: meeting) ?? tr("未分类"))
        }
        .menuStyle(.button)
        .buttonStyle(.plain.clicking())
        .menuIndicator(.hidden)
        .fixedSize()
        .clickCursor()
        .popover(isPresented: $creatingCategory, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            CategoryEditor(title: tr("新建分类"), draft: $categoryDraft) {
                if let categoryID = model.addCategory(name: categoryDraft.name, colorIndex: categoryDraft.colorIndex, symbol: categoryDraft.symbol) {
                    model.assign(meeting: meeting.id, category: categoryID)
                    creatingCategory = false
                }
            }
        }
    }

    private var audioInputChip: some View {
        @Bindable var inputs = model.audioInputs
        return Menu {
            Picker(tr("输入源"), selection: $inputs.selectedUID) {
                Text(tr("系统默认")).tag(AudioInputs.systemDefault)
                ForEach(model.audioInputs.devices) { device in
                    Text(device.name).tag(device.id)
                }
                if model.audioInputs.selectedUID != AudioInputs.systemDefault, model.audioInputs.selectedDevice == nil {
                    Text(tr("设备已断开")).tag(model.audioInputs.selectedUID)
                }
            }
            .pickerStyle(.inline)
        } label: {
            metaLabel(model.audioInputs.selectionTitle, symbol: "mic")
        }
        .menuStyle(.button)
        .buttonStyle(.plain.clicking())
        .menuIndicator(.hidden)
        .fixedSize()
        .clickCursor()
        .disabled(model.engine.session.phase != .idle)
        .accessibilityLabel(tr("输入源"))
        .help(model.audioInputs.selectionTitle)
    }

    private func metaChip(_ text: String) -> some View {
        metaLabel(text)
    }

    private func metaLabel(_ text: String, symbol: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text).truncationMode(.middle)
        }
            .font(AppFont.caption)
            .monospacedDigit()
            .foregroundStyle(AppColor.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(AppColor.surface, in: Capsule())
    }

    private func sideVisible(width: CGFloat) -> Bool {
        let preferred = sidePreference ?? (width >= 1100)
        return preferred && width >= 760
    }

    private func sideRange(total: CGFloat) -> ClosedRange<CGFloat> {
        let chrome: CGFloat = 48 + 16
        let sideMin: CGFloat = 300
        let sideMax = max(sideMin, total - chrome - 340)
        return sideMin...sideMax
    }

    /// Ask content takes width from the transcript instead of drawing over it.
    private func ensureSideWidth(_ needed: CGFloat, total: CGFloat) {
        let resolved = min(sideRange(total: total).upperBound, needed)
        guard sideWidth < resolved - 0.5 else { return }
        withAnimation(Motion.layout(reduceMotion)) {
            sideWidth = resolved
        }
        persistSideWidth()
    }

    private func persistSideWidth() {
        UserDefaults.standard.set(Double(sideWidth), forKey: Self.sideWidthKey)
    }
}

private struct ColumnSplitHandle: NSViewRepresentable {
    @Binding var width: CGFloat
    var range: ClosedRange<CGFloat>
    var onEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(width: $width, onEnd: onEnd)
    }

    func makeNSView(context: Context) -> SplitHandleView {
        let view = SplitHandleView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: SplitHandleView, context: Context) {
        context.coordinator.width = $width
        context.coordinator.onEnd = onEnd
        view.range = range
        view.coordinator = context.coordinator
    }

    final class Coordinator {
        var width: Binding<CGFloat>
        var onEnd: () -> Void

        init(width: Binding<CGFloat>, onEnd: @escaping () -> Void) {
            self.width = width
            self.onEnd = onEnd
        }
    }
}

private final class SplitHandleView: NSView {
    var range: ClosedRange<CGFloat> = 300...640
    var coordinator: ColumnSplitHandle.Coordinator?
    private var start: CGFloat = 0
    private var startX: CGFloat = 0

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        start = coordinator?.width.wrappedValue ?? 0
        startX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        let next = min(range.upperBound, max(range.lowerBound, start - (event.locationInWindow.x - startX)))
        coordinator?.width.wrappedValue = next
    }

    override func mouseUp(with event: NSEvent) {
        coordinator?.onEnd()
    }

    override func draw(_ dirtyRect: NSRect) {
        let pill = NSRect(x: (bounds.width - 4) / 2, y: (bounds.height - 36) / 2, width: 4, height: 36)
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 2, yRadius: 2).fill()
    }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .splitter }

    override func accessibilityLabel() -> String? { tr("调整侧栏宽度") }
}

struct StartTimeEditor: View {
    @Binding var date: Date
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(tr("重设时间")).font(AppFont.sectionTitle)
            DatePicker(tr("重设时间"), selection: $date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.field)
                .labelsHidden()
            HStack {
                Spacer()
                Button(tr("完成")) { onDone() }
            }
        }
        .padding(Space.s4)
        .environment(\.locale, InterfaceLanguage.current.locale)
    }
}
