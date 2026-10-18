import Foundation
import SwiftUI

struct Commit: Identifiable, Equatable {
    var id: Int
    var source: String
    var translation: String
    var start: TimeInterval
    var end: TimeInterval
}

struct Paragraph: Identifiable, Equatable {
    var id: Int
    var openedAt: TimeInterval
    var commits: [Commit]
    var tail: String
    var closed: Bool

    var source: String {
        commits.map(\.source).joined()
    }

    var translation: String {
        commits.map(\.translation).filter { !$0.isEmpty }.joined(separator: " ")
    }

    var isLive: Bool { !closed }
}

enum TranscriptChange: Equatable {
    case tailReplaced
    case paragraphOpened
    case committed
}

struct TranscriptBuilder {
    static let maxCharacters = 200
    static let pauseGap: TimeInterval = 2

    private(set) var paragraphs: [Paragraph] = []
    private var nextParagraphID = 1

    @discardableResult
    mutating func applyTail(text: String, start: TimeInterval) -> TranscriptChange {
        let before = paragraphs.count
        let index = indexForIncoming(start: start)
        paragraphs[index].tail = text
        return paragraphs.count > before ? .paragraphOpened : .tailReplaced
    }

    @discardableResult
    mutating func applyCommit(_ commit: Commit, tail: String) -> TranscriptChange {
        let index = indexForIncoming(start: commit.start)
        paragraphs[index].commits.append(commit)
        if shouldClose(paragraphs[index]) {
            paragraphs[index].tail = ""
            paragraphs[index].closed = true
            if !tail.isEmpty {
                let next = openParagraph(at: commit.end)
                paragraphs[next].tail = tail
            }
        } else {
            paragraphs[index].tail = tail
        }
        return .committed
    }

    mutating func flush(at end: TimeInterval) {
        guard let index = paragraphs.indices.last else { return }
        if !paragraphs[index].tail.isEmpty {
            let tail = paragraphs[index].tail
            let start = paragraphs[index].commits.last?.end ?? paragraphs[index].openedAt
            let id = (paragraphs.flatMap(\.commits).map(\.id).max() ?? 0) + 1
            applyCommit(
                Commit(id: id, source: tail, translation: "", start: start, end: max(end, start)),
                tail: ""
            )
        }
        for index in paragraphs.indices {
            paragraphs[index].closed = true
            paragraphs[index].tail = ""
        }
    }

    private mutating func indexForIncoming(start: TimeInterval) -> Int {
        guard let lastIndex = paragraphs.indices.last else {
            return openParagraph(at: start)
        }
        if paragraphs[lastIndex].closed {
            return openParagraph(at: start)
        }
        let anchor = paragraphs[lastIndex].commits.last?.end ?? paragraphs[lastIndex].openedAt
        let hasContent = !paragraphs[lastIndex].commits.isEmpty || !paragraphs[lastIndex].tail.isEmpty
        if hasContent && start - anchor > Self.pauseGap {
            paragraphs[lastIndex].closed = true
            return openParagraph(at: start)
        }
        return lastIndex
    }

    private mutating func openParagraph(at start: TimeInterval) -> Int {
        let paragraph = Paragraph(
            id: nextParagraphID,
            openedAt: start,
            commits: [],
            tail: "",
            closed: false
        )
        nextParagraphID += 1
        paragraphs.append(paragraph)
        return paragraphs.count - 1
    }

    private func shouldClose(_ paragraph: Paragraph) -> Bool {
        let text = paragraph.source
        guard text.count >= Self.maxCharacters, let last = text.last else { return false }
        return "。！？!?".contains(last)
    }
}

@MainActor
@Observable
final class LiveTranscript {
    var paragraphs: [Paragraph] = []
    private var builder = TranscriptBuilder()

    func reset() {
        builder = TranscriptBuilder()
        paragraphs = []
    }

    func applyTail(text: String, start: TimeInterval, reduceMotion: Bool) {
        publish(builder.applyTail(text: text, start: start), reduceMotion: reduceMotion)
    }

    func applyCommit(_ commit: Commit, tail: String, reduceMotion: Bool) {
        publish(builder.applyCommit(commit, tail: tail), reduceMotion: reduceMotion)
    }

    func flush(at end: TimeInterval, reduceMotion: Bool) {
        builder.flush(at: end)
        publish(.committed, reduceMotion: reduceMotion)
    }

    private func publish(_ change: TranscriptChange, reduceMotion: Bool) {
        let updated = builder.paragraphs
        switch change {
        case .tailReplaced:
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                paragraphs = updated
            }
        case .paragraphOpened, .committed:
            withAnimation(Motion.layout(reduceMotion)) {
                paragraphs = updated
            }
        }
    }
}
