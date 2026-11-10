import SwiftUI

/// What Nomi is doing for an answer, one line per step. The running step has its own dot loader, a
/// shimmer and its seconds; finished steps show what they found. While the model thinks, its
/// thinking streams in under the step; afterwards "思考了 N 秒 ›" opens it again.
struct AnswerStepsView: View {
    var steps: [AnswerStep]
    var thinking: String

    @State private var openThought: UUID?

    private var shown: [AnswerStep] { steps.filter { $0.isRunning || !$0.detail.isEmpty } }

    var body: some View {
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shown) { step in
                    if step.isRunning {
                        running(step)
                    } else {
                        finished(step)
                    }
                }
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle().fill(AppColor.separator).frame(width: 2)
            }
            .animation(.easeOut(duration: 0.2), value: shown.map(\.id))
        }
    }

    private func running(_ step: AnswerStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                DotLoader(style: DotLoader.Style(step.kind))
                Text(step.title)
                    .font(AppFont.secondary)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .shimmering()
                TimelineView(.periodic(from: step.startedAt, by: 1)) { _ in
                    Text(trf("%d 秒", step.seconds))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(AppColor.textSecondary.opacity(0.8))
                }
            }
            if step.kind == .thinking {
                let text = thinking.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    // The newest lines of the thinking, the oldest fading out at the top.
                    Text(String(text.suffix(600)))
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(4)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.leading, 24)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func finished(_ step: AnswerStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColor.accentGreen)
                    .frame(width: 32)
                if step.thought.isEmpty {
                    Text(step.detail)
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Button {
                        openThought = openThought == step.id ? nil : step.id
                    } label: {
                        HStack(spacing: 4) {
                            Text(step.detail)
                            Image(systemName: openThought == step.id ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain.clicking())
                }
            }
            if openThought == step.id {
                Text(step.thought)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(AppColor.surfaceInset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.leading, 24)
                    .textSelection(.enabled)
            }
        }
    }
}

/// The folded line above a finished answer: "用时 14 秒 · 读了 1 个文件 · 搜索 2 次 · 思考了 4 秒 ›".
/// Clicking it shows the steps again.
struct AnswerStepsFold: View {
    var steps: [AnswerStep]
    var seconds: Double?

    @State private var open = false

    var body: some View {
        let line = AnswerStepSummary.line(steps: steps, seconds: seconds)
        if !line.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { open.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(line)
                        if !steps.isEmpty {
                            Image(systemName: open ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain.clicking())
                .disabled(steps.isEmpty)
                if open {
                    AnswerStepsView(steps: steps, thinking: "")
                }
            }
        }
    }
}
