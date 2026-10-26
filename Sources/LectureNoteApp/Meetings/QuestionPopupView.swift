import SwiftUI

/// The teacher's question, floating over the window while recording. It stays for a few
/// seconds (longer while the pointer is on it); Answer now keeps it open to show the answer,
/// Later sends it to the Q&A tab, and left alone it follows the meeting's Auto-answer switch.
struct QuestionPopupView: View {
    var model: AppModel
    var popup: QuestionPopup
    var reduceMotion: Bool
    /// Fixed over the full window; nil fills the compact window's width.
    var width: CGFloat? = 380

    @State private var hovering = false
    @State private var pulsing = false

    static let askSeconds: TimeInterval = 8
    static let answeredSeconds: TimeInterval = 10

    private enum Phase: Equatable { case asking, answering, answered, failed }

    var body: some View {
        if let question = model.question(for: popup) {
            card(question)
        } else {
            // The question was deleted from the Q&A tab.
            Color.clear.frame(width: 1, height: 1).onAppear { model.closeQuestionPopup() }
        }
    }

    private func phase(_ question: MeetingQuestion) -> Phase {
        guard popup.answering else { return .asking }
        switch question.status {
        case .answered: return .answered
        case .failed: return .failed
        default: return .answering
        }
    }

    private func card(_ question: MeetingQuestion) -> some View {
        let phase = phase(question)
        return VStack(alignment: .leading, spacing: 0) {
            eyebrow(question, phase: phase)
            Text(question.text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if !question.quote.isEmpty, question.quote != question.text {
                Text(question.quote)
                    .font(AppFont.secondary)
                    .foregroundStyle(AppColor.accent)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
            if phase != .asking { answer(question, phase: phase) }
            footer(question, phase: phase)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(AppColor.separator)
        }
        .overlay(alignment: .bottom) {
            if phase != .answering {
                CountdownBar(seconds: phase == .asking ? Self.askSeconds : Self.answeredSeconds, paused: hovering) {
                    if phase == .asking { model.questionPopupTimedOut() } else { model.closeQuestionPopup() }
                }
                .id(phase)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 26, x: 0, y: 14)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("老师提问"))
    }

    private func eyebrow(_ question: MeetingQuestion, phase: Phase) -> some View {
        let label: String
        switch phase {
        case .asking: label = tr("老师提问")
        case .answering: label = tr("正在回答")
        case .answered: label = tr("已回答")
        case .failed: label = tr("没能回答")
        }
        return HStack(spacing: 8) {
            Circle()
                .fill(phase == .failed ? Color.red : AppColor.accentGreen)
                .frame(width: 8, height: 8)
                .scaleEffect(pulsing && phase != .answered ? 1.25 : 1)
                .opacity(pulsing && phase != .answered ? 0.6 : 1)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulsing = true }
                }
            Text("\(label) · \(formatClock(question.at))")
                .font(AppFont.caption.weight(.bold))
                .foregroundStyle(AppColor.accent)
            Spacer(minLength: 0)
            Button {
                if phase == .asking { model.questionPopupTimedOut() } else { model.closeQuestionPopup() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain.clicking())
            .accessibilityLabel(tr("关闭"))
        }
    }

    @ViewBuilder
    private func answer(_ question: MeetingQuestion, phase: Phase) -> some View {
        Group {
            if phase == .failed {
                Text(question.error ?? tr("没能回答"))
                    .foregroundStyle(.red)
            } else if question.answer.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ShimmerLine(reduceMotion: reduceMotion)
                    ShimmerLine(reduceMotion: reduceMotion).frame(width: 220)
                }
                .padding(.vertical, 2)
            } else {
                Text(LocalizedStringKey(question.answer))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(AppFont.secondary)
        .lineSpacing(3)
        .padding(.top, 10)
    }

    private func footer(_ question: MeetingQuestion, phase: Phase) -> some View {
        HStack(spacing: 8) {
            Button {
                model.page = .meetings
                model.openMeetingID = popup.meetingID
                model.jumpTranscript(popup.meetingID, to: question.at)
            } label: {
                Text(formatClock(question.at))
                    .font(AppFont.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain.clicking())
            .help(tr("跳到这一刻"))
            Spacer(minLength: 0)
            if phase == .asking {
                Button(tr("稍后")) { model.answerPopupQuestionLater() }
                    .buttonStyle(.bordered.clicking())
                Button(tr("现在回答")) { model.answerPopupQuestionNow() }
                    .buttonStyle(.borderedProminent.clicking())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(tr("在 Q&A 中查看")) { model.openPopupQuestionInQA() }
                    .buttonStyle(.link.clicking())
            }
        }
        .controlSize(.regular)
        .padding(.top, 12)
    }
}

/// The time left before the pop-up lets the question go. It redraws on its own, so the card
/// above it is not rebuilt twenty times a second, and it holds still while the pointer is on the card.
private struct CountdownBar: View {
    var seconds: TimeInterval
    var paused: Bool
    var onFinish: () -> Void

    @State private var elapsed: TimeInterval = 0
    @State private var resumedAt: Date?

    var body: some View {
        TimelineView(.animation(paused: paused)) { context in
            let left = max(0, 1 - total(at: context.date) / seconds)
            Capsule()
                .fill(AppColor.accent.opacity(0.35))
                .frame(height: 3)
                .scaleEffect(x: left, anchor: .leading)
        }
        .frame(height: 3)
        .padding(.horizontal, 18)
        .padding(.bottom, 1)
        .onAppear { if !paused { resumedAt = .now } }
        .onChange(of: paused) { _, now in
            if now {
                elapsed = total(at: .now)
                resumedAt = nil
            } else {
                resumedAt = .now
            }
        }
        .task(id: paused) {
            guard !paused else { return }
            let left = seconds - total(at: .now)
            try? await Task.sleep(for: .seconds(max(0, left)))
            if !Task.isCancelled { onFinish() }
        }
    }

    private func total(at date: Date) -> TimeInterval {
        elapsed + (resumedAt.map { date.timeIntervalSince($0) } ?? 0)
    }
}

private struct ShimmerLine: View {
    var reduceMotion: Bool
    @State private var lit = false

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(AppColor.surfaceInset)
            .frame(maxWidth: .infinity)
            .frame(height: 10)
            .opacity(lit ? 0.55 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { lit = true }
            }
    }
}
