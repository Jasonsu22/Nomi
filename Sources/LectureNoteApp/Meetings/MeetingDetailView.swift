import SwiftUI

struct MeetingDetailView: View {
    @Bindable var model: AppModel
    var meetingID: UUID
    var reduceMotion: Bool
    @State private var titleDraft = ""
    @State private var sidePreference: Bool?
    @State private var showingLanguages = false
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
                metaChip("\(formatMonthDay(meeting.startedAt)) \(formatWeekday(meeting.startedAt))")
                timeChip(meeting)
                categoryChip(meeting)
                Button {
                    showingLanguages = true
                } label: {
                    metaChip("\(languageName(meeting.sourceLanguage)) → \(languageName(meeting.targetLanguage))")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingLanguages, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        RecordingLanguagePicker(source: $model.recordingSourceLanguage, target: $model.recordingTargetLanguage)
                            .disabled(model.engine.session.phase != .idle)
                    }
                    .padding(Space.s4)
                    .frame(width: 300)
                }
            }
        }
    }

    private func timeChip(_ meeting: Meeting) -> some View {
        Group {
            if meeting.isLive {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    metaChip(formatTimeRange(start: meeting.startedAt, duration: meeting.duration, liveElapsed: model.engine.session.elapsed))
                }
            } else {
                metaChip(formatTimeRange(start: meeting.startedAt, duration: meeting.duration, liveElapsed: nil))
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
        } label: {
            Text(model.categoryName(for: meeting) ?? tr("未分类"))
                .font(AppFont.caption)
                .monospacedDigit()
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .background(AppColor.surface, in: Capsule())
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
