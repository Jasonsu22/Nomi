import SwiftUI

/// 转写卡片单独成视图：只有它读取实时转写，tail 更新时头部和右栏不重新求值。
struct TranscriptCard: View {
    var meeting: Meeting
    var transcript: LiveTranscript
    var reduceMotion: Bool
    var canCompare: Bool
    var embedded = false
    /// A moment to scroll to, sent from the Q&A tab.
    var jump: TranscriptJump? = nil
    /// The voice pass: running now, why it failed, how to start it, and "This is the teacher".
    var checkingVoices = false
    var voiceError: String? = nil
    var onCheckVoices: (() -> Void)? = nil
    var onMarkTeacher: ((Int) -> Void)? = nil
    var onCopy: (Meeting) -> Void

    @AppStorage("lecturenote.transcriptFontSize") private var fontSize = 15.0
    @State private var compare = false
    @State private var copied = false
    @State private var followsLatest = false
    @State private var userScrolling = false
    /// Whether the view is at the newest line. A plain box, not view state, so scrolling
    /// never rebuilds the whole transcript; only a change of `followsLatest` does.
    @State private var scrollEdge = ScrollEdge()
    /// The paragraph a Q&A timestamp jumped to, lit for a moment.
    @State private var highlighted: Int?
    @State private var highlightFade: Task<Void, Never>?
    @AppStorage("lecturenote.teacherOnly") private var teacherOnly = false

    var body: some View {
        let paragraphs = paragraphs
        card(paragraphs)
        .onAppear {
            followsLatest = meeting.isLive
        }
    }

    private func card(_ paragraphs: [Paragraph]) -> some View {
        let content = VStack(alignment: .leading, spacing: 0) {
            toolbar
            transcript(paragraphs)
        }
        return Group {
            if embedded {
                content
            } else {
                content
                    .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
        }
    }

    private var paragraphs: [Paragraph] {
        meeting.isLive ? transcript.paragraphs : meeting.paragraphs
    }

    private var toolbar: some View {
        HStack(spacing: Space.s2) {
            if !embedded {
                Text(tr("转写"))
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(AppColor.textPrimary)
            }
            Spacer(minLength: Space.s2)
            voiceControl
            fontButton("A−") { fontSize = max(13, fontSize - 1) }
            fontButton("A+") { fontSize = min(20, fontSize + 1) }
            if canCompare {
                Button {
                    compare.toggle()
                } label: {
                    Text(compare ? tr("对照") : tr("段内"))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                }
                .buttonStyle(.plain.clicking())
            }
            Button {
                onCopy(snapshot)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    copied = false
                }
            } label: {
                Text(copied ? tr("已复制") : tr("复制全文"))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .buttonStyle(.plain.clicking())
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    /// "Teacher only" once voices are known; before that, a way to find them in a finished recording.
    @ViewBuilder
    private var voiceControl: some View {
        if meeting.voices != nil {
            Button {
                teacherOnly.toggle()
            } label: {
                Label(teacherOnly ? tr("只看老师") : tr("全部声音"), systemImage: teacherOnly ? "person.fill" : "person.2")
                    .font(AppFont.caption)
                    .foregroundStyle(teacherOnly ? AppColor.accent : AppColor.textSecondary)
                    .padding(.horizontal, 6)
                    .frame(height: 24)
            }
            .buttonStyle(.plain.clicking())
            .help(teacherOnly ? tr("显示同学说的话") : tr("隐藏同学说的话，只看老师"))
        } else if checkingVoices {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(tr("正在识别声音…"))
            }
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
        } else if let onCheckVoices, !meeting.isLive, !(meeting.audioFiles ?? []).isEmpty {
            Button(action: onCheckVoices) {
                Label(tr("识别同学的声音"), systemImage: "person.2.wave.2")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .padding(.horizontal, 6)
                    .frame(height: 24)
            }
            .buttonStyle(.plain.clicking())
            .help(voiceError ?? tr("从录音里分出老师和同学的声音，同学说的话会变灰"))
        }
    }

    private func fontButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain.clicking())
    }

