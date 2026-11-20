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
    var onMarkMe: ((Int) -> Void)? = nil
    var onClearMe: (() -> Void)? = nil
    var onRenameSpeaker: ((String, String) -> Void)? = nil
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
    @AppStorage("lecturenote.showSpeakers") private var showSpeakers = true
    /// The voice being renamed, and the name typed so far.
    @State private var renaming: String?
    @State private var newName = ""

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
        .alert(tr("给说话人起个名字"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(tr("名字，例如 Jenny"), text: $newName)
            Button(tr("保存")) {
                if let renaming { onRenameSpeaker?(renaming, newName) }
                renaming = nil
            }
            Button(tr("取消"), role: .cancel) { renaming = nil }
        } message: {
            Text(tr("这场录音里这个声音说的话都会用这个名字。留空就恢复原来的名字。"))
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
        // A pass from before voiceprints were kept is run again, so "This is me" can be remembered.
        if meeting.voices?.prints != nil, !checkingVoices {
            Button {
                showSpeakers.toggle()
            } label: {
                Label(tr("说话人"), systemImage: showSpeakers ? "person.2.fill" : "person.2")
                    .font(AppFont.caption)
                    .foregroundStyle(showSpeakers ? AppColor.accent : AppColor.textSecondary)
                    .padding(.horizontal, 6)
                    .frame(height: 24)
            }
            .buttonStyle(.plain.clicking())
            .help(showSpeakers ? tr("隐藏说话人。右键一段可以改名，或标出老师和你自己") : tr("在每段话前标出是谁说的"))
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
                        ForEach(paragraphs) { paragraph in
                            ParagraphRow(
                                paragraph: paragraph,
                                sourceLanguage: meeting.sourceLanguage,
                                targetLanguage: meeting.targetLanguage,
                                compare: sideBySide,
                                fontSize: fontSize,
                                highlighted: paragraph.id == highlighted,
                                voices: meeting.voices,
                                showSpeakers: showSpeakers
                            )
                            .equatable()
                            .contextMenu {
                                if let voices = meeting.voices {
                                    let other = VoiceLabels.voiceToPromote(in: paragraph, voices: voices)
                                    if let onMarkMe, let other, other != voices.me {
                                        Button(tr("这是我的声音")) { onMarkMe(paragraph.id) }
                                    }
                                    if let onClearMe, voices.me != nil, paragraph.commits.contains(where: { voices.side(of: $0) == .me }) {
                                        Button(tr("这不是我的声音")) { onClearMe() }
                                    }
                                    if let onMarkTeacher, other != nil {
                                        Button(tr("这是老师的声音")) { onMarkTeacher(paragraph.id) }
                                    }
                                    if onRenameSpeaker != nil {
                                        let present = Array(NSOrderedSet(array: paragraph.commits.compactMap(\.speaker))) as? [String] ?? []
                                        if !present.isEmpty { Divider() }
                                        ForEach(present, id: \.self) { speaker in
                                            Button(trf("重命名“%@”…", voices.name(of: speaker))) {
                                                newName = voices.names?[speaker] ?? ""
                                                renaming = speaker
                                            }
                                        }
                                    }
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
            .fadingScrollBar()
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

/// Whether the transcript is scrolled to its newest line.
private final class ScrollEdge {
    var atBottom = true
}

