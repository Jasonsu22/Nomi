import Foundation

enum ChatStream {
    enum Line: Equatable {
        case skip
        case done
        case payload(String)
    }

    static func line(_ raw: String) -> Line {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix(":") || trimmed.hasPrefix("event:") { return .skip }
        guard trimmed.hasPrefix("data:") else { return .skip }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload.isEmpty { return .skip }
        if payload == "[DONE]" { return .done }
        return .payload(String(payload))
    }

    static func object(from payload: String) -> [String: Any]? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    /// Hides an unclosed think block. The answer after `</think>` is what the user sees.
    static func visible(_ raw: String) -> String {
        if let range = raw.range(of: "</think>") {
            return String(raw[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<think") || trimmed == "<" || trimmed == "<t" || trimmed == "<th" || trimmed == "<thi" || trimmed == "<thin" {
            return ""
        }
        return raw
    }

    struct Accumulator {
        var content = ""
        var reasoning = ""
        var links: [String] = []
        var finished = false
        /// Parsed events and the last stop reason, reported when a reply comes back empty.
        var events = 0
        var finishReason: String?
        var usage = LLMUsage()

        /// What the model thought before answering: `reasoning_content`, a Responses reasoning
        /// summary, Anthropic thinking, or a `<think>` block at the start of the text.
        var thinking: String {
            var parts: [String] = []
            let own = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
            if !own.isEmpty { parts.append(own) }
            if let start = content.range(of: "<think>") {
                let rest = content[start.upperBound...]
                let inner = rest.range(of: "</think>").map { rest[..<$0.lowerBound] } ?? rest
                let text = inner.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { parts.append(text) }
            }
            return parts.joined(separator: "\n\n")
        }

        var display: String {
            let body = ChatStream.visible(content)
            if !body.isEmpty { return body }
            guard finished else { return "" }
            let thought = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
            if !thought.isEmpty { return thought }
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var answer: String {
            var text = display.trimmingCharacters(in: .whitespacesAndNewlines)
            if !links.isEmpty {
                if !text.isEmpty { text += "\n" }
                text += links.joined(separator: "\n")
            }
            return text
        }

        mutating func apply(_ object: [String: Any]) -> String? {
            events += 1
            noteFinishReason(object)
            if object["type"] == nil, let used = object["usage"] as? [String: Any] { noteUsage(used) }
            if let message = Self.failure(in: object) { return message }
            if let kind = object["type"] as? String, apply(kind: kind, object: object) { return nil }
            if applyLocal(object) { return nil }
            if applyChoice(object) { return nil }
            if applyAnthropic(object) { return nil }
            if applyResponses(object) { return nil }
            return nil
        }

        private static func failure(in object: [String: Any]) -> String? {
            if let error = object["error"] as? String, !error.isEmpty { return error }
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
                return message
            }
            if object["type"] as? String == "error", let message = object["message"] as? String, !message.isEmpty {
                return message
            }
            return nil
        }

        private mutating func apply(kind: String, object: [String: Any]) -> Bool {
            switch kind {
            case "content_block_delta":
                guard let delta = object["delta"] as? [String: Any] else { return true }
                if delta["type"] as? String == "text_delta", let text = delta["text"] as? String {
                    content += text
                } else if delta["type"] as? String == "thinking_delta", let text = delta["thinking"] as? String {
                    reasoning += text
                } else if delta["type"] as? String == "citations_delta" {
                    addLink(delta["citation"] as? [String: Any])
                }
                return true
            case "response.output_text.delta":
                if let text = object["delta"] as? String { content += text }
                return true
            case "response.reasoning_summary_text.delta", "response.reasoning_text.delta":
                if let text = object["delta"] as? String { reasoning += text }
                return true
            case "response.reasoning_summary_part.added":
                if !reasoning.isEmpty { reasoning += "\n\n" }
                return true
            case "message_start":
                if let used = (object["message"] as? [String: Any])?["usage"] as? [String: Any] { noteUsage(used) }
                return true
            case "message_delta":
                if let used = object["usage"] as? [String: Any] { noteUsage(used) }
                return true
            case "response.output_text.annotation.added":
                addLink(object["annotation"] as? [String: Any])
                return true
            case "message_stop":
                finished = true
                return true
            case "response.completed":
                if let used = (object["response"] as? [String: Any])?["usage"] as? [String: Any] { noteUsage(used) }
                finished = true
                return true
            case "error":
                return true
            default:
                return false
            }
        }

        private mutating func applyLocal(_ object: [String: Any]) -> Bool {
            guard object["choices"] == nil, object["type"] == nil else { return false }
            let done = object["done"] as? Bool == true
            guard done || object["text"] is String else { return false }
            if let text = object["text"] as? String, !text.isEmpty || !done {
                content = text
            }
            if done { finished = true }
            return true
        }

        private mutating func applyChoice(_ object: [String: Any]) -> Bool {
            guard let choice = (object["choices"] as? [[String: Any]])?.first else { return false }
            if let delta = choice["delta"] as? [String: Any] {
                if let text = delta["content"] as? String { content += text }
                if let text = delta["reasoning_content"] as? String { reasoning += text }
                else if let text = delta["reasoning"] as? String { reasoning += text }
                if choice["finish_reason"] is String { finished = true }
                return true
            }
            if let message = choice["message"] as? [String: Any] {
                content = ChatStream.messageText(message)
                finished = true
                return true
            }
            return true
        }

        private mutating func applyAnthropic(_ object: [String: Any]) -> Bool {
            guard object["choices"] == nil, let blocks = object["content"] as? [[String: Any]] else { return false }
            let thoughts = blocks.filter { $0["type"] as? String == "thinking" }.compactMap { $0["thinking"] as? String }
            if !thoughts.isEmpty { reasoning = thoughts.joined(separator: "\n\n") }
            if let used = object["usage"] as? [String: Any] { noteUsage(used) }
            let texts = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
            guard !texts.isEmpty || blocks.contains(where: { ($0["type"] as? String) == "text" }) else { return false }
            content = texts.joined(separator: "\n")
            for block in blocks {
                for cite in block["citations"] as? [[String: Any]] ?? [] { addLink(cite) }
            }
            finished = true
            return true
        }

        private mutating func applyResponses(_ object: [String: Any]) -> Bool {
            guard let output = object["output"] as? [[String: Any]] else { return false }
            var parts: [String] = []
            for item in output where item["type"] as? String == "reasoning" {
                let summary = (item["summary"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
                if !summary.isEmpty { reasoning = summary.joined(separator: "\n\n") }
            }
            if let used = object["usage"] as? [String: Any] { noteUsage(used) }
            for item in output where item["type"] as? String == "message" {
                for block in item["content"] as? [[String: Any]] ?? [] {
                    if let text = block["text"] as? String { parts.append(text) }
                    for note in block["annotations"] as? [[String: Any]] ?? [] { addLink(note) }
                }
            }
            content = parts.joined(separator: "\n")
            finished = true
            return true
        }

        /// Token counts in any of the services' shapes. Later reports fill in what earlier ones lacked.
        private mutating func noteUsage(_ used: [String: Any]) {
            func int(_ value: Any?) -> Int? { (value as? Int) ?? (value as? NSNumber)?.intValue }
            let details = (used["prompt_tokens_details"] ?? used["input_tokens_details"]) as? [String: Any]
            if let input = int(used["prompt_tokens"]) ?? int(used["input_tokens"]) {
                // Anthropic counts cached input apart from `input_tokens`.
                let anthropicCached = int(used["cache_read_input_tokens"]) ?? 0
                let created = int(used["cache_creation_input_tokens"]) ?? 0
                usage.input = input + anthropicCached + created
            }
            if let cached = int(details?["cached_tokens"]) ?? int(used["prompt_cache_hit_tokens"]) ?? int(used["cache_read_input_tokens"]) {
                usage.cached = cached
            }
            if let output = int(used["completion_tokens"]) ?? int(used["output_tokens"]) { usage.output = output }
        }

        /// Chat Completions `finish_reason`, Anthropic `stop_reason`, or a Responses `status`.
        private mutating func noteFinishReason(_ object: [String: Any]) {
            if let choice = (object["choices"] as? [[String: Any]])?.first,
               let reason = choice["finish_reason"] as? String, !reason.isEmpty {
                finishReason = reason
            } else if let reason = (object["delta"] as? [String: Any])?["stop_reason"] as? String {
                finishReason = reason
            } else if let reason = object["stop_reason"] as? String {
                finishReason = reason
            } else if let response = object["response"] as? [String: Any], let status = response["status"] as? String {
                finishReason = status
            } else if object["output"] != nil, let status = object["status"] as? String {
                finishReason = status
            }
        }

        private mutating func addLink(_ note: [String: Any]?) {
            guard let url = note?["url"] as? String, !url.isEmpty else { return }
            let title = (note?["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let line = title.isEmpty ? url : "\(title) \(url)"
            guard !links.contains(line) else { return }
            links.append(line)
        }
    }

    static func messageText(_ message: [String: Any]?) -> String {
        guard let message else { return "" }
        if let content = message["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return content
        }
        if let parts = message["content"] as? [[String: Any]] {
            let joined = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return joined }
        }
        if let reasoning = message["reasoning_content"] as? String,
           !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return reasoning
        }
        return message["refusal"] as? String ?? ""
    }
}
