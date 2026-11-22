// Engine/LLMRequest.swift: what one request sends, and the JSON body for each API style.
import type { ModelImage } from "../models/chatImage";
import type { LLMAPIProfile, ThinkingLevel, LLMAPIMode } from "../models/llmConfiguration";
import { anthropicBudget } from "../models/llmConfiguration";

export type LLMMessage = { role: "user" | "assistant"; text: string; images: ModelImage[]; cacheMark?: boolean };

export type LLMRequest = { system: string; messages: LLMMessage[]; thinking: ThinkingLevel; cacheKey?: string | null; label: string };

export function singleRequest(system: string, prompt: string, images: ModelImage[] = [], label = "task"): LLMRequest {
  return { system, messages: [{ role: "user", text: prompt, images }], thinking: "off", label };
}

export type LLMUsage = { input?: number; cached?: number; output?: number };
export type LLMProgress = { answer: string; thinking: string };
export type LLMResult = { answer: string; thinking: string; usage: LLMUsage; thinkingRejected?: boolean; responsesRejected?: boolean };

export type BodyOptions = { thinking: boolean; extras: boolean };

const nonEmpty = (text: string) => (text.trim() ? text : "…");

export const LLMRequestBody = {
  answerTokens: 8192,

  make(profile: LLMAPIProfile, request: LLMRequest, mode: LLMAPIMode, options: BodyOptions = { thinking: true, extras: true }): { path: string; body: Record<string, unknown> } {
    const level: ThinkingLevel = options.thinking ? request.thinking : "off";
    if (profile.format === "anthropic") return { path: "messages", body: anthropic(profile, request, level) };
    if (mode === "responses") return { path: "responses", body: responses(profile, request, level, options.extras) };
    return { path: "chat/completions", body: chat(profile, request, level, options.extras) };
  },

  host(profile: LLMAPIProfile): string {
    try {
      return new URL(profile.baseURL).hostname.toLowerCase();
    } catch {
      return "";
    }
  },

  isOpenAI(profile: LLMAPIProfile) {
    return this.host(profile) === "api.openai.com";
  },

  isMiniMax(profile: LLMAPIProfile) {
    return this.host(profile).includes("minimax");
  },

  miniMaxOutputCeiling(modelID: string) {
    return modelID.toLowerCase().includes("m3") ? 524_288 : 204_800;
  },

  rejectsOption(status: number, message: string): boolean {
    if (![400, 422].includes(status)) return false;
    const text = message.toLowerCase();
    return ["reasoning", "thinking", "effort", "stream_options", "include_usage", "prompt_cache_key", "unsupported parameter", "unrecognized", "unknown parameter", "extra inputs", "extra_forbidden", "not supported", "additional properties", "unknown field", "invalid parameter"].some((t) => text.includes(t));
  },

  lacksResponses(status: number, message: string): boolean {
    if ([404, 405, 501].includes(status)) return true;
    const text = message.toLowerCase();
    return status === 400 && (text.includes("not found") || text.includes("no route") || text.includes("invalid url"));
  },
};

export function openAIContent(prompt: string, images: ModelImage[], miniMax: boolean): unknown {
  if (!images.length) return prompt;
  return [{ type: "text", text: prompt }, ...images.map((i) => ({ type: "image_url", image_url: { url: `data:${i.mime};base64,${i.base64}`, ...(miniMax ? { detail: "default" } : {}) } }))];
}

function anthropic(profile: LLMAPIProfile, request: LLMRequest, level: ThinkingLevel) {
  const body: Record<string, unknown> = {
    model: profile.modelID,
    max_tokens: LLMRequestBody.answerTokens + anthropicBudget(level),
    messages: request.messages.map(anthropicMessage),
    stream: true,
  };
  if (request.system.trim()) body.system = [{ type: "text", text: request.system, cache_control: { type: "ephemeral" } }];
  if (level !== "off") body.thinking = { type: "enabled", budget_tokens: anthropicBudget(level) };
  return body;
}

function anthropicMessage(m: LLMMessage) {
  const text = nonEmpty(m.text);
  if (!m.images.length && !m.cacheMark) return { role: m.role, content: text };
  const block: Record<string, unknown> = { type: "text", text };
  if (m.cacheMark) block.cache_control = { type: "ephemeral" };
  return { role: m.role, content: [block, ...m.images.map((i) => ({ type: "image", source: { type: "base64", media_type: i.mime, data: i.base64 } }))] };
}

function chat(profile: LLMAPIProfile, request: LLMRequest, level: ThinkingLevel, extras: boolean) {
  const miniMax = LLMRequestBody.isMiniMax(profile);
  const messages: unknown[] = [{ role: "system", content: request.system }];
  for (const m of request.messages) messages.push({ role: m.role, content: m.role === "user" ? openAIContent(m.text, m.images, miniMax) : nonEmpty(m.text) });
  const body: Record<string, unknown> = { model: profile.modelID, messages, stream: true };
  if (level !== "off") body.reasoning_effort = level;
  if (extras) body.stream_options = { include_usage: true };
  if (LLMRequestBody.isOpenAI(profile)) {
    body.store = false;
    if (extras && request.cacheKey) body.prompt_cache_key = request.cacheKey;
  } else if (miniMax) {
    body.max_completion_tokens = LLMRequestBody.miniMaxOutputCeiling(profile.modelID);
  }
  return body;
}

function responses(profile: LLMAPIProfile, request: LLMRequest, level: ThinkingLevel, extras: boolean) {
  const input = request.messages.map((m) =>
    m.role === "assistant"
      ? { role: "assistant", content: [{ type: "output_text", text: nonEmpty(m.text) }] }
      : { role: "user", content: [{ type: "input_text", text: m.text }, ...m.images.map((i) => ({ type: "input_image", image_url: `data:${i.mime};base64,${i.base64}` }))] },
  );
  const body: Record<string, unknown> = { model: profile.modelID, instructions: request.system, input, stream: true, store: false };
  if (level !== "off") body.reasoning = { effort: level, summary: "auto" };
  if (extras && LLMRequestBody.isOpenAI(profile) && request.cacheKey) body.prompt_cache_key = request.cacheKey;
  return body;
}
