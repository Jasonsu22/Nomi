import AppKit
import AVFoundation
import Foundation

/// What a citation points to, which decides how its preview card looks and what a click does.
enum CitationKind: Equatable, Sendable {
    case lecture, summary, pdf, slides, document, picture, web, chat, missing

    private static let slideTypes: Set<String> = ["ppt", "pptx", "key", "odp"]
    private static let pictureTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp"]

    /// From the citation alone, before looking anything up.
    static func of(_ citation: ChatCitation, fileName: String? = nil) -> CitationKind {
        if citation.chatID != nil { return .chat }
        if citation.meetingID != nil {
            let detail = citation.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail == tr("会议摘要") || detail == "会议摘要" ? .summary : .lecture
        }
        if citation.sourceID != nil {
            let name = (fileName ?? citation.title).lowercased()
            let type = (name as NSString).pathExtension
            if type == "pdf" { return .pdf }
            if slideTypes.contains(type) { return .slides }
            if pictureTypes.contains(type) { return .picture }
            return .document
        }
        return .web
    }

    var symbol: String {
        switch self {
        case .lecture: "clock"
        case .summary: "sparkles"
        case .pdf: "doc.richtext"
        case .slides: "rectangle.on.rectangle"
        case .document: "doc.text"
        case .picture: "photo"
        case .web: "globe"
        case .chat: "bubble.left.and.bubble.right"
        case .missing: "exclamationmark.triangle"
        }
    }
}

/// Everything a preview card shows for one citation.
struct CitationDetails: Equatable {
    var kind: CitationKind
    /// Where it is from: the meeting, file, site or chat.
    var origin: String
    /// Where inside it: "31:20", "第 3 页", a date.
    var place = ""
    /// A web page's or earlier question's own title.
    var title = ""
    /// The words the answer relied on, marked inside `excerpt`.
    var quote = ""
    /// A little of the source around the quote.
    var excerpt = ""
    /// The translation of a lecture line.
    var translation = ""
    /// The translation of the quoted sentences, marked inside `translation`.
    var translationQuote = ""
    var fileURL: URL?
    var page: Int?
    var meetingID: UUID?
    /// Where the cited words are spoken: the recording plays from here.
    var at: TimeInterval?
    /// The transcript line that holds them. A sentence can start a little before its line opens,
    /// so the jump and the shown time use the line's own time, as the transcript does.
    var lineAt: TimeInterval?
    /// Where the cited words end, so "Play this moment" plays all of them.
    var until: TimeInterval?
    var webURL: URL?
    /// Set when the source was removed; the card says so instead of showing nothing.
    var missing: String?
    /// A lecture whose recording is still on this Mac can play the cited moment.
    var hasAudio = false
}

/// The app's data, reachable from the answer page's preview card without passing the model down.
@MainActor
enum CitationLookup {
    static var details: ((ChatCitation) -> CitationDetails)?
    static var fileExcerpt: ((ChatCitation) async -> String)?
    /// Plays a meeting from a moment to `until`; returns how many seconds it will play.
    static var playMoment: ((UUID, TimeInterval, TimeInterval?) -> TimeInterval?)?
}

extension AppModel {
    func installCitationLookup() {
        CitationLookup.details = { [weak self] citation in
            self?.citationDetails(citation) ?? CitationDetails(kind: CitationKind.of(citation), origin: citation.title)
        }
        CitationLookup.fileExcerpt = { [weak self] citation in
            await self?.citationFileExcerpt(citation) ?? ""
        }
        CitationLookup.playMoment = { [weak self] meetingID, at, until in
            guard let self, let meeting = self.meetings.first(where: { $0.id == meetingID }) else { return nil }
            return MomentPlayer.shared.play(meeting, at: at, until: until)
        }
    }

