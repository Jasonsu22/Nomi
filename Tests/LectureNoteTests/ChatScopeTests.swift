import Foundation
import Testing
@testable import LectureNoteApp

struct ChatScopeTests {
    private let course = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let other = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    @Test func wholeCategoryIncludesAMeetingAddedLater() {
        let first = item("m1", course)
        var scope = ChatScope()
        scope.toggleCategory(course, meetings: [first], sources: [])
        let later = item("m2", course)
        let selected = scope.selectedMeetings([first, later])
        #expect(selected == [first.id, later.id])
    }

    @Test func excludingOneKeepsTheCategoryAndALaterMeeting() {
        let first = item("m1", course)
        let second = item("m2", course)
        var scope = ChatScope()
        scope.toggleCategory(course, meetings: [first, second], sources: [])
        scope.toggleMeeting(first, meetings: [first, second], sources: [])
        let later = item("m3", course)
        let selected = scope.selectedMeetings([first, second, later])
        #expect(selected == [second.id, later.id])
        #expect(scope.categoryIDs == [course])
    }

    @Test func explicitMeetingsDoNotIncludeALaterOne() {
        let first = item("m1", course)
        let second = item("m2", course)
        var scope = ChatScope()
        scope.toggleMeeting(first, meetings: [first, second], sources: [])
        let later = item("m3", course)
        #expect(scope.selectedMeetings([first, second, later]) == [first.id])
    }

    @Test func selectingEveryCurrentItemPromotesTheCategory() {
        let first = item("m1", course)
        let second = item("m2", course)
        var scope = ChatScope()
        scope.toggleMeeting(first, meetings: [first, second], sources: [])
        scope.toggleMeeting(second, meetings: [first, second], sources: [])
        #expect(scope.categoryIDs == [course])
        #expect(scope.meetingIDs.isEmpty)
        let later = item("m3", course)
        #expect(scope.selectedMeetings([first, second, later]) == [first.id, second.id, later.id])
    }

    @Test func liveMeetingIsNeverSelected() {
        let live = item("live", course, live: true)
        let saved = item("saved", course)
        var scope = ChatScope()
        scope.toggleAll(meetings: [live, saved], sources: [])
        scope.toggleMeeting(live, meetings: [live, saved], sources: [])
        #expect(scope.selectedMeetings([live, saved]) == [saved.id])
        scope.meetingIDs.insert(live.id)
        #expect(!scope.selectedMeetings([live, saved]).contains(live.id))
    }

    @Test func turningOffOneCategoryFromAllKeepsTheOther() {
        let english = item("en", course)
        let math = item("math", other)
        var scope = ChatScope()
        scope.toggleAll(meetings: [english, math], sources: [])
        scope.toggleCategory(course, meetings: [english, math], sources: [])
        #expect(scope.includeAll == false)
        #expect(scope.selectedMeetings([english, math]) == [math.id])
    }

    @Test func deletedCategoryDoesNotKeepItsOldItems() {
        let loose = item("loose", nil)
        var scope = ChatScope()
        scope.categoryIDs.insert(course)
        #expect(scope.selectedMeetings([loose]).isEmpty)
    }

    @Test func chipNamesASingleCategory() {
        let meeting = item("m1", course)
        let source = item("s1", course)
        var scope = ChatScope()
        scope.toggleCategory(course, meetings: [meeting], sources: [source])
        let title = scope.chipTitle(
            meetings: [meeting],
            sources: [source],
            categories: [ScopeCategoryName(id: course, name: "计算机课"), ScopeCategoryName(id: nil, name: "未分类")]
        )
        #expect(title.contains("计算机课"))
        #expect(title.contains("1"))
    }

