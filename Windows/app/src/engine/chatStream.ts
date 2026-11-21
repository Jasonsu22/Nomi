// Engine/ChatStream.swift: reads streamed replies from every API style.
import type { LLMUsage } from "./llmRequest";

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => !!v && typeof v === "object" && !Array.isArray(v);
const str = (v: unknown) => (typeof v === "string" ? v : undefined);
const num = (v: unknown) => (typeof v === "number" ? v : undefined);
const arr = (v: unknown): Obj[] => (Array.isArray(v) ? v.filter(isObj) : []);

export const ChatStream = {
  line(raw: string): { kind: "skip" } | { kind: "done" } | { kind: "payload"; payload: string } {
    const trimmed = raw.trim();
    if (!trimmed || trimmed.startsWith(":") || trimmed.startsWith("event:")) return { kind: "skip" };
    if (!trimmed.startsWith("data:")) return { kind: "skip" };
    const payload = trimmed.slice(5).trim();
    if (!payload) return { kind: "skip" };
    if (payload === "[DONE]") return { kind: "done" };
    return { kind: "payload", payload };
  },

  object(payload: string): Obj | null {
    try {
      const o = JSON.parse(payload);
      return isObj(o) ? o : null;
    } catch {
      return null;
    }
  },

  visible(raw: string): string {
    const end = raw.indexOf("</think>");
    if (end >= 0) return raw.slice(end + 8).trim();
    const t = raw.trim();
    if (t.startsWith("<think") || ["<", "<t", "<th", "<thi", "<thin"].includes(t)) return "";
    return raw;
  },

  messageText(message: Obj | undefined): string {
    if (!message) return "";
    const c = message.content;
    if (typeof c === "string" && c.trim()) return c;
    if (Array.isArray(c)) {
      const joined = arr(c).map((p) => str(p.text)).filter((x): x is string => x !== undefined).join("\n");
      if (joined.trim()) return joined;
    }
    const r = str(message.reasoning_content);
    if (r && r.trim()) return r;
    return str(message.refusal) ?? "";
  },
};

export class Accumulator {
  content = "";
  reasoning = "";
  links: string[] = [];
  finished = false;
  events = 0;
  finishReason: string | null = null;
  usage: LLMUsage = {};

  get thinking(): string {
    const parts: string[] = [];
    const own = this.reasoning.trim();
    if (own) parts.push(own);
    const start = this.content.indexOf("<think>");
    if (start >= 0) {
      const rest = this.content.slice(start + 7);
      const end = rest.indexOf("</think>");
      const text = (end >= 0 ? rest.slice(0, end) : rest).trim();
      if (text) parts.push(text);
    }
    return parts.join("\n\n");
  }

  get display(): string {
    const body = ChatStream.visible(this.content);
    if (body) return body;
    if (!this.finished) return "";
    const thought = this.reasoning.trim();
    if (thought) return thought;
    return this.content.trim();
  }

  get answer(): string {
    let text = this.display.trim();
    if (this.links.length) {
      if (text) text += "\n";
      text += this.links.join("\n");
    }
    return text;
  }

  apply(o: Obj): string | null {
    this.events++;
    this.noteFinishReason(o);
    if (o.type === undefined && isObj(o.usage)) this.noteUsage(o.usage);
    const failure = failureIn(o);
    if (failure) return failure;
    const kind = str(o.type);
    if (kind && this.applyKind(kind, o)) return null;
    if (this.applyLocal(o)) return null;
    if (this.applyChoice(o)) return null;
    if (this.applyAnthropic(o)) return null;
    this.applyResponses(o);
    return null;
  }

  private applyKind(kind: string, o: Obj): boolean {
    switch (kind) {
      case "content_block_delta": {
        const d = isObj(o.delta) ? o.delta : null;
        if (!d) return true;
        if (d.type === "text_delta" && typeof d.text === "string") this.content += d.text;
        else if (d.type === "thinking_delta" && typeof d.thinking === "string") this.reasoning += d.thinking;
        else if (d.type === "citations_delta") this.addLink(isObj(d.citation) ? d.citation : undefined);
        return true;
      }
      case "response.output_text.delta":
        if (typeof o.delta === "string") this.content += o.delta;
        return true;
      case "response.reasoning_summary_text.delta":
      case "response.reasoning_text.delta":
        if (typeof o.delta === "string") this.reasoning += o.delta;
        return true;
      case "response.reasoning_summary_part.added":
        if (this.reasoning) this.reasoning += "\n\n";
        return true;
      case "message_start":
        if (isObj(o.message) && isObj(o.message.usage)) this.noteUsage(o.message.usage);
        return true;
      case "message_delta":
        if (isObj(o.usage)) this.noteUsage(o.usage);
        return true;
      case "response.output_text.annotation.added":
        this.addLink(isObj(o.annotation) ? o.annotation : undefined);
        return true;
      case "message_stop":
        this.finished = true;
        return true;
      case "response.completed":
        if (isObj(o.response) && isObj(o.response.usage)) this.noteUsage(o.response.usage);
        this.finished = true;
        return true;
      case "error":
        return true;
      default:
        return false;
    }
  }

