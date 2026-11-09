import Foundation
import Testing
@testable import LectureNoteApp

/// Request bodies for each API style, the retry rules, and reading thinking and usage back.
struct AgentRequestTests {
    private func profile(_ base: String, format: LLMAPIFormat = .openAI, mode: LLMAPIMode = .chatCompletions) -> LLMAPIProfile {
        var value = LLMAPIProfile(name: "Test", baseURL: base, modelID: "model-x", format: format)
        value.apiMode = mode
        return value
    }

    private var request: LLMRequest {
        LLMRequest(
            system: "You are Nomi.",
            messages: [
                LLMMessage(role: .user, text: "Earlier question"),
                LLMMessage(role: .assistant, text: "Earlier answer", cacheMark: true),
                LLMMessage(role: .user, text: "Now?"),
            ],
            thinking: .low,
            cacheKey: "chat-1"
        )
    }

    @Test func newProfilesThinkAtLowAndOldOnesDecodeTheSame() throws {
        #expect(LLMAPIProfile().thinking == .low)
        let old = Data(#"{"name":"Old","baseURL":"https://x.test/v1","modelID":"m","format":"openAI"}"#.utf8)
        let decoded = try JSONDecoder().decode(LLMAPIProfile.self, from: old)
        #expect(decoded.thinking == .low)
        #expect(decoded.apiMode == .chatCompletions)
    }

    @Test func chatCompletionsSendsEarlierTurnsAsMessagesAndLowEffort() {
        let made = LLMRequestBody.make(profile: profile("https://relay.example/v1"), request: request, mode: .chatCompletions)
        #expect(made.path == "chat/completions")
        let messages = made.body["messages"] as? [[String: Any]] ?? []
        #expect(messages.map { $0["role"] as? String } == ["system", "user", "assistant", "user"])
        #expect(made.body["reasoning_effort"] as? String == "low")
        #expect((made.body["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true)
        #expect(made.body["prompt_cache_key"] == nil, "only OpenAI itself gets the cache key")
        let plain = LLMRequestBody.make(profile: profile("https://relay.example/v1"), request: request, mode: .chatCompletions,
                                        options: .init(thinking: false, extras: false))
        #expect(plain.body["reasoning_effort"] == nil)
        #expect(plain.body["stream_options"] == nil)
    }

    @Test func openAIGetsItsCacheKeyAndNoStorage() {
        let made = LLMRequestBody.make(profile: profile("https://api.openai.com/v1"), request: request, mode: .chatCompletions)
        #expect(made.body["prompt_cache_key"] as? String == "chat-1")
        #expect(made.body["store"] as? Bool == false)
    }

    @Test func responsesAsksForAReasoningSummary() {
        let made = LLMRequestBody.make(profile: profile("https://api.openai.com/v1", mode: .responses), request: request, mode: .responses)
        #expect(made.path == "responses")
        #expect(made.body["instructions"] as? String == "You are Nomi.")
        let reasoning = made.body["reasoning"] as? [String: Any]
        #expect(reasoning?["effort"] as? String == "low")
        #expect(reasoning?["summary"] as? String == "auto")
        let input = made.body["input"] as? [[String: Any]] ?? []
        #expect(input.map { $0["role"] as? String } == ["user", "assistant", "user"])
        let answer = (input[1]["content"] as? [[String: Any]])?.first
        #expect(answer?["type"] as? String == "output_text")
        #expect(made.body["store"] as? Bool == false)
    }

    @Test func anthropicNeverUsesResponsesAndMarksTheCache() {
        var claude = profile("https://api.anthropic.com/v1", format: .anthropic, mode: .responses)
        #expect(claude.effectiveAPIMode == .chatCompletions)
        claude.apiMode = .responses
        let made = LLMRequestBody.make(profile: claude, request: request, mode: claude.effectiveAPIMode)
        #expect(made.path == "messages")
        let thinking = made.body["thinking"] as? [String: Any]
        #expect(thinking?["budget_tokens"] as? Int == 2048)
        #expect(made.body["max_tokens"] as? Int == LLMRequestBody.answerTokens + 2048, "thinking never eats the answer's room")
        let system = made.body["system"] as? [[String: Any]]
        #expect((system?.first?["cache_control"] as? [String: Any])?["type"] as? String == "ephemeral")
        let messages = made.body["messages"] as? [[String: Any]] ?? []
        let marked = (messages[1]["content"] as? [[String: Any]])?.first?["cache_control"]
        #expect(marked != nil, "the last earlier turn is cached")
        #expect(messages[2]["content"] is String, "unmarked messages stay plain text")
    }

    @Test func refusedOptionsAndMissingResponsesAreRecognized() {
        #expect(LLMRequestBody.rejectsOption(status: 400, message: "Unsupported parameter: 'reasoning_effort' is not supported with this model."))
        #expect(LLMRequestBody.rejectsOption(status: 400, message: "Unrecognized request argument supplied: stream_options"))
        #expect(!LLMRequestBody.rejectsOption(status: 401, message: "Invalid API key"))
        #expect(!LLMRequestBody.rejectsOption(status: 400, message: "This model's maximum context length is 8192 tokens"))
        #expect(LLMRequestBody.lacksResponses(status: 404, message: ""))
        #expect(!LLMRequestBody.lacksResponses(status: 401, message: "bad key"))
    }

    @Test func aSettingTurnedDownIsRememberedPerModel() {
        var value = profile("https://relay.example/v1")
        value.noThinkingModels = ["model-x"]
        #expect(value.effectiveThinking == .off)
        value.modelID = "model-y"
        #expect(value.effectiveThinking == .low, "another model on the same service still thinks")
        value.apiMode = .responses
        value.responsesUnsupported = true
        #expect(value.effectiveAPIMode == .chatCompletions)
    }

    // MARK: Reading replies

    private func read(_ events: [String]) -> ChatStream.Accumulator {
        var accumulator = ChatStream.Accumulator()
        for event in events {
            if let object = ChatStream.object(from: event) { _ = accumulator.apply(object) }
        }
        return accumulator
    }

    @Test func thinkingIsReadFromEveryProvider() {
        let chat = read([
            #"{"choices":[{"delta":{"reasoning_content":"Count the pairs."}}]}"#,
            #"{"choices":[{"delta":{"content":"It is n squared."},"finish_reason":"stop"}]}"#,
            #"{"choices":[],"usage":{"prompt_tokens":1200,"completion_tokens":40,"prompt_tokens_details":{"cached_tokens":1024}}}"#,
        ])
        #expect(chat.thinking == "Count the pairs.")
        #expect(chat.answer == "It is n squared.")
        #expect(chat.usage == LLMUsage(input: 1200, cached: 1024, output: 40))

        let responses = read([
            #"{"type":"response.reasoning_summary_text.delta","delta":"Every token "}"#,
            #"{"type":"response.reasoning_summary_text.delta","delta":"meets every other."}"#,
            #"{"type":"response.output_text.delta","delta":"O(n²)."}"#,
            #"{"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":900,"output_tokens":12,"input_tokens_details":{"cached_tokens":768}}}}"#,
        ])
        #expect(responses.thinking == "Every token meets every other.")
        #expect(responses.answer == "O(n²).")
        #expect(responses.usage.cached == 768)

        let claude = read([
            #"{"type":"message_start","message":{"usage":{"input_tokens":50,"cache_read_input_tokens":3000}}}"#,
            #"{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"QKᵀ is n by n."}}"#,
            #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"Quadratic."}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":20}}"#,
        ])
        #expect(claude.thinking == "QKᵀ is n by n.")
        #expect(claude.usage == LLMUsage(input: 3050, cached: 3000, output: 20))

        let tagged = read([#"{"choices":[{"delta":{"content":"<think>Recall the formula.</think>Use the formula."}}]}"#])
        #expect(tagged.thinking == "Recall the formula.")
        #expect(tagged.display == "Use the formula.")
    }

    // MARK: Cache-friendly history

    private func turns(_ count: Int) -> [ChatTurn] {
        (0..<count).map { ChatTurn(question: "Q\($0)", answer: "A\($0)", modelName: "m", createdAt: Date(timeIntervalSince1970: Double($0) * 60)) }
    }

    @Test func earlierTurnsBecomeAlternatingMessagesWithTheLastMarked() {
        let window = ChatHistory.window(turns(3), budget: .api, dated: false)
        let messages = window.messages
        #expect(messages.map(\.role) == [.user, .assistant, .user, .assistant, .user, .assistant])
        #expect(messages.last?.cacheMark == true)
        #expect(messages.dropLast().allSatisfy { !$0.cacheMark })
        #expect(window.forMessages.text.isEmpty, "turns are not pasted into the prompt as well")
    }

    @Test func oldTurnsLeaveInBlocksSoFollowUpsShareTheirStart() {
        // A budget that holds about nine turns; the window slides as the chat grows.
        var budget = ContextBudget.api
        budget.history = 220
        func start(_ count: Int) -> String? {
            ChatHistory.window(turns(count), budget: budget, dated: false, stableStart: true).turns.first?.question
        }
        let starts = (10...16).map(start)
        // Each start is a multiple of four, and it changes at most twice across seven questions.
        #expect(starts.allSatisfy { ($0.flatMap { Int($0.dropFirst()) } ?? 0) % 4 == 0 })
        #expect(Set(starts.compactMap { $0 }).count <= 2)
        #expect(ChatHistory.window(turns(16), budget: budget, dated: false, stableStart: true).turns.last?.question == "Q15", "the newest turn is always there")
        var small = ContextBudget.api
        small.history = 90
        #expect(ChatHistory.window(turns(8), budget: small, dated: false, stableStart: true).turns.count >= 2, "a small window keeps its context")
    }

    @Test func aContinuationNumbersNewResultsAfterTheOldOnes() {
        let block = ContextBlock(title: "d2l.ai", detail: "", body: "Attention is quadratic.", url: "https://d2l.ai")
        let text = ChatContext.continuationPrompt(newBlocks: [block], startingAt: 4, webFinished: true, libraryFinished: false, draftEmpty: false, searchFailed: false)
        #expect(text.contains("[5] d2l.ai"))
        #expect(text.contains("Do not call web_search again."))
        #expect(text.contains("Continue the answer"))
    }

    @Test func theFoldedLineCountsWhatWasDone() {
        let start = Date(timeIntervalSince1970: 0)
        var files = AnswerStep(kind: .files, title: "", detail: "读取了 2 个文件", startedAt: start, endedAt: start.addingTimeInterval(1))
        files.count = 2
        let web = AnswerStep(kind: .web, title: "", detail: "找到 5 个网页", startedAt: start, endedAt: start.addingTimeInterval(2))
        let thought = AnswerStep(kind: .thinking, title: "", detail: "思考了 4 秒", startedAt: start, endedAt: start.addingTimeInterval(4))
        let line = AnswerStepSummary.line(steps: [files, web, thought], seconds: 14)
        #expect(line == [trf("用时 %d 秒", 14), trf("读了 %d 个文件", 2), trf("搜索 %d 次", 1), trf("思考了 %d 秒", 4)].joined(separator: " · "))
        let running = AnswerStep(kind: .web, title: "…", startedAt: start)
        #expect(AnswerStepSummary.kept([files, running]).count == 1, "a step still running is not saved")
    }

    @Test func savedStepsLeaveTheThinkingOut() throws {
        var step = AnswerStep(kind: .thinking, title: "", detail: "思考了 4 秒", startedAt: .now, endedAt: .now)
        step.thought = "private reasoning"
        let data = try JSONEncoder().encode(step)
        #expect(!String(decoding: data, as: UTF8.self).contains("private reasoning"))
        #expect(try JSONDecoder().decode(AnswerStep.self, from: data).detail == "思考了 4 秒")
    }
}
