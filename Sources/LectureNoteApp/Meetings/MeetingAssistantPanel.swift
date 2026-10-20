import SwiftUI

struct MeetingAssistantPanel: View {
    var model: AppModel
    var meeting: Meeting
    var summary = false
    @State private var question = ""

    private var state: MeetingAssistantState? { model.assistantStates[meeting.id] }
    /// What the panel produced before, shown until this session asks something new.
    private var record: MeetingAssistantRecord? { meeting.assistant }

    private var shownSummary: String? { state?.summary ?? record?.summary }

    private var shownSummaryModel: String {
        if let state, state.summary != nil { return state.summaryModelName }
        return record?.summaryModelName ?? ""
    }

    private var shownAnswers: [MeetingAssistantAnswer] {
        if let state { return state.answers }
        return (record?.answers ?? []).map {
            MeetingAssistantAnswer(id: $0.id, question: $0.question, answer: $0.answer, modelName: $0.modelName, createdAt: $0.createdAt)
        }
    }

    private var summaryIsStale: Bool {
        guard state?.isGenerating != true, let record, state?.summary == nil || state?.summary == record.summary else { return false }
        return record.summaryIsStale(transcriptEnd: meeting.paragraphs.map(\.openedAt).max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(model.assistantModelName).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if summary {
                        if state?.isGenerating == true, let draft = state?.draft, !draft.isEmpty {
                            result(draft, modelName: state?.summaryModelName ?? "", streaming: true)
                        } else if let text = shownSummary {
                            result(text, modelName: shownSummaryModel)
                            if summaryIsStale {
                                Text(tr("转写有更新，可以重新生成摘要。"))
                                    .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                            }
                        } else {
                            Text(tr("生成这场会议的要点、术语和结论。"))
                                .font(AppFont.secondary).foregroundStyle(AppColor.textSecondary)
                        }
                    } else {
                        if shownAnswers.isEmpty && (state?.draft.isEmpty != false) {
                            Text(tr("根据这场会议的转写提问，回答会引用相关时间。"))
                                .font(AppFont.secondary).foregroundStyle(AppColor.textSecondary)
                        }
                        ForEach(shownAnswers) { answer in
                            VStack(alignment: .leading, spacing: Space.s2) {
                                Text(answer.question).font(AppFont.body.weight(.medium))
                                result(answer.answer, modelName: answer.modelName)
                            }
                        }
                        if state?.isGenerating == true, let draft = state?.draft, !draft.isEmpty {
                            result(draft, modelName: "", streaming: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = state?.error {
                Text(error).font(AppFont.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            if !summary {
                TextEditor(text: $question)
                    .font(AppFont.secondary)
                    .scrollContentBackground(.hidden)
                    .padding(Space.s2)
                    .frame(height: 72)
                    .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    .accessibilityLabel(tr("输入问题"))
            }
            HStack {
                if state?.isGenerating == true {
                    ProgressView().controlSize(.small)
                    Text(tr("正在生成…")).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                }
                Spacer()
                Button(summary ? (shownSummary == nil ? tr("生成摘要") : tr("重新生成")) : tr("发送")) {
                    let value = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.generateAssistant(for: meeting.id, question: summary ? nil : value)
                }
                .buttonStyle(.borderedProminent.clicking())
                .disabled(!model.canGenerateAssistant || (!summary && question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            if model.llmConfiguration.mode == .api {
                Text(tr("使用 API 会将这场会议的文字发送到所选服务。"))
                    .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            }
            if !model.canGenerateAssistant && !model.assistantIsBusy {
                if model.engine.session.phase != .idle {
                    Text(tr("录制结束后可生成回答和摘要。"))
                        .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                } else {
                    Button(tr("配置大模型")) { model.page = .settings }.buttonStyle(.link.clicking())
                }
            }
        }
        .padding(Space.s4)
        .onChange(of: state?.answers.count) { _, _ in
            if state?.answers.last?.question == question.trimmingCharacters(in: .whitespacesAndNewlines) { question = "" }
        }
    }

    private func result(_ text: String, modelName: String, streaming: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            AnswerBody(source: text, streaming: streaming)
            if !modelName.isEmpty {
                Text(modelName).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            }
        }
    }
}