  private applyLocal(o: Obj): boolean {
    if (o.choices !== undefined || o.type !== undefined) return false;
    const done = o.done === true;
    if (!done && typeof o.text !== "string") return false;
    if (typeof o.text === "string" && (o.text || !done)) this.content = o.text;
    if (done) this.finished = true;
    return true;
  }

  private applyChoice(o: Obj): boolean {
    const choice = arr(o.choices)[0];
    if (!choice) return false;
    if (isObj(choice.delta)) {
      const d = choice.delta;
      if (typeof d.content === "string") this.content += d.content;
      if (typeof d.reasoning_content === "string") this.reasoning += d.reasoning_content;
      else if (typeof d.reasoning === "string") this.reasoning += d.reasoning;
      if (typeof choice.finish_reason === "string") this.finished = true;
      return true;
    }
    if (isObj(choice.message)) {
      this.content = ChatStream.messageText(choice.message);
      this.finished = true;
    }
    return true;
  }

  private applyAnthropic(o: Obj): boolean {
    if (o.choices !== undefined || !Array.isArray(o.content)) return false;
    const blocks = arr(o.content);
    const thoughts = blocks.filter((b) => b.type === "thinking").map((b) => str(b.thinking)).filter((x): x is string => !!x);
    if (thoughts.length) this.reasoning = thoughts.join("\n\n");
    if (isObj(o.usage)) this.noteUsage(o.usage);
    const textBlocks = blocks.filter((b) => b.type === "text");
    if (!textBlocks.length) return false;
    this.content = textBlocks.map((b) => str(b.text) ?? "").join("\n");
    for (const b of blocks) for (const c of arr(b.citations)) this.addLink(c);
    this.finished = true;
    return true;
  }

  private applyResponses(o: Obj): boolean {
    if (!Array.isArray(o.output)) return false;
    const output = arr(o.output);
    for (const item of output.filter((i) => i.type === "reasoning")) {
      const summary = arr(item.summary).map((s) => str(s.text)).filter((x): x is string => !!x);
      if (summary.length) this.reasoning = summary.join("\n\n");
    }
    if (isObj(o.usage)) this.noteUsage(o.usage);
    const parts: string[] = [];
    for (const item of output.filter((i) => i.type === "message")) {
      for (const block of arr(item.content)) {
        if (typeof block.text === "string") parts.push(block.text);
        for (const note of arr(block.annotations)) this.addLink(note);
      }
    }
    this.content = parts.join("\n");
    this.finished = true;
    return true;
  }

  private noteUsage(used: Obj) {
    const details = (isObj(used.prompt_tokens_details) ? used.prompt_tokens_details : isObj(used.input_tokens_details) ? used.input_tokens_details : undefined) as Obj | undefined;
    const input = num(used.prompt_tokens) ?? num(used.input_tokens);
    if (input !== undefined) this.usage.input = input + (num(used.cache_read_input_tokens) ?? 0) + (num(used.cache_creation_input_tokens) ?? 0);
    const cached = num(details?.cached_tokens) ?? num(used.prompt_cache_hit_tokens) ?? num(used.cache_read_input_tokens);
    if (cached !== undefined) this.usage.cached = cached;
    const output = num(used.completion_tokens) ?? num(used.output_tokens);
    if (output !== undefined) this.usage.output = output;
  }

  private noteFinishReason(o: Obj) {
    const choice = arr(o.choices)[0];
    if (choice && typeof choice.finish_reason === "string" && choice.finish_reason) this.finishReason = choice.finish_reason;
    else if (isObj(o.delta) && typeof o.delta.stop_reason === "string") this.finishReason = o.delta.stop_reason;
    else if (typeof o.stop_reason === "string") this.finishReason = o.stop_reason;
    else if (isObj(o.response) && typeof o.response.status === "string") this.finishReason = o.response.status;
    else if (o.output !== undefined && typeof o.status === "string") this.finishReason = o.status;
  }

  private addLink(note: Obj | undefined) {
    const url = str(note?.url);
    if (!url) return;
    const title = (str(note?.title) ?? "").trim();
    const line = title ? `${title} ${url}` : url;
    if (!this.links.includes(line)) this.links.push(line);
  }
}

export function failureIn(o: Obj): string | null {
  if (typeof o.error === "string" && o.error) return o.error;
  if (isObj(o.error) && typeof o.error.message === "string" && o.error.message) return o.error.message;
  if (o.type === "error" && typeof o.message === "string" && o.message) return o.message;
  return null;
}
