import Foundation

/// One message of a conversation sent to an API model.
struct LLMMessage: Equatable, Sendable {
    enum Role: String, Sendable { case user, assistant }

    var role: Role
    var text: String
    var images: [ModelImage] = []
    /// Anthropic caches everything up to and including a marked message. At most three are marked,
    /// because the system prompt takes the fourth of Anthropic's four marks.
    var cacheMark = false
}

/// What one answer round sends. Earlier turns are their own messages, so a follow-up question
/// starts with the same bytes as the request before it and the service can reuse its cache.
struct LLMRequest: Equatable, Sendable {
    var system: String
    var messages: [LLMMessage]
    var thinking: ThinkingLevel = .off
    /// Keeps one chat's requests on the same OpenAI cache.
    var cacheKey: String?
    /// Which step of an answer this is, for the request log.
    var label = "chat"

    /// Only the system prompt and one question, for summaries, demos and other single-shot tasks.
    static func single(system: String, prompt: String, images: [ModelImage] = [], label: String = "task") -> LLMRequest {
        LLMRequest(system: system, messages: [LLMMessage(role: .user, text: prompt, images: images)], label: label)
    }
}

/// Tokens a request used, as the service reports them.
struct LLMUsage: Equatable, Sendable {
    var input: Int?
    var cached: Int?
    var output: Int?
}

/// The reply so far: the visible answer and the model's thinking.
struct LLMProgress: Equatable, Sendable {
    var answer = ""
    var thinking = ""
}

struct LLMResult: Equatable, Sendable {
    var answer: String
    var thinking: String
    var usage: LLMUsage
    /// The service did not accept the thinking parameter, so the answer came without it.
    var thinkingRejected = false
    /// The service has no Responses endpoint, so the answer came from Chat Completions.
    var responsesRejected = false
}

/// The JSON body for each API style. Pure, so every provider's request can be tested.
enum LLMRequestBody {
    /// `thinking` and `extras` (usage reports, the cache key) are dropped on a retry when a service rejects them.
    struct Options: Equatable {
        var thinking = true
        var extras = true
    }

    static let answerTokens = 8192

    static func make(profile: LLMAPIProfile, request: LLMRequest, mode: LLMAPIMode, options: Options = .init()) -> (path: String, body: [String: Any]) {
        let level = options.thinking ? request.thinking : .off
        if profile.format == .anthropic {
            return ("messages", anthropic(profile: profile, request: request, level: level))
        }
        if mode == .responses {
            return ("responses", responses(profile: profile, request: request, level: level, extras: options.extras))
        }
        return ("chat/completions", chat(profile: profile, request: request, level: level, extras: options.extras))
    }

    // MARK: Anthropic Messages