    @Test func shortPassagesStayInOrderAndLongOnesPreferTheQuestion() {
        let intro = ContextBlock(title: "课", detail: "0:01", body: "今天点名", meetingID: UUID())
        let match = ContextBlock(title: "课", detail: "12:30", body: "拥塞控制窗口", meetingID: UUID())
        let packed = ChatContext.pack([intro, match], question: "拥塞控制")
        #expect(packed.map(\.detail) == ["0:01", "12:30"])

        let filler = ContextBlock(title: "其他", detail: "1", body: String(repeating: "无关内容。", count: 80), meetingID: UUID())
        let hit = ContextBlock(title: "网络", detail: "2", body: String(repeating: "拥塞控制。", count: 80), meetingID: UUID())
        let picked = ChatContext.pack([filler, hit], question: "拥塞控制", budget: 40)
        #expect(picked.count == 1)
        #expect(picked[0].title == "网络")
        #expect(picked[0].body.contains("拥"))
        #expect(picked[0].body.count <= 40)
    }

    @Test func aQuestionWithoutPassagesDoesNotAttachThem() {
        let prompt = ChatContext.userPrompt(question: "什么是注意力？", history: [], blocks: [])
        #expect(prompt == "Question: 什么是注意力？")
        #expect(!prompt.contains("passages"))
        let system = ChatContext.systemPrompt(language: "Simplified Chinese", allowsWeb: false, hasPassages: false)
        #expect(system.contains("You are Nomi"))
        #expect(system.contains("No meeting transcript"))
    }

    @Test func theSystemPromptStaysFixedAndDisabledSkillsStayOut() {
        let custom = "Answer only in haiku."
        let on = PromptSkill(name: "术语表", body: "Prefer the course glossary.", enabled: true)
        let off = PromptSkill(name: "忽略", body: "Do not use this.", enabled: false)
        let system = ChatContext.composedSystemPrompt(
            override: custom,
            language: "Simplified Chinese",
            allowsWeb: false,
            hasPassages: true,
            skills: [on, off]
        )
        #expect(!system.contains("Answer only in haiku."))
        #expect(system.contains("You are Nomi"))
        #expect(system.contains("Answer in Simplified Chinese."))
        #expect(system.contains("术语表"))
        #expect(system.contains("Prefer the course glossary."))
        #expect(!system.contains("Do not use this."))

        let untouched = ChatContext.composedSystemPrompt(
            override: ChatContext.defaultSystemText,
            language: "English",
            allowsWeb: false,
            hasPassages: false,
            skills: []
        )
        #expect(untouched.contains("You are Nomi"))
        #expect(untouched.contains("No meeting transcript"))
    }

    @Test func citationsKeepPassageNumbersAndWebLinks() {
        let block = ContextBlock(title: "计算机网络", detail: "12:30", body: "窗口", meetingID: UUID())
        let citations = ChatContext.citations(in: "见 [1]，以及 https://example.com/a.", blocks: [block])
        #expect(citations.count == 2)
        #expect(citations[0].meetingID == block.meetingID)
        #expect(citations[0].detail == "12:30")
        #expect(citations[0].passage == 1)
        #expect(citations[1].url == "https://example.com/a")
        #expect(citations[1].passage == nil)
    }

    @Test func plainTextFileBecomesABlock() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nomi-ask-\(UUID().uuidString).txt")
        try Data("拥塞控制\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let blocks = SourceText.blocks(url: url, title: "笔记", sourceID: UUID())
        #expect(blocks.count == 1)
        #expect(blocks[0].body.contains("拥塞控制"))
        #expect(blocks[0].title == "笔记")
    }

    private func item(_ name: String, _ category: UUID?, live: Bool = false) -> ScopeItem {
        ScopeItem(id: UUID(uuidString: stable(name))!, categoryID: category, live: live)
    }

    private func stable(_ name: String) -> String {
        switch name {
        case "m1": "00000000-0000-0000-0000-000000000001"
        case "m2": "00000000-0000-0000-0000-000000000002"
        case "m3": "00000000-0000-0000-0000-000000000003"
        case "live": "00000000-0000-0000-0000-000000000004"
        case "saved": "00000000-0000-0000-0000-000000000005"
        case "en": "00000000-0000-0000-0000-000000000006"
        case "math": "00000000-0000-0000-0000-000000000007"
        case "loose": "00000000-0000-0000-0000-000000000008"
        case "s1": "00000000-0000-0000-0000-000000000009"
        default: "00000000-0000-0000-0000-0000000000AA"
        }
    }
}
