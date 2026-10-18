import SwiftUI

struct MeetingAssistantPanel: View {
    var model: AppModel
    var meeting: Meeting
    var summary = false
    @State private var question = ""

    private var state: MeetingAssistantState? { model.assistantStates[meeting.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(model.assistantModelName).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    if summary {
                        if let text = state?.summary {
                            result(text, modelName: state?.summaryModelName ?? "")
                        } else {
                            Text(tr("生成这场会议的要点、术语和结论。"))
                                .font(AppFont.secondary).foregroundStyle(AppColor.textSecondary)
                        }
                    } else {
                        if state?.answers.isEmpty != false {
                            Text(tr("根据这场会议的转写提问，回答会引用相关时间。"))
                                .font(AppFont.secondary).foregroundStyle(AppColor.textSecondary)
                        }
                        ForEach(state?.answers ?? []) { answer in
                            VStack(alignment: .leading, spacing: Space.s2) {
                                Text(answer.question).font(AppFont.body.weight(.medium))
                                result(answer.answer, modelName: answer.modelName)
                            }
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
                Button(summary ? (state?.summary == nil ? tr("生成摘要") : tr("重新生成")) : tr("发送")) {
                    let value = question.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.generateAssistant(for: meeting.id, question: summary ? nil : value)
                }
                .buttonStyle(.borderedProminent)
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
                    Button(tr("配置大模型")) { model.page = .settings }.buttonStyle(.link)
                }
            }
        }
        .padding(Space.s4)
        .onChange(of: state?.answers.count) { _, _ in
            if state?.answers.last?.question == question.trimmingCharacters(in: .whitespacesAndNewlines) { question = "" }
        }
    }

    private func result(_ text: String, modelName: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(.init(text)).font(AppFont.secondary).textSelection(.enabled)
            Text(modelName).font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
        }
    }
}
