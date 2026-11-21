// Engine/RemoteLLMClient.swift: API models, streamed, with the same retries as the Mac:
// one more try for an empty reply, Chat Completions when Responses is missing, and the request
// again without thinking or extras when a service refuses them.
import { fetch } from "@tauri-apps/plugin-http";
import { tr, trf } from "../i18n";
import { Profiles, type LLMAPIMode, type LLMAPIProfile } from "../models/llmConfiguration";
import type { ModelImage } from "../models/chatImage";
import { Accumulator, ChatStream, failureIn } from "./chatStream";
import { LLMRequestBody, singleRequest, type BodyOptions, type LLMProgress, type LLMRequest, type LLMResult } from "./llmRequest";
import { RequestLog } from "./requestLog";

export class EmptyReply extends Error {
  constructor(public status: number, public events: number, public finishReason: string | null, public retried = false) {
    super("");
    this.message = this.describe();
  }
  describe() {
    let detail = trf("HTTP %d · %d 个事件 · 结束原因：%@", this.status, this.events, this.finishReason ?? "none");
    if (this.retried) detail += " · " + tr("已自动重试一次");
    return tr("模型未返回文字，请检查所选模型和接口格式。") + ` (${detail})`;
  }
}

export class HTTPFailure extends Error {
  constructor(public status: number, public detail: string) {
    super(trf("API 请求失败（HTTP %d）：%@", status, detail.slice(0, 400)));
  }
}

export class Cancelled extends Error {
  constructor() {
    super("cancelled");
  }
}

const redacted = (message: string, key: string) => (key ? message.split(key).join("••••") : message);

function headers(profile: LLMAPIProfile, key: string, json: boolean): Record<string, string> {
  const h: Record<string, string> = {};
  if (json) h["Content-Type"] = "application/json";
  if (profile.format === "anthropic") {
    h["x-api-key"] = key;
    h["anthropic-version"] = "2023-06-01";
  } else if (key) h.Authorization = `Bearer ${key}`;
  return h;
}

function serviceFailure(o: Record<string, unknown>): string | null {
  const e = o.error;
  if (e && typeof e === "object" && typeof (e as Record<string, unknown>).message === "string" && (e as Record<string, unknown>).message) return (e as Record<string, string>).message;
  if (typeof e === "string" && e) return e;
  const base = o.base_resp as Record<string, unknown> | undefined;
  if (base && typeof base === "object") {
    const status = Number(base.status_code ?? 0);
    if (status !== 0) return String(base.status_msg || status);
  }
  if (typeof o.message === "string" && o.message && o.choices === undefined && o.data === undefined) return o.message;
  return null;
}

export const RemoteLLM = {
  async models(profile0: LLMAPIProfile, key: string): Promise<string[]> {
    const profile = Profiles.validated(profile0, false);
    const result = new Set<string>();
    let lastID: string | null = null;
    const seen = new Set<string>();
    for (let page = 0; page < 50; page++) {
      let url = profile.baseURL.replace(/\/+$/, "") + "/models";
      if (profile.format === "anthropic") url += `?limit=100${lastID ? `&after_id=${encodeURIComponent(lastID)}` : ""}`;
      const response = await fetch(url, { method: "GET", headers: headers(profile, key, false) });
      const text = await response.text();
      let o: Record<string, unknown>;
      try {
        o = JSON.parse(text);
      } catch {
        throw new Error(redacted(trf("API 请求失败（HTTP %d）：%@", response.status, text.slice(0, 400)), key));
      }
      const failure = serviceFailure(o);
      if (failure) throw new Error(redacted(trf("API 请求失败（HTTP %d）：%@", response.status, failure.slice(0, 400)), key));
      if (!response.ok) throw new Error(redacted(trf("API 请求失败（HTTP %d）：%@", response.status, ""), key));
      if (!Array.isArray(o.data)) throw new Error(tr("服务未返回模型列表，可以手动填写模型 ID。"));
      for (const m of o.data as Record<string, unknown>[]) if (typeof m.id === "string") result.add(m.id);
      const next = typeof o.last_id === "string" ? o.last_id : null;
      if (profile.format !== "anthropic" || o.has_more !== true || !next || seen.has(next)) break;
      seen.add(next);
      lastID = next;
    }
    return [...result].sort();
  },

  async generate(profile: LLMAPIProfile, key: string, system: string, prompt: string, images: ModelImage[] = [], onUpdate?: (text: string) => void, signal?: AbortSignal): Promise<string> {
    const result = await this.stream(profile, key, singleRequest(system, prompt, images), (p) => {
      if (p.answer) onUpdate?.(p.answer);
    }, signal);
    return result.answer;
  },

  async stream(profile: LLMAPIProfile, key: string, request: LLMRequest, onProgress: (p: LLMProgress) => void, signal?: AbortSignal): Promise<LLMResult> {
    const options: BodyOptions = { thinking: true, extras: true };
    let mode: LLMAPIMode = Profiles.effectiveAPIMode(profile);
    let responsesRejected = false;
    let emptyRetried = false;
    const started = Date.now();
    let first: number | null = null;
    const watched = (p: LLMProgress) => {
      first = first ?? Date.now();
      onProgress(p);
    };
    let lastError: Error | null = null;
    for (let attempt = 0; attempt < 5; attempt++) {
      try {
        const result = await send(profile, key, request, mode, options, watched, signal);
        result.responsesRejected = responsesRejected;
        result.thinkingRejected = request.thinking !== "off" && !options.thinking;
        RequestLog.record({ profile, request, mode, options, started, firstToken: first, usage: result.usage, failure: null });
        return result;
      } catch (error) {
        if (signal?.aborted) throw new Cancelled();
        if (error instanceof HTTPFailure && mode === "responses" && LLMRequestBody.lacksResponses(error.status, error.detail)) {
          mode = "chatCompletions";
          responsesRejected = true;
          lastError = error;
        } else if (error instanceof HTTPFailure && LLMRequestBody.rejectsOption(error.status, error.detail) && (options.thinking || options.extras)) {
          const text = error.detail.toLowerCase();
          const aboutThinking = ["reasoning", "thinking", "effort"].some((t) => text.includes(t));
          if (options.thinking && request.thinking !== "off" && (aboutThinking || !options.extras)) options.thinking = false;
          else if (options.extras) options.extras = false;
          else options.thinking = false;
          lastError = error;
        } else if (error instanceof EmptyReply) {
          if (emptyRetried) {
            error.retried = true;
            error.message = error.describe();
            lastError = error;
            break;
          }
          emptyRetried = true;
          lastError = error;
        } else {
          lastError = error instanceof Error ? error : new Error(String(error));
          break;
        }
      }
    }
    const error = lastError ?? new Error(tr("模型未返回文字，请检查所选模型和接口格式。"));
    RequestLog.record({ profile, request, mode, options, started, firstToken: first, usage: {}, failure: error.message });
    throw error;
  },
};

