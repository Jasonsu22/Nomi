import SwiftUI

struct MeetingDetailView: View {
    @Bindable var model: AppModel
    var meetingID: UUID
    var reduceMotion: Bool
    @State private var titleDraft = ""
    @State private var followsLatest = false
    @State private var userScrolling = false
    @State private var distanceFromBottom: CGFloat = 0
    @State private var fontSize: CGFloat = 15
    @State private var compare = false
    @State private var sidePreference: Bool?
    @State private var copied = false

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
                    transcriptCard(meeting, compare: compare && proxy.size.width >= 1100)
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
            followsLatest = meeting.isLive
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
                .accessibilityLabel("返回会议列表")

                CategoryIcon(
                    symbol: model.category(for: meeting.categoryID)?.symbol ?? CategoryPalette.uncategorizedSymbol,
                    colorIndex: model.category(for: meeting.categoryID)?.colorIndex ?? CategoryPalette.uncategorizedIndex
                )

                TextField("未命名会议", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(AppFont.detailTitle)
                    .foregroundStyle(AppColor.textPrimary)
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
                    .accessibilityLabel("打开侧栏")
                    .help(width < 760 ? "窗口再宽一点才能打开侧栏" : "打开侧栏")
                    .disabled(width < 760)
                }
            }

            HStack(spacing: Space.s2) {
                metaChip("\(formatMonthDay(meeting.startedAt)) \(formatWeekday(meeting.startedAt))")
                timeChip(meeting)
                categoryChip(meeting)
                metaChip("\(languageName(meeting.sourceLanguage)) → \(languageName(meeting.targetLanguage))")
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
            Button("未分类") {
                model.assign(meeting: meeting.id, category: nil)
            }
            ForEach(model.categories) { category in
                Button(category.name) {
                    model.assign(meeting: meeting.id, category: category.id)
                }
            }
        } label: {
            metaLabel(model.categoryName(for: meeting) ?? "未分类")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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

    private func transcriptCard(_ meeting: Meeting, compare: Bool) -> some View {
        let paragraphs = paragraphs(for: meeting)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s2) {
                Text("转写")
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(AppColor.textPrimary)
                Spacer(minLength: Space.s2)
                fontButton("A−") { fontSize = max(13, fontSize - 1) }
                fontButton("A+") { fontSize = min(20, fontSize + 1) }
                Button {
                    self.compare.toggle()
                } label: {
                    Text(self.compare ? "对照" : "段内")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                }
                .buttonStyle(.plain)
                .disabled(false)
                Button {
                    model.copyTranscript(liveSnapshot(meeting))
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                } label: {
                    Text(copied ? "已复制" : "复制全文")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s3)

            transcript(paragraphs, meeting: meeting, compare: compare)
        }
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func fontButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
    }

    private func transcript(_ paragraphs: [Paragraph], meeting: Meeting, compare: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if paragraphs.isEmpty {
                        Text(meeting.isLive ? "正在听…" : "这场还没有转写。")
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(Space.s5)
                    } else {
                        ForEach(paragraphs) { paragraph in
                            ParagraphRow(
                                paragraph: paragraph,
                                sourceLanguage: meeting.sourceLanguage,
                                targetLanguage: meeting.targetLanguage,
                                compare: compare,
                                fontSize: fontSize
                            )
                            .transition(insertionTransition(reduceMotion: reduceMotion))
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, Space.s3)
                .padding(.bottom, Space.s4)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(meeting.isLive ? .bottom : .top, for: .initialOffset)
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .interacting, .tracking, .decelerating:
                    userScrolling = true
                case .idle:
                    userScrolling = false
                    followsLatest = distanceFromBottom < 72
                case .animating:
                    userScrolling = false
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentSize.height - geo.visibleRect.maxY
            } action: { _, distance in
                distanceFromBottom = distance
                guard userScrolling else { return }
                let atBottom = distance < 72
                if atBottom != followsLatest {
                    followsLatest = atBottom
                }
            }
            .onChange(of: bottomToken(paragraphs)) { _, _ in
                guard meeting.isLive, followsLatest else { return }
                stick(proxy)
            }
            .overlay(alignment: .bottomTrailing) {
                if meeting.isLive, !followsLatest, !paragraphs.isEmpty {
                    JumpToLatestPill {
                        followsLatest = true
                        stick(proxy)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.tap(reduceMotion), value: followsLatest)
        }
    }

    private func paragraphs(for meeting: Meeting) -> [Paragraph] {
        meeting.isLive ? model.engine.transcript.paragraphs : meeting.paragraphs
    }

    private func liveSnapshot(_ meeting: Meeting) -> Meeting {
        var copy = meeting
        if meeting.isLive {
            copy.paragraphs = model.engine.transcript.paragraphs
        }
        return copy
    }

    private func bottomToken(_ paragraphs: [Paragraph]) -> String {
        let last = paragraphs.last
        return "\(paragraphs.count)-\(last?.commits.count ?? 0)-\(last?.source.count ?? 0)-\(last?.tail.count ?? 0)"
    }

    private func stick(_ proxy: ScrollViewProxy) {
        withAnimation(Motion.layout(reduceMotion)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func sideVisible(width: CGFloat) -> Bool {
        let preferred = sidePreference ?? (width >= 1100)
        return preferred && width >= 760
    }
}
