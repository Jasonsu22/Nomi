import SwiftUI

struct ParagraphRow: View, Equatable {
    var paragraph: Paragraph
    var sourceLanguage: String
    var targetLanguage: String
    var compare: Bool
    var fontSize: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(formatClock(paragraph.openedAt))
                .font(AppFont.caption)
                .monospacedDigit()
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 48, alignment: .leading)
            if compare {
                spoken
                    .font(.system(size: fontSize))
                    .lineSpacing(5)
                    .contentTransition(.interpolate)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(translation.isEmpty ? " " : translation)
                    .font(.system(size: fontSize - 1))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineSpacing(4)
                    .contentTransition(.interpolate)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    spoken
                        .font(.system(size: fontSize))
                        .lineSpacing(5)
                        .contentTransition(.interpolate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !translation.isEmpty {
                        Text(translation)
                            .font(.system(size: max(12, fontSize - 2)))
                            .foregroundStyle(AppColor.textSecondary)
                            .lineSpacing(4)
                            .contentTransition(.interpolate)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 10)
        .background {
            if paragraph.isLive {
                RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
                    .fill(AppColor.accentSoft)
            }
        }
    }

    private var source: String {
        paragraph.renderedSource(language: sourceLanguage)
    }

    private var translation: String {
        paragraph.renderedTranslation(language: targetLanguage)
    }

    private var spoken: Text {
        var committed = AttributedString(source)
        committed.foregroundColor = AppColor.textPrimary
        let pending = paragraph.tail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pending.isEmpty {
            if TranscriptText.needsSeparator(source, pending, language: sourceLanguage) {
                committed.append(AttributedString(" "))
            }
            var tail = AttributedString(pending)
            tail.foregroundColor = AppColor.textSecondary
            committed.append(tail)
        }
        return Text(committed)
    }
}
