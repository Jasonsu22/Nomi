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
    var fileURL: URL?
    var page: Int?
    var meetingID: UUID?
    var at: TimeInterval?
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
    static var playMoment: ((UUID, TimeInterval) -> Void)?
}

extension AppModel {
    func installCitationLookup() {
        CitationLookup.details = { [weak self] citation in
            self?.citationDetails(citation) ?? CitationDetails(kind: CitationKind.of(citation), origin: citation.title)
        }
        CitationLookup.fileExcerpt = { [weak self] citation in
            await self?.citationFileExcerpt(citation) ?? ""
        }
        CitationLookup.playMoment = { [weak self] meetingID, at in
            guard let self, let meeting = self.meetings.first(where: { $0.id == meetingID }) else { return }
            MomentPlayer.shared.play(meeting, at: at)
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
            let at = citation.at ?? CitationQuote.clockSeconds(in: citation.detail)
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

    /// Up to `CitationQuote.excerptLimit` characters of `text`, kept around `quote`.
    static func window(_ text: String, around quote: String) -> String {
        let limit = CitationQuote.excerptLimit
        guard text.count > limit else { return text }
        guard !quote.isEmpty, let range = text.range(of: quote) else { return String(text.prefix(limit)) + "…" }
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let from = max(0, min(start - 120, text.count - limit))
        let head = text.index(text.startIndex, offsetBy: from)
        let tail = text.index(head, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex
        return (from > 0 ? "…" : "") + String(text[head..<tail]) + (tail < text.endIndex ? "…" : "")
    }
}

/// Plays ten seconds of a meeting's recording from a moment. A meeting recorded in several runs
/// keeps one file per run; the moment is found by adding up the earlier files' lengths.
@MainActor
final class MomentPlayer {
    static let shared = MomentPlayer()
    static let clipSeconds: TimeInterval = 10

    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func play(_ meeting: Meeting, at moment: TimeInterval) {
        stop()
        let folder = MeetingStore.audioDirectory(for: meeting.id)
        var start: TimeInterval = 0
        for name in meeting.audioFiles ?? [] {
            guard let file = try? AVAudioPlayer(contentsOf: folder.appendingPathComponent(name)) else { continue }
            if moment < start + file.duration || name == meeting.audioFiles?.last {
                file.currentTime = max(0, min(moment - start - 0.5, file.duration - 0.5))
                file.prepareToPlay()
                file.play()
                player = file
                stopTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(Self.clipSeconds))
                    guard !Task.isCancelled else { return }
                    self?.stop()
                }
                return
            }
            start += file.duration
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
    }

    var isPlaying: Bool { player?.isPlaying == true }
}
