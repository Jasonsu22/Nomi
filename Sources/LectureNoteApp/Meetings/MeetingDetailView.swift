import SwiftUI

struct MeetingDetailView: View {
    @Bindable var model: AppModel
    var meetingID: UUID
    var reduceMotion: Bool
    @State private var titleDraft = ""
    @State private var sidePreference: Bool?
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
                HStack(alignment: .top, spacing: 16) {
                    TranscriptCard(
                        meeting: meeting,
                        transcript: model.engine.transcript,
                        reduceMotion: reduceMotion,
                        canCompare: proxy.size.width >= 1100,
                        onCopy: { model.copyTranscript($0) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if showSide {
                        DetailSidePanel(model: model, meeting: meeting, reduceMotion: reduceMotion) {
                            withAnimation(Motion.layout(reduceMotion)) {
                                sidePreference = false
                            }
                        }
                        .frame(width: 340, alignment: .top)
                        .frame(maxHeight: .infinity)
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
                .buttonStyle(.plain)
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
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("打开侧栏"))
                    .help(width < 760 ? tr("窗口再宽一点才能打开侧栏") : tr("打开侧栏"))
                    .disabled(width < 760)
                }
            }

            HStack(spacing: Space.s2) {
                Button {
                    showingStartTime = true
                } label: {
                    HStack(spacing: Space.s2) {
                        metaChip("\(formatMonthDay(meeting.startedAt)) \(formatWeekday(meeting.startedAt))")
                        metaChip(formatClockTime(meeting.startedAt))
                    }
                }
                .buttonStyle(.plain)
                .help(tr("修改开始时间"))
                .popover(isPresented: $showingStartTime, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        Text(tr("开始时间")).font(AppFont.sectionTitle)
                        DatePicker(tr("开始时间"), selection: Binding(
                            get: { model.meetings.first { $0.id == meeting.id }?.startedAt ?? meeting.startedAt },
                            set: { model.setStartTime(meeting: meeting.id, to: $0) }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.field)
                        .labelsHidden()
                        HStack {
                            Spacer()
                            Button(tr("完成")) { showingStartTime = false }
                        }
                    }
                    .padding(Space.s4)
                }
                categoryChip(meeting)
                Button {
                    showingLanguages = true
                } label: {
                    metaChip("\(languageName(model.recordingSourceLanguage)) → \(languageName(model.recordingTargetLanguage))")
                }
                .buttonStyle(.plain)
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
            Text(model.categoryName(for: meeting) ?? tr("未分类"))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .font(AppFont.caption)
        .foregroundStyle(AppColor.textSecondary)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(AppColor.surface, in: Capsule())
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
            Label(model.audioInputs.selectionTitle, systemImage: "mic")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .frame(height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .background(AppColor.surface, in: Capsule())
        .disabled(model.engine.session.phase != .idle)
        .accessibilityLabel(tr("输入源"))
        .help(model.audioInputs.selectionTitle)
    }

    private func metaChip(_ text: String) -> some View {
        metaLabel(text)
    }

    private func metaLabel(_ text: String) -> some View {
        Text(text)
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
}
