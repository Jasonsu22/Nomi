import Foundation
import Testing
@testable import LectureNoteApp

struct MeetingRecordTests {
    private func answer(_ index: Int) -> MeetingAssistantRecord.Answer {
        .init(question: "问题 \(index)", answer: "回答 \(index)", modelName: "m", createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)))
    }

    @Test func aRecordRoundTripsAndKeepsTheNewestFiftyAnswers() throws {
        var record = MeetingAssistantRecord(summary: "要点", summaryModelName: "m", summaryAt: Date(timeIntervalSince1970: 1_800_000_000), summaryCoversUntil: 600)
        for index in 0..<55 { record.append(answer(index)) }
        #expect(record.answers.count == MeetingAssistantRecord.answerLimit)
        #expect(record.answers.first?.question == "问题 5")
        let again = try JSONDecoder().decode(MeetingAssistantRecord.self, from: JSONEncoder().encode(record))
        #expect(again == record)
    }

    @Test func aSummaryIsStaleOnlyWhenTheTranscriptGrewByMoreThanAMinute() {
        let record = MeetingAssistantRecord(summary: "要点", summaryCoversUntil: 600)
        #expect(!record.summaryIsStale(transcriptEnd: 650))
        #expect(record.summaryIsStale(transcriptEnd: 700))
        #expect(!MeetingAssistantRecord(summaryCoversUntil: 600).summaryIsStale(transcriptEnd: 9_999))
    }

    @MainActor @Test func theSidePanelPicksUpWhereItLeftOff() {
        var record = MeetingAssistantRecord(summary: "要点", summaryModelName: "m")
        record.append(answer(1))
        let state = MeetingAssistantState(record: record)
        #expect(state.summary == "要点")
        #expect(state.summaryModelName == "m")
        #expect(state.answers.map(\.question) == ["问题 1"])
        #expect(state.answers.first?.id == record.answers.first?.id)
        #expect(MeetingAssistantState(record: nil).answers.isEmpty)
    }

    @Test func aQuestionGetsTheRelevantLinesWithNeighboursInTimeOrder() {
        var lines = (0..<200).map { "[\($0):00] 今天继续讲课程安排和作业要求，这部分和考试关系不大。" }
        lines[120] = "[120:00] 薛定谔方程描述量子态如何随时间演化。"
        let picked = TranscriptSelection.pick(lines, query: "薛定谔方程是什么", budget: 600)
        #expect(TranscriptSelection.size(of: picked) <= 600)
        #expect(picked.contains(lines[120]))
        #expect(picked.contains(lines[119]) && picked.contains(lines[121]))
        let indices = picked.compactMap { lines.firstIndex(of: $0) }
        #expect(indices == indices.sorted())
    }

    @Test func aShortTranscriptIsSentWhole() {
        let lines = ["[0:00] 第一句。", "[0:10] 第二句。"]
        #expect(TranscriptSelection.pick(lines, query: "随便", budget: 1_000) == lines)
    }

    @Test func aLongTranscriptIsSplitAndALocalModelReadsAtMostFourPieces() {
        let lines = (0..<100).map { "[\($0):00] " + String(repeating: "内容", count: 40) }
        let all = TranscriptSelection.chunks(lines, budget: 1_000)
        #expect(!all.skipped)
        #expect(all.chunks.allSatisfy { TranscriptSelection.size(of: $0) <= 1_000 })
        #expect(all.chunks.flatMap { $0 } == lines)
        let capped = TranscriptSelection.chunks(lines, budget: 1_000, maxChunks: 4)
        #expect(capped.skipped)
        #expect(capped.chunks.count == 4)
        #expect(capped.chunks.first == all.chunks.first)
        #expect(capped.chunks.last == all.chunks.last)
    }

    @Test func aPinnedSummaryIsKeptAheadOfRankedPassages() {
        let summary = ContextBlock(title: "第一讲", detail: "会议摘要", body: "整节课讲了量子比特。", meetingID: nil, pinned: true)
        let paragraphs = (0..<20).map { ContextBlock(title: "第一讲", detail: "\($0)", body: String(repeating: "叠加态", count: 100), meetingID: nil) }
        let packed = ChatContext.pack([summary] + paragraphs, question: "叠加态", budget: 1_000)
        #expect(packed.first?.body == summary.body)
        #expect(packed.reduce(0) { $0 + $1.body.count } <= 1_000)
    }

    @Test func aSavedMeetingSummaryIsSearchable() {
        let documents = LibrarySearch.meetingDocuments(
            id: UUID(), title: "第一讲", startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            paragraphs: [(0, "第一段。", "")], summary: "这节课讲了量子比特。"
        )
        #expect(documents.count == 2)
        #expect(documents.first?.body == "这节课讲了量子比特。")
    }
}
