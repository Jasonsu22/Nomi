// Engine/RequestLog.swift: one line per API request in logs/requests.jsonl. Never the question,
// the answer or the key.
import { fs, paths } from "../platform";
import type { LLMAPIProfile, LLMAPIMode } from "../models/llmConfiguration";
import { LLMRequestBody, type BodyOptions, type LLMRequest, type LLMUsage } from "./llmRequest";

export type LogEntry = { profile: LLMAPIProfile; request: LLMRequest; mode: LLMAPIMode; options: BodyOptions; started: number; firstToken: number | null; usage: LLMUsage; failure: string | null };

let queue = Promise.resolve();

export const RequestLog = {
  get file() {
    return paths.join(paths.root, "logs", "requests.jsonl");
  },
  line(e: LogEntry, now = Date.now()): Record<string, unknown> {
    const chars = [...e.request.system].length + e.request.messages.reduce((n, m) => n + [...m.text].length, 0);
    const line: Record<string, unknown> = {
      at: new Date(e.started).toISOString(),
      label: e.request.label,
      host: LLMRequestBody.host(e.profile),
      model: e.profile.modelID,
      api: e.profile.format === "anthropic" ? "messages" : e.mode,
      thinking: e.options.thinking ? e.request.thinking : "off",
      messages: e.request.messages.length,
      images: e.request.messages.reduce((n, m) => n + m.images.length, 0),
      chars,
      total_ms: Math.round(now - e.started),
    };
    if (e.firstToken) line.first_token_ms = Math.round(e.firstToken - e.started);
    if (e.usage.input !== undefined) line.input_tokens = e.usage.input;
    if (e.usage.cached !== undefined) line.cached_tokens = e.usage.cached;
    if (e.usage.output !== undefined) line.output_tokens = e.usage.output;
    if (e.failure) line.error = e.failure.slice(0, 200);
    return line;
  },
  record(e: LogEntry) {
    const text = JSON.stringify(this.line(e));
    queue = queue.then(async () => {
      const existing = (await fs.readText(this.file).catch(() => null)) ?? "";
      let next = existing + text + "\n";
      if (next.length > 1_000_000) {
        const half = next.slice(Math.floor(next.length / 2));
        next = half.slice(half.indexOf("\n") + 1);
      }
      await fs.writeText(this.file, next).catch(() => {});
    });
  },
};