    private func transcript(_ paragraphs: [Paragraph]) -> some View {
        let sideBySide = compare && canCompare
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if paragraphs.isEmpty {
                        Text(meeting.isLive ? tr("正在听…") : tr("这场还没有转写。"))
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(Space.s5)
                    } else {
                        ForEach(shown(paragraphs)) { paragraph in
                            ParagraphRow(
                                paragraph: paragraph,
                                sourceLanguage: meeting.sourceLanguage,
                                targetLanguage: meeting.targetLanguage,
                                compare: sideBySide,
                                fontSize: fontSize,
                                highlighted: paragraph.id == highlighted,
                                voices: meeting.voices,
                                teacherOnly: teacherOnly
                            )
                            .equatable()
                            .contextMenu {
                                if let voices = meeting.voices, let onMarkTeacher,
                                   VoiceLabels.voiceToPromote(in: paragraph, voices: voices) != nil {
                                    Button(tr("这是老师的声音")) { onMarkTeacher(paragraph.id) }
                                }
                            }
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
            .defaultScrollAnchor(followsLatest && meeting.isLive ? .bottom : nil, for: .sizeChanges)
            .scrollIndicators(userScrolling ? .automatic : .hidden, axes: .vertical)
            .background(LiveScrollerGate(shown: userScrolling))
            .onScrollPhaseChange { _, phase in
                switch phase {
                case .interacting, .tracking, .decelerating:
                    userScrolling = true
                    // Scrolling away by hand means the student has found the line.
                    if highlighted != nil, phase == .interacting { clearHighlight() }
                case .idle:
                    let wasDragging = userScrolling
                    userScrolling = false
                    if wasDragging, followsLatest != scrollEdge.atBottom {
                        followsLatest = scrollEdge.atBottom
                    }
                case .animating:
                    break
                }
            }
            // Reports only when "at the bottom" flips, not on every scrolled frame.
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentSize.height - geo.visibleRect.maxY < 72
            } action: { _, atBottom in
                scrollEdge.atBottom = atBottom
                guard userScrolling, atBottom != followsLatest else { return }
                followsLatest = atBottom
            }
            .onChange(of: jump?.token, initial: true) { _, _ in
                guard let jump, jump.isFresh else { return }
                show(jump.time, in: paragraphs, proxy: proxy)
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
                    .animation(Motion.tap(reduceMotion), value: followsLatest)
                }
            }
        }
    }

    /// With "Teacher only", paragraphs that are all classmates' are left out.
    private func shown(_ paragraphs: [Paragraph]) -> [Paragraph] {
        guard teacherOnly, let voices = meeting.voices else { return paragraphs }
        return paragraphs.filter { paragraph in
            paragraph.commits.isEmpty || paragraph.commits.contains { !voices.isClassmate($0) }
        }
    }

    private var snapshot: Meeting {
        var copy = meeting
        if meeting.isLive {
            copy.paragraphs = transcript.paragraphs
        }
        return copy
    }

    private func bottomToken(_ paragraphs: [Paragraph]) -> String {
        let last = paragraphs.last
        let spoken = last?.renderedSource(language: meeting.sourceLanguage).count ?? 0
        return "\(paragraphs.count)-\(last?.commits.count ?? 0)-\(spoken)-\(last?.tail.count ?? 0)"
    }

    /// Scrolls to the paragraph that was being spoken at `time`, and stops following the live end.
    private func show(_ time: TimeInterval, in paragraphs: [Paragraph], proxy: ScrollViewProxy) {
        // A question's time and its line's start differ by a fraction of a second, so the line that
        // starts just after it still counts as the one being spoken.
        guard let target = paragraphs.last(where: { $0.openedAt <= time + 1.5 }) ?? paragraphs.first else { return }
        followsLatest = false
        withAnimation(Motion.layout(reduceMotion)) {
            proxy.scrollTo(target.id, anchor: .top)
        }
        highlightFade?.cancel()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { highlighted = target.id }
        highlightFade = Task { @MainActor in
            // Long enough to catch the eye once the scroll lands, then it fades.
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            clearHighlight()
        }
    }

    private func clearHighlight() {
        highlightFade?.cancel()
        highlightFade = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { highlighted = nil }
    }

    private func stick(_ proxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

/// Overlay scrollers, and only while the user is dragging. Content growth must
/// not flash the bar or change the text width.
private struct LiveScrollerGate: NSViewRepresentable {
    var shown: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let scroll = nsView.enclosingScrollView else { return }
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.hasVerticalScroller = shown
        }
    }
}

private final class ScrollEdge {
    var atBottom = true
}
