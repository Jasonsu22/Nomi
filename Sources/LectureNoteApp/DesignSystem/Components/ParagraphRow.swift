import SwiftUI

struct ParagraphRow: View, Equatable {
    var paragraph: Paragraph
    var sourceLanguage: String
    var targetLanguage: String
    var compare: Bool
    var fontSize: Double
    /// The paragraph a Q&A timestamp jumped to: filled for a moment, then it fades.
    var highlighted = false
    /// Who speaks, once the voice pass has run.
    var voices: MeetingVoices? = nil
    /// Start each speaker's words with their name, in their colour.
    var showSpeakers = false

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
                (labelled ? speakerText(\.translation, size: fontSize - 1, base: AppColor.textSecondary) : Text(translation.isEmpty ? " " : translation))
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
                        (labelled ? speakerText(\.translation, size: fontSize - 1, base: AppColor.textSecondary) : Text(translation))
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
        paragraph.renderedTranslation(language: targetLanguage)
    }

    /// Speaker labels are shown, and something here has a voice.
    private var labelled: Bool {
        showSpeakers && voices != nil && paragraph.commits.contains { $0.speaker != nil }
    }

    private var spoken: Text {
        labelled ? speakerText(\.source, size: fontSize, base: AppColor.textPrimary) : plainSpoken
    }

    /// The words split into one run per speaker, each starting with the speaker's name in their
    /// colour. Lines too short or too mixed to have a voice join the run before them.
    private func speakerText(_ words: KeyPath<Commit, String>, size: Double, base: Color) -> Text {
        guard let voices else { return Text("") }
        let language = words == \Commit.source ? (paragraph.sourceLanguage ?? sourceLanguage) : (paragraph.targetLanguage ?? targetLanguage)
        var runs: [(speaker: String?, parts: [String])] = []
        for commit in paragraph.commits {
            let text = commit[keyPath: words]
            if let speaker = commit.speaker, speaker != runs.last?.speaker ?? nil {
                runs.append((speaker, [text]))
            } else if runs.isEmpty {
                runs.append((nil, [text]))
            } else {
                runs[runs.count - 1].parts.append(text)
            }
        }
        var result = Text("")
        for (index, run) in runs.enumerated() {
            let body = TranscriptText.join(run.parts, language: language)
            guard !body.isEmpty else { continue }
            if index > 0 { result = result + Text(TranscriptText.usesSpaces(language) ? " " : "") }
            // The translation repeats a name only when the paragraph has more than one speaker.
            if let speaker = run.speaker, words == \Commit.source || Set(runs.compactMap(\.speaker)).count > 1 {
                result = result + Text(voices.name(of: speaker) + "  ")
                    .font(.system(size: size - 3, weight: .semibold))
                    .foregroundStyle(Self.color(of: speaker, in: voices))
            }
            result = result + Text(body).foregroundStyle(base)
        }
        return result
    }

    /// You in the accent colour; every other speaker, Speaker 1 included, in a colour of their own.
    static func color(of speaker: String, in voices: MeetingVoices) -> Color {
        if speaker == voices.me { return AppColor.accent }
        let palette: [Color] = [.teal, .orange, .pink, .purple, .green, .brown, .indigo, .mint, .red, .yellow]
        return palette[(voices.number(of: speaker) - 1) % palette.count]
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
