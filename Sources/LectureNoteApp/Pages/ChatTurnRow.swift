import SwiftUI

/// Equality is explicit: parent updates must not rebuild completed rich text.
struct ChatTurnRow: View, Equatable {
    var turn: ChatTurn
    var model: AppModel
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.turn == rhs.turn && lhs.model === rhs.model
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: Space.s2) {
                    if !turn.images.isEmpty {
                        StoredImageStrip(images: turn.images)
                    }
                    if !turn.question.isEmpty {
                        Text(turn.question)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            if let error = turn.error {
                Text(error)
                    .font(AppFont.secondary)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if !turn.answer.isEmpty {
                AnswerBody(source: turn.answer, citations: turn.citations, cacheNamespace: turn.id.uuidString) { citation in
                    model.openCitation(citation)
                }
                .equatable()
                .frame(maxWidth: 680, alignment: .leading)
            }
        }
    }
}

/// Only this subtree observes the changing answer and citations.
struct ChatPendingTurn: View {
    var question: String
    var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: Space.s2) {
                    if !model.pendingImageDrafts.isEmpty {
                        ChatImageStrip(items: model.pendingImageDrafts)
                    }
                    if !question.isEmpty {
                        Text(question)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            if model.pendingAnswer.isEmpty {
                HStack(spacing: Space.s2) {
                    ProgressView().controlSize(.small)
                    Text(tr("正在回答…"))
                        .font(AppFont.secondary)
                        .foregroundStyle(AppColor.textSecondary)
                }
            } else {
                AnswerBody(source: model.pendingAnswer, streaming: true, citations: model.pendingCitations) { citation in
                    model.openCitation(citation)
                }
                .equatable()
                .frame(maxWidth: 680, alignment: .leading)
            }
        }
    }
}