    /// The preview for a citation, from the meetings, files and chats on this Mac. Citations saved
    /// before quotes were kept get their time and words from the meeting itself.
    func citationDetails(_ citation: ChatCitation) -> CitationDetails {
        if let id = citation.meetingID {
            guard let stored = meetings.first(where: { $0.id == id }) else {
                return CitationDetails(kind: .missing, origin: citation.title, missing: tr("这场会议已经删除，无法预览。"))
            }
            let meeting = current(stored)
            let origin = "\(meeting.title) · \(formatMonthDay(meeting.startedAt))"
            if CitationKind.of(citation) == .summary {
                let summary = meeting.assistant?.summary ?? ""
                return CitationDetails(
                    kind: .summary, origin: origin, place: tr("摘要"),
                    quote: citation.quote ?? "",
                    excerpt: citation.excerpt ?? String(summary.prefix(CitationQuote.excerptLimit)),
                    meetingID: id
                )
            }
            let near = citation.at ?? CitationQuote.clockSeconds(in: citation.detail)
            // The sentences themselves, found again in the transcript from the quoted words: the
            // citation's own time is only where its search chunk started.
            let needle = [citation.quote, citation.excerpt].compactMap { $0 }.first { !$0.isEmpty } ?? ""
            if let moment = LectureMoments.locate(in: meeting.paragraphs, near: near, needle: needle,
                                                  sourceLanguage: meeting.sourceLanguage, targetLanguage: meeting.targetLanguage) {
                let paragraph = meeting.paragraphs[moment.paragraph]
                let quote = moment.source, translated = moment.translation
                let lineAt = max(moment.at, paragraph.openedAt)
                var details = CitationDetails(kind: .lecture, origin: origin, place: formatClock(lineAt), meetingID: id, at: moment.at, lineAt: lineAt)
                details.quote = quote
                // The whole line, which the card scrolls; it starts just before the quote so the marked
                // words show first.
                details.excerpt = Self.fromNear(paragraph.renderedSource(language: meeting.sourceLanguage), quote: quote)
                details.translationQuote = translated
                details.translation = Self.fromNear(paragraph.renderedTranslation(language: meeting.targetLanguage), quote: translated)
                details.until = moment.end
                details.hasAudio = !(meeting.audioFiles ?? []).isEmpty
                return details
            }
            let at = near
            var details = CitationDetails(kind: .lecture, origin: origin, place: at.map(formatClock) ?? citation.detail, meetingID: id, at: at)
            if let at, let index = meeting.paragraphs.lastIndex(where: { $0.openedAt <= at + 1.5 }) ?? meeting.paragraphs.indices.first {
                let paragraph = meeting.paragraphs[index]
                // What was said from that moment on: the paragraph and the ones after it, up to the card's length.
                var spoken = ""
                for next in meeting.paragraphs[index...] {
                    let text = next.renderedSource(language: meeting.sourceLanguage).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    spoken += (spoken.isEmpty ? "" : " ") + text
                    if spoken.count >= CitationQuote.excerptLimit { break }
                }
                let opening = CitationQuote.sentences(spoken).prefix(2).joined(separator: " ")
                let picked = citation.quote.map { ($0, citation.excerpt ?? spoken) } ?? (opening, spoken)
                details.quote = picked.0
                details.excerpt = Self.window(picked.1.isEmpty ? spoken : picked.1, around: picked.0)
                let translated = paragraph.renderedTranslation(language: meeting.targetLanguage).trimmingCharacters(in: .whitespacesAndNewlines)
                details.translation = translated.count > 260 ? String(translated.prefix(260)) + "…" : translated
                details.until = paragraph.commits.last?.end
            } else {
                details.quote = citation.quote ?? ""
                details.excerpt = citation.excerpt ?? ""
            }
            details.hasAudio = !(meeting.audioFiles ?? []).isEmpty && at != nil
            return details
        }
        if let id = citation.sourceID {
            guard let source = sources.first(where: { $0.id == id }) else {
                return CitationDetails(kind: .missing, origin: citation.title, missing: tr("这个文件已从资料中移除，无法预览。"))
            }
            let kind = CitationKind.of(citation, fileName: source.fileName)
            let page = citation.page ?? CitationQuote.pageNumber(in: citation.detail)
            let place: String
            if let page {
                place = kind == .slides ? trf("第 %d 张", page) : trf("第 %d 页", page)
            } else {
                place = citation.detail
            }
            return CitationDetails(
                kind: kind, origin: source.fileName, place: place,
                quote: citation.quote ?? "", excerpt: citation.excerpt ?? "",
                fileURL: SourceStore.fileURL(for: source), page: page
            )
        }
        if let id = citation.chatID {
            guard let chat = chats.first(where: { $0.id == id }) else {
                return CitationDetails(kind: .missing, origin: citation.title, missing: tr("这段对话已经删除，无法预览。"))
            }
            let first = chat.turns.first { !$0.answer.isEmpty }
            let title = chat.title.isEmpty ? tr("对话") : chat.title
            return CitationDetails(
                kind: .chat, origin: title, place: formatMonthDay(chat.updatedAt),
                title: citation.quote == nil ? (first.map { "“\(String($0.question.prefix(80)))”" } ?? "") : "",
                quote: citation.quote ?? "",
                excerpt: citation.excerpt ?? first.map { String(ChatHistory.cleanedAnswer($0.answer, limit: 300)) } ?? ""
            )
        }
        let url = citation.url.flatMap(URL.init(string:))
        let host = url?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? citation.detail
        let title = citation.title == host || citation.title == citation.url ? "" : citation.title
        return CitationDetails(kind: .web, origin: host, title: title, quote: citation.quote ?? "", excerpt: citation.excerpt ?? "", webURL: url)
    }

    /// The cited page's text, for a citation saved before excerpts were kept.
    func citationFileExcerpt(_ citation: ChatCitation) async -> String {
        guard let id = citation.sourceID, let source = sources.first(where: { $0.id == id }) else { return "" }
        let blocks = await SourceTextCache.shared.blocks(for: source)
        let page = citation.page ?? CitationQuote.pageNumber(in: citation.detail)
        let block = blocks.first { $0.page != nil && $0.page == page } ?? blocks.first { $0.detail == citation.detail } ?? blocks.first
        guard let body = block?.body else { return "" }
        return CitationQuote.pick(in: body, for: "").excerpt
    }

