import SwiftUI

struct ParagraphRow: View, Equatable {
    var paragraph: Paragraph
    var sourceLanguage: String
    var targetLanguage: String
    var compare: Bool
    var fontSize: Double
    /// The paragraph a Q&A timestamp jumped to: filled for a moment, then it fades.
    var highlighted = false
    /// Who the teacher is, once the voice pass has run: classmates' lines are greyed.
    var voices: MeetingVoices? = nil
    /// Leave classmates' lines out.
    var teacherOnly = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Text(formatClock(paragraph.openedAt))
                .font(AppFont.caption)
                .monospacedDigit()
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
                // Wide enough for 1:11:45 in a class longer than an hour.
                .frame(width: 56, alignment: .leading)
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
                            .font(.system(size: fontSize - 1))
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
            if highlighted {
                RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
                    .fill(AppColor.selection)
                    .transition(.opacity)
            } else if paragraph.isLive {
                RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
                    .fill(AppColor.accentSoft)
            }
        }
    }

    private var source: String {
        paragraph.renderedSource(language: sourceLanguage)
    }

    private var translation: String {
        guard let voices, teacherOnly else { return paragraph.renderedTranslation(language: targetLanguage) }
        return TranscriptText.join(paragraph.commits.filter { !voices.isClassmate($0) }.map(\.translation), language: paragraph.targetLanguage ?? targetLanguage)
    }

    /// Whether any line here is a classmate's.
    private var hasClassmate: Bool {
        guard let voices else { return false }
        return paragraph.commits.contains(where: voices.isClassmate)
    }

    private var spoken: Text {
        guard let voices, hasClassmate else { return plainSpoken }
        // Runs of lines by one side, so a classmate's words read as one greyed stretch with a tag.
        var result = Text("")
        var started = false
        var run: [Commit] = []
        func flush() {
            guard let first = run.first else { return }
            let student = voices.isClassmate(first)
            let text = TranscriptText.join(run.map(\.source), language: paragraph.sourceLanguage ?? sourceLanguage)
            run = []
            if student && teacherOnly { return }
            if started, TranscriptText.usesSpaces(paragraph.sourceLanguage ?? sourceLanguage) { result = result + Text(" ") }
            started = true
            if student {
                result = result
                    + Text(Image(systemName: "person.2")).font(.system(size: fontSize - 3)).foregroundStyle(AppColor.textSecondary)
                    + Text(" " + text).foregroundStyle(AppColor.textSecondary)
            } else {
                result = result + Text(text).foregroundStyle(AppColor.textPrimary)
            }
        }
        for commit in paragraph.commits {
            if let last = run.last, voices.isClassmate(last) != voices.isClassmate(commit) { flush() }
            run.append(commit)
        }
        flush()
        return result
    }

    private var plainSpoken: Text {
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