    private static func anthropic(profile: LLMAPIProfile, request: LLMRequest, level: ThinkingLevel) -> [String: Any] {
        var body: [String: Any] = [
            "model": profile.modelID,
            "max_tokens": answerTokens + level.anthropicBudget,
            "messages": request.messages.map(anthropicMessage),
            "stream": true,
        ]
        let system = request.system.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            body["system"] = [["type": "text", "text": request.system, "cache_control": ["type": "ephemeral"]]]
        }
        if level != .off {
            body["thinking"] = ["type": "enabled", "budget_tokens": level.anthropicBudget]
        }
        return body
    }

    private static func anthropicMessage(_ message: LLMMessage) -> [String: Any] {
        let text = nonEmpty(message.text)
        guard !message.images.isEmpty || message.cacheMark else {
            return ["role": message.role.rawValue, "content": text]
        }
        var block: [String: Any] = ["type": "text", "text": text]
        if message.cacheMark { block["cache_control"] = ["type": "ephemeral"] }
        var parts: [[String: Any]] = [block]
        for image in message.images {
            parts.append(["type": "image", "source": ["type": "base64", "media_type": image.mime, "data": image.base64]])
        }
        return ["role": message.role.rawValue, "content": parts]
    }

    // MARK: OpenAI Chat Completions

    private static func chat(profile: LLMAPIProfile, request: LLMRequest, level: ThinkingLevel, extras: Bool) -> [String: Any] {
        var messages: [[String: Any]] = [["role": "system", "content": request.system]]
        let miniMax = isMiniMax(profile)
        for message in request.messages {
            let content: Any = message.role == .user
                ? RemoteLLMClient.openAIContent(prompt: message.text, images: message.images, miniMax: miniMax)
                : nonEmpty(message.text)
            messages.append(["role": message.role.rawValue, "content": content])
        }
        var body: [String: Any] = ["model": profile.modelID, "messages": messages, "stream": true]
        if level != .off { body["reasoning_effort"] = level.rawValue }
        if extras { body["stream_options"] = ["include_usage": true] }
        if isOpenAI(profile) {
            body["store"] = false
            if extras, let key = request.cacheKey { body["prompt_cache_key"] = key }
        } else if miniMax {
            // Omitting this uses a short server default and cuts the reply off. The value is that API's own maximum, so the model stops when it is finished.
            body["max_completion_tokens"] = miniMaxOutputCeiling(profile.modelID)
        }
        return body
    }

    // MARK: OpenAI Responses

    private static func responses(profile: LLMAPIProfile, request: LLMRequest, level: ThinkingLevel, extras: Bool) -> [String: Any] {
        let input: [[String: Any]] = request.messages.map { message in
            if message.role == .assistant {
                return ["role": "assistant", "content": [["type": "output_text", "text": nonEmpty(message.text)]]]
            }
            var parts: [[String: Any]] = [["type": "input_text", "text": message.text]]
            for image in message.images {
                parts.append(["type": "input_image", "image_url": "data:\(image.mime);base64,\(image.base64)"])
            }
            return ["role": "user", "content": parts]
        }
        var body: [String: Any] = [
            "model": profile.modelID,
            "instructions": request.system,
            "input": input,
            "stream": true,
            "store": false,
        ]
        if level != .off { body["reasoning"] = ["effort": level.rawValue, "summary": "auto"] }
        if extras, isOpenAI(profile), let key = request.cacheKey { body["prompt_cache_key"] = key }
        return body
    }

    // MARK: Helpers

    /// Services reject empty message text.
    private static func nonEmpty(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "…" : text
    }

    static func host(of profile: LLMAPIProfile) -> String {
        URL(string: profile.baseURL)?.host?.lowercased() ?? ""
    }

    static func isOpenAI(_ profile: LLMAPIProfile) -> Bool { host(of: profile) == "api.openai.com" }

    static func isMiniMax(_ profile: LLMAPIProfile) -> Bool { host(of: profile).contains("minimax") }

    /// MiniMax stops a reply at this budget. M3 can use 512K; other models on that API can use 200K.
    static func miniMaxOutputCeiling(_ modelID: String) -> Int {
        modelID.lowercased().contains("m3") ? 524_288 : 204_800
    }

    /// A 400-style refusal of an optional parameter: thinking, usage reports or the cache key.
    /// Nomi then asks once more without them instead of showing the student an error.
    static func rejectsOption(status: Int, message: String) -> Bool {
        guard [400, 422].contains(status) else { return false }
        let text = message.lowercased()
        return ["reasoning", "thinking", "effort", "stream_options", "include_usage", "prompt_cache_key",
                "unsupported parameter", "unrecognized", "unknown parameter", "extra inputs", "extra_forbidden",
                "not supported", "additional properties", "unknown field", "invalid parameter"].contains { text.contains($0) }
    }

    /// The service has no Responses endpoint.
    static func lacksResponses(status: Int, message: String) -> Bool {
        if [404, 405, 501].contains(status) { return true }
        let text = message.lowercased()
        return status == 400 && (text.contains("not found") || text.contains("no route") || text.contains("invalid url"))
    }
}