    /// `text` from a little before `quote` on, up to `limit` characters.
    static func fromNear(_ text: String, quote: String, lead: Int = 120, limit: Int = 2_400) -> String {
        guard !quote.isEmpty, let range = text.range(of: quote) else { return text.count > limit ? String(text.prefix(limit)) + "…" : text }
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        var head = text.startIndex
        if start > lead + 40 {
            // Back up to a sentence end within the lead, so the text starts with a whole sentence.
            let earliest = text.index(text.startIndex, offsetBy: start - lead)
            let ends: Set<Character> = ["。", "！", "？", ".", "!", "?"]
            head = text[earliest..<range.lowerBound].firstIndex { ends.contains($0) }.map { text.index(after: $0) } ?? earliest
            while head < range.lowerBound, text[head].isWhitespace { head = text.index(after: head) }
        }
        let tail = text.index(head, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
        return (head > text.startIndex ? "…" : "") + String(text[head..<tail]) + (tail < text.endIndex ? "…" : "")
    }

    /// Up to `limit` characters of `text`, kept around `quote`.
    static func window(_ text: String, around quote: String, limit: Int = CitationQuote.excerptLimit) -> String {
        guard text.count > limit else { return text }
        guard !quote.isEmpty, let range = text.range(of: quote) else { return String(text.prefix(limit)) + "…" }
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let from = max(0, min(start - limit / 4, text.count - limit))
        let head = text.index(text.startIndex, offsetBy: from)
        let tail = text.index(head, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
        return (from > 0 ? "…" : "") + String(text[head..<tail]) + (tail < text.endIndex ? "…" : "")
    }
}

/// Plays ten seconds of a meeting's recording from a moment. A meeting recorded in several runs
/// keeps one file per run; the moment is found by adding up the earlier files' lengths.
///
/// Lengths and positions are counted in samples. `AVAudioPlayer` only estimates them for the app's
/// AAC files, and for a long lecture it was off by twenty minutes, so late moments played from the
/// wrong file and earlier ones drifted.
@MainActor
final class MomentPlayer {
    static let shared = MomentPlayer()
    /// How long a moment plays when where its words end is not known.
    nonisolated static let clipSeconds: TimeInterval = 10
    /// A little after the last word, so it is not cut off; and a cap for very long passages.
    nonisolated static let tail: TimeInterval = 1.0
    nonisolated static let longest: TimeInterval = 180

    /// Seconds to play from `moment` (less the lead-in) to just after `until`.
    nonisolated static func length(from moment: TimeInterval, until: TimeInterval?) -> TimeInterval {
        guard let until, until > moment else { return clipSeconds + leadIn }
        return min(longest, until - moment + leadIn + tail)
    }
    /// Starts a little before the words, so the first one is not clipped.
    nonisolated static let leadIn: TimeInterval = 0.8

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var attached = false
    private var playing = false
    private var stopTask: Task<Void, Never>?

    /// Which file holds `moment`, and how far into it, given each file's length in seconds.
    nonisolated static func locate(_ moment: TimeInterval, in lengths: [TimeInterval]) -> (file: Int, offset: TimeInterval)? {
        guard !lengths.isEmpty else { return nil }
        var start: TimeInterval = 0
        for (index, length) in lengths.enumerated() {
            if moment < start + length || index == lengths.count - 1 {
                return (index, max(0, min(moment - start, length)))
            }
            start += length
        }
        return nil
    }

    /// Plays from just before `moment` to just after `until`. Returns the seconds it will play.
    @discardableResult
    func play(_ meeting: Meeting, at moment: TimeInterval, until: TimeInterval? = nil) -> TimeInterval? {
        stop()
        let folder = MeetingStore.audioDirectory(for: meeting.id)
        let files = (meeting.audioFiles ?? []).compactMap { try? AVAudioFile(forReading: folder.appendingPathComponent($0)) }
        let lengths = files.map { Double($0.length) / $0.fileFormat.sampleRate }
        guard let (index, offset) = Self.locate(moment, in: lengths) else { return nil }
        let file = files[index]
        let rate = file.processingFormat.sampleRate
        let first = min(AVAudioFramePosition(max(0, offset - Self.leadIn) * rate), max(0, file.length - 1))
        let count = AVAudioFrameCount(max(0, min(Double(file.length - first), Self.length(from: moment, until: until) * rate)))
        guard count > 0 else { return nil }
        if !attached {
            engine.attach(node)
            attached = true
        }
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
        do { try engine.start() } catch { return nil }
        node.scheduleSegment(file, startingFrame: first, frameCount: count, at: nil)
        node.play()
        playing = true
        stopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Double(count) / rate))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
        return Double(count) / rate
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        if attached { node.stop() }
        if engine.isRunning { engine.stop() }
        playing = false
    }

    var isPlaying: Bool { playing }
}