async function send(profile0: LLMAPIProfile, key: string, request: LLMRequest, mode: LLMAPIMode, options: BodyOptions, onProgress: (p: LLMProgress) => void, signal?: AbortSignal): Promise<LLMResult> {
  const profile = Profiles.validated(profile0);
  const made = LLMRequestBody.make(profile, request, mode, options);
  const url = profile.baseURL.replace(/\/+$/, "") + "/" + made.path;
  const response = await fetch(url, { method: "POST", headers: headers(profile, key, true), body: JSON.stringify(made.body), signal, connectTimeout: 60_000 });
  const type = (response.headers.get("content-type") ?? "").toLowerCase();
  if (!response.ok || (type.includes("json") && !type.includes("event-stream"))) {
    const text = await response.text();
    if (!response.ok) throw failureOf(text, response.status, key);
    return complete(text, response.status, key, onProgress);
  }
  return events(response, key, options.extras, onProgress, signal);
}

function failureOf(text: string, status: number, key: string): Error {
  try {
    const o = JSON.parse(text);
    const message = o && typeof o === "object" ? serviceFailure(o) : null;
    if (message) return new HTTPFailure(status, redacted(message, key));
  } catch {
    /* not JSON */
  }
  return new HTTPFailure(status, redacted(text.slice(0, 2000), key));
}

function complete(text: string, status: number, key: string, onProgress: (p: LLMProgress) => void): LLMResult {
  let o: Record<string, unknown>;
  try {
    o = JSON.parse(text);
  } catch {
    throw failureOf(text, 200, key);
  }
  const failure = serviceFailure(o);
  if (failure) throw new HTTPFailure(200, redacted(failure, key));
  const acc = new Accumulator();
  const message = acc.apply(o);
  if (message) throw new Error(redacted(message, key));
  acc.finished = true;
  const answer = acc.answer;
  if (!answer) throw new EmptyReply(status, acc.events, acc.finishReason);
  onProgress({ answer, thinking: acc.thinking });
  return { answer, thinking: acc.thinking, usage: acc.usage };
}

async function events(response: Response, key: string, waitsForUsage: boolean, onProgress: (p: LLMProgress) => void, signal?: AbortSignal): Promise<LLMResult> {
  const reader = response.body?.getReader();
  if (!reader) throw new EmptyReply(response.status, 0, null);
  const decoder = new TextDecoder();
  let buffer = "";
  const acc = new Accumulator();
  let last = 0;
  let shown = { answer: "", thinking: "" };
  let linesAfterFinish = 0;
  let firstLine = true;
  let rawJSON: string | null = null;
  outer: while (true) {
    if (signal?.aborted) {
      await reader.cancel().catch(() => {});
      throw new Cancelled();
    }
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    let newline: number;
    while ((newline = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, newline).replace(/\r$/, "");
      buffer = buffer.slice(newline + 1);
      if (rawJSON !== null) {
        rawJSON += "\n" + line;
        continue;
      }
      const trimmed = line.trim();
      if (!trimmed) continue;
      if (firstLine && (trimmed.startsWith("{") || trimmed.startsWith("["))) {
        rawJSON = line;
        continue;
      }
      firstLine = false;
      const parsed = ChatStream.line(line);
      let finishedNow = false;
      if (parsed.kind === "skip") continue;
      if (parsed.kind === "done") {
        acc.finished = true;
        finishedNow = true;
      } else {
        const o = ChatStream.object(parsed.payload);
        if (!o) continue;
        const message = acc.apply(o) ?? failureIn(o);
        if (message) throw new Error(redacted(message, key));
      }
      const progress = { answer: acc.display, thinking: acc.thinking };
      const now = performance.now();
      if ((progress.answer !== shown.answer || progress.thinking !== shown.thinking) && (progress.answer || progress.thinking) && now - last >= 50) {
        last = now;
        shown = progress;
        onProgress(progress);
      }
      if (finishedNow) break outer;
      if (acc.finished) {
        linesAfterFinish++;
        if (!waitsForUsage || acc.usage.input !== undefined || linesAfterFinish > 3) break outer;
      }
    }
  }
  await reader.cancel().catch(() => {});
  if (rawJSON !== null) return complete(rawJSON + buffer, response.status, key, onProgress);
  acc.finished = true;
  const answer = acc.answer;
  if (!answer) throw new EmptyReply(response.status, acc.events, acc.finishReason);
  if (answer !== shown.answer || acc.thinking !== shown.thinking) onProgress({ answer, thinking: acc.thinking });
  return { answer, thinking: acc.thinking, usage: acc.usage };
}
