import SwiftUI

/// 转写卡片单独成视图：只有它读取实时转写，tail 更新时头部和右栏不重新求值。
struct TranscriptCard: View {
    var meeting: Meeting
    var transcript: LiveTranscript
    var reduceMotion: Bool
    var canCompare: Bool
    var onCopy: (Meeting) -> Void

    @AppStorage("lecturenote.transcriptFontSize") private var fontSize = 15.0
    @State private var compare = false
    @State private var copied = false
    @State private var followsLatest = false
    @State private var userScrolling = false
    @State private var distanceFromBottom: CGFloat = 0

    var body: some View {
        let paragraphs = paragraphs
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            transcript(paragraphs)
        }
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onAppear {
            followsLatest = meeting.isLive
        }
    }

    private var paragraphs: [Paragraph] {
        meeting.isLive ? transcript.paragraphs : meeting.paragraphs
    }

    private var toolbar: some View {
        HStack(spacing: Space.s2) {
            Text(tr("转写"))
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.textPrimary)
            Spacer(minLength: Space.s2)
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
                                fontSize: fontSize
                            )
                            .equatable()
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
                case .idle:
                    let wasDragging = userScrolling
                    userScrolling = false
                    if wasDragging {
                        followsLatest = distanceFromBottom < 72
                    }
                case .animating:
                    break
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
