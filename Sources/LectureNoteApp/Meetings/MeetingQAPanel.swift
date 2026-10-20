import SwiftUI

/// The Q&A tab: questions the teacher asked, answered one at a time, or on request when Auto-answer is off.
struct MeetingQAPanel: View {
    var model: AppModel
    var meeting: Meeting
    var onContinueInChat: () -> Void
    @Environment(\.appReduceMotion) private var reduceMotion

    var body: some View {
        let qa = model.qa(for: meeting.id)
        VStack(alignment: .leading, spacing: 0) {
            header(qa)
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s3)
            if qa.questions.isEmpty {
                empty(qa)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s3) {
                        ForEach(Array(qa.questions.enumerated()), id: \.element.id) { index, question in
                            QuestionCard(
                                question: question,
                                isFirst: index == 0,
                                isLast: index == qa.questions.count - 1,
                                model: model,
                                meetingID: meeting.id,
                                onContinueInChat: {
                                    model.continueQuestionInChat(question.id, in: meeting.id)
                                    onContinueInChat()
                                }
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(Motion.layout(reduceMotion), value: qa.questions.map(\.id))
                    .padding(.horizontal, Space.s4)
                    .padding(.bottom, Space.s4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ qa: MeetingQA) -> some View {
        HStack(spacing: Space.s3) {
            Toggle(tr("自动回答"), isOn: Binding(
                get: { qa.autoAnswer },
                set: { model.setAutoAnswer($0, for: meeting.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(AppFont.caption)
            .clickCursor()
            Spacer(minLength: Space.s2)
            if !qa.questions.isEmpty {
                Text(trf("%d 个问题 · 已回答 %d", qa.questions.count, qa.answeredCount))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }
            if !qa.autoAnswer, qa.questions.contains(where: { $0.status == .waiting || $0.status == .failed }) {
                Button(tr("全部回答")) { model.askAllQuestions(in: meeting.id) }
                    .font(AppFont.caption)
                    .clickCursor()
            }
            findButton(qa)
        }
    }

    private func findButton(_ qa: MeetingQA) -> some View {
        Button {
            Task { await model.findQuestions(meeting.id) }
        } label: {
            Group {
                if qa.scanning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "text.magnifyingglass")
                }
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain.clicking())
        .foregroundStyle(AppColor.textSecondary)
        .disabled(qa.scanning || !model.canRunBackgroundWork)
        .help(tr("从转写里找老师提出的问题"))
        .accessibilityLabel(tr("找问题"))
    }

    @ViewBuilder
    private func empty(_ qa: MeetingQA) -> some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "questionmark.bubble")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AppColor.accent)
                .frame(width: 48, height: 48)
                .background(AppColor.accentSoft, in: Circle())
            Text(emptyText(qa))
                .font(AppFont.secondary)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let error = qa.scanError {
                Text(error)
                    .font(AppFont.caption)
                    .foregroundStyle(.red)
            }
            if !meeting.isLive, !qa.scanning {
                Button(qa.scannedThrough < 0 ? tr("找问题") : tr("再找一次")) {
                    Task { await model.findQuestions(meeting.id, fromStart: qa.scannedThrough >= 0) }
                }
                .buttonStyle(.borderedProminent.clicking())
                .disabled(!model.canRunBackgroundWork || model.transcriptLines(meeting.id).isEmpty)
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyText(_ qa: MeetingQA) -> String {
        if qa.scanning { return tr("正在从转写里找老师提出的问题…") }
        if meeting.isLive { return tr("录音时，老师提出的问题会出现在这里。") }
        if qa.scannedThrough >= 0 { return tr("这节课里没有找到老师提出的问题。") }
        return tr("找出老师在课上提出的问题，并自动回答。")
    }
}

private struct QuestionCard: View {
    var question: MeetingQuestion
    var isFirst: Bool
    var isLast: Bool
    var model: AppModel
    var meetingID: UUID
    var onContinueInChat: () -> Void
    @State private var expanded = false
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button {
                    model.jumpTranscript(meetingID, to: question.at)
                } label: {
                    Label(formatClock(question.at), systemImage: "clock")
                        .font(AppFont.caption.monospacedDigit())
                        .foregroundStyle(AppColor.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppColor.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain.clicking())
                .help(tr("在转写里查看这一刻"))
                status
                Spacer(minLength: 0)
                menu
            }
            if editing {
                TextField(tr("问题"), text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(AppFont.body.weight(.semibold))
                    .onSubmit(saveEdit)
                HStack {
                    Button(tr("取消")) { editing = false }
                    Button(tr("保存")) { saveEdit() }
                        .buttonStyle(.borderedProminent.clicking())
                }
                .font(AppFont.caption)
            } else {
                Text(question.text)
                    .font(AppFont.body.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !question.quote.isEmpty {
                Text("“\(question.quote)”")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
            }
            answer
            actions
        }
        .padding(Space.s3)
        .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var status: some View {
        switch question.status {
        case .waiting:
            Text(tr("等待提问")).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
        case .queued:
            Text(tr("排队中")).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
        case .answering:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(tr("正在回答…"))
            }
            .font(AppFont.caption)
            .foregroundStyle(AppColor.textSecondary)
        case .answered:
            EmptyView()
        case .failed:
            Text(tr("回答失败")).font(AppFont.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var answer: some View {
        if !question.answer.isEmpty {
            let folded = question.status == .answered && !expanded
            AnswerBody(source: question.answer, streaming: question.status == .answering, citations: question.citations) { citation in
                open(citation)
            }
            .frame(maxHeight: folded ? 150 : nil, alignment: .top)
            .clipped()
            .mask {
                if folded {
                    LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                } else {
                    Color.black
                }
            }
        }
        if let error = question.error, question.status == .failed {
            Text(error)
                .font(AppFont.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: Space.s3) {
            switch question.status {
            case .waiting, .failed:
                Button(question.status == .failed ? tr("重试") : tr("回答")) {
                    model.askQuestion(question.id, in: meetingID)
                }
                .buttonStyle(.borderedProminent.clicking())
                .controlSize(.small)
            case .answered:
                Button(expanded ? tr("收起") : tr("展开")) {
                    withAnimation(.smooth(duration: 0.3)) { expanded.toggle() }
                }
                .buttonStyle(.plain.clicking())
                .foregroundStyle(AppColor.accent)
                Button(tr("在提问中继续"), action: onContinueInChat)
                    .buttonStyle(.plain.clicking())
                    .foregroundStyle(AppColor.accent)
            case .queued, .answering:
                EmptyView()
            }
        }
        .font(AppFont.caption)
    }

    private var menu: some View {
        Menu {
            Button(tr("编辑问题")) {
                draft = question.text
                editing = true
            }
            .disabled(question.status == .answering)
            if question.status == .answered {
                Button(tr("重新回答")) { model.askQuestion(question.id, in: meetingID) }
            }
            Divider()
            Button(tr("上移")) { model.moveQuestion(question.id, in: meetingID, by: -1) }
                .disabled(isFirst)
            Button(tr("下移")) { model.moveQuestion(question.id, in: meetingID, by: 1) }
                .disabled(isLast)
            Divider()
            Button(tr("删除"), role: .destructive) { model.deleteQuestion(question.id, in: meetingID) }
                .disabled(question.status == .answering)
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 22, height: 18)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .clickCursor()
    }

    private func saveEdit() {
        model.editQuestion(question.id, in: meetingID, text: draft)
        editing = false
    }

    /// A passage from this lecture jumps the transcript; anything else opens as usual.
    private func open(_ citation: ChatCitation) {
        if citation.meetingID == meetingID, let time = QuestionFinder.seconds(citation.detail) {
            model.jumpTranscript(meetingID, to: time)
        } else {
            model.openCitation(citation)
        }
    }
}
