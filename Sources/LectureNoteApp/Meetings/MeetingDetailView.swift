import SwiftUI

struct MeetingDetailView: View {
    @Bindable var model: AppModel
    var meetingID: UUID
    var namespace: Namespace.ID
    var reduceMotion: Bool
    @State private var titleDraft = ""
    @State private var followsLatest = true
    @State private var ignoreScrollUntil = Date.distantPast
    @State private var contentShown = false

    var body: some View {
        Group {
            if let meeting = model.meetings.first(where: { $0.id == meetingID }) {
                detail(meeting)
            }
        }
        .modifier(HeroFrame(id: meetingID, namespace: namespace, enabled: !reduceMotion))
    }

    private func detail(_ meeting: Meeting) -> some View {
        let paragraphs = paragraphs(for: meeting)
        return VStack(alignment: .leading, spacing: 0) {
            header(meeting)
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s5)
                .padding(.bottom, Space.s4)
                .opacity(contentShown ? 1 : 0)
            transcript(paragraphs, live: meeting.isLive)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            titleDraft = meeting.title
            guard !contentShown else { return }
            withAnimation(Motion.fade(reduceMotion).delay(reduceMotion ? 0 : 0.08)) {
                contentShown = true
            }
        }
    }

    private func header(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Button {
                withAnimation(Motion.layout(reduceMotion)) {
                    model.closeMeeting()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("会议")
                }
                .font(AppFont.secondary.weight(.medium))
                .foregroundStyle(AppColor.textSecondary)
            }
            .buttonStyle(.plain)

            TextField("未命名会议", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(AppFont.pageTitle)
                .foregroundStyle(AppColor.textPrimary)
                .onChange(of: titleDraft) { _, newValue in
                    model.rename(id: meeting.id, to: newValue)
                }

            Text(meta(meeting))
                .font(AppFont.secondary)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private func transcript(_ paragraphs: [Paragraph], live: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if paragraphs.isEmpty {
                        Text(live ? "正在听…" : "这场还没有转写。")
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(Space.s5)
                    } else {
                        ForEach(paragraphs) { paragraph in
                            ParagraphRow(paragraph: paragraph)
                                .transition(insertionTransition(reduceMotion: reduceMotion))
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s3)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .padding(.horizontal, Space.s6)
                .padding(.bottom, 28)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentSize.height - geo.visibleRect.maxY
            } action: { _, distance in
                guard Date() >= ignoreScrollUntil else { return }
                let atBottom = distance < 72
                if atBottom != followsLatest {
                    followsLatest = atBottom
                }
            }
            .onChange(of: bottomToken(paragraphs)) { _, _ in
                guard live, followsLatest else { return }
                stick(proxy)
            }
            .overlay(alignment: .bottomTrailing) {
                if live, !followsLatest, !paragraphs.isEmpty {
                    JumpToLatestPill {
                        followsLatest = true
                        stick(proxy)
                    }
                    .padding(.trailing, 40)
                    .padding(.bottom, 24)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.tap(reduceMotion), value: followsLatest)
        }
    }

    private func paragraphs(for meeting: Meeting) -> [Paragraph] {
        meeting.isLive ? model.engine.transcript.paragraphs : meeting.paragraphs
    }

    private func meta(_ meeting: Meeting) -> String {
        let length = meeting.isLive
            ? formatClock(model.engine.session.elapsed)
            : formatDuration(meeting.duration)
        return "\(formatMeetingTime(meeting.startedAt)) · \(length) · \(meeting.source.title) · \(languageName(meeting.sourceLanguage)) → \(languageName(meeting.targetLanguage))"
    }

    private func bottomToken(_ paragraphs: [Paragraph]) -> String {
        let last = paragraphs.last
        return "\(paragraphs.count)-\(last?.commits.count ?? 0)-\(last?.source.count ?? 0)-\(last?.tail.count ?? 0)"
    }

    private func stick(_ proxy: ScrollViewProxy) {
        ignoreScrollUntil = Date().addingTimeInterval(0.35)
        withAnimation(Motion.layout(reduceMotion)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}
