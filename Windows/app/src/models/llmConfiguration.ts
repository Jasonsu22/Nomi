// Models/LLMConfiguration.swift: API profiles and which model answers. Keys live in Windows
// Credential Manager (the Mac keeps them in a private file).
import { tr } from "../i18n";
import { newID } from "../support/format";
import { prefs } from "../support/prefs";
import { secrets } from "../platform";

export type LLMMode = "local" | "api";
export type LLMAPIFormat = "openAI" | "anthropic";
export type LLMAPIMode = "chatCompletions" | "responses";
export type ThinkingLevel = "off" | "low" | "medium" | "high";

export const modeTitle = (m: LLMMode) => (m === "local" ? tr("本地模型") : "API");
export const formatTitle = (f: LLMAPIFormat) => (f === "openAI" ? tr("OpenAI 兼容") : "Anthropic Messages");
export const apiModeTitle = (m: LLMAPIMode) => (m === "chatCompletions" ? "Chat Completions" : "Responses");
export const thinkingTitle = (t: ThinkingLevel) => ({ off: tr("关"), low: tr("低"), medium: tr("中"), high: tr("高") })[t];
export const anthropicBudget = (t: ThinkingLevel) => ({ off: 0, low: 2048, medium: 8000, high: 16000 })[t];

export type LLMAPIProfile = {
  id: string;
  providerID: string;
  name: string;
  baseURL: string;
  modelID: string;
  format: LLMAPIFormat;
  savedModelIDs: string[];
  contextCharacters?: number | null;
  apiMode: LLMAPIMode;
  thinking: ThinkingLevel;
  responsesUnsupported?: boolean;
  noThinkingModels?: string[];
};

export function newProfile(extra: Partial<LLMAPIProfile> = {}): LLMAPIProfile {
  return { id: newID(), providerID: "custom", name: "", baseURL: "", modelID: "", format: "openAI", savedModelIDs: [], apiMode: "chatCompletions", thinking: "low", ...extra };
}

export const Profiles = {
  decode(raw: Partial<LLMAPIProfile>): LLMAPIProfile {
    return newProfile({ ...raw, id: raw.id ?? newID(), noThinkingModels: raw.noThinkingModels ?? [], responsesUnsupported: raw.responsesUnsupported ?? false });
  },
  thinkingUnsupported: (p: LLMAPIProfile) => (p.noThinkingModels ?? []).includes(p.modelID),
  effectiveAPIMode: (p: LLMAPIProfile): LLMAPIMode => (p.format === "anthropic" || p.responsesUnsupported ? "chatCompletions" : p.apiMode),
  effectiveThinking: (p: LLMAPIProfile): ThinkingLevel => ((p.noThinkingModels ?? []).includes(p.modelID) ? "off" : p.thinking),
  isLoopback(p: LLMAPIProfile): boolean {
    try {
      return ["localhost", "127.0.0.1", "::1", "[::1]"].includes(new URL(p.baseURL).hostname.toLowerCase());
    } catch {
      return false;
    }
  },
  validated(p: LLMAPIProfile, requireModel = true): LLMAPIProfile {
    const value: LLMAPIProfile = { ...p, name: p.name.trim(), baseURL: p.baseURL.trim().replace(/^\/+|\/+$/g, ""), modelID: p.modelID.trim() };
    const models: string[] = [];
    for (const raw of p.savedModelIDs) {
      const id = raw.trim();
      if (id && !models.includes(id)) models.push(id);
    }
    if (value.modelID && !models.includes(value.modelID)) models.unshift(value.modelID);
    value.savedModelIDs = models;
    let url: URL | null = null;
    try {
      url = new URL(value.baseURL);
    } catch {
      url = null;
    }
    if (!value.name || !url || !["https:", "http:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) {
      throw new Error(tr("请填写名称和有效的 API 地址。"));
    }
    if (requireModel && !value.modelID) throw new Error(tr("请选择或填写模型 ID。"));
    return value;
  },
};

export type LLMProviderPreset = { id: string; name: string; baseURL: string; format: LLMAPIFormat };

export const providerPresets: LLMProviderPreset[] = [
  { id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", format: "openAI" },
  { id: "anthropic", name: "Anthropic", baseURL: "https://api.anthropic.com/v1", format: "anthropic" },
  { id: "gemini", name: "Google Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", format: "openAI" },
  { id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", format: "openAI" },
  { id: "kimi", name: "Kimi", baseURL: "https://api.moonshot.ai/v1", format: "openAI" },
  { id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1", format: "openAI" },
  { id: "nvidia", name: "NVIDIA", baseURL: "https://integrate.api.nvidia.com/v1", format: "openAI" },
  { id: "zhipu", name: "Zhipu AI", baseURL: "https://api.z.ai/api/paas/v4", format: "openAI" },
  { id: "ollama", name: "Ollama", baseURL: "http://localhost:11434/v1", format: "openAI" },
  { id: "custom", name: "自定义", baseURL: "", format: "openAI" },
];

export const localLogoFile = "provider-qwen";
export function logoFile(providerID: string): string | null {
  if (providerID === "custom" || !providerPresets.some((p) => p.id === providerID)) return null;
  return `provider-${providerID}`;
}

const keyService = "local.nomi.llm-api";
const keyCache = new Map<string, string>();
const account = (p: LLMAPIProfile) => `${p.id}|${p.baseURL}`;

export const LLMKeys = {
  async read(p: LLMAPIProfile): Promise<string> {
    const id = account(p);
    const cached = keyCache.get(id);
    if (cached !== undefined) return cached;
    const key = (await secrets.get(keyService, id)) ?? "";
    keyCache.set(id, key);
    return key;
  },
  async save(key: string, p: LLMAPIProfile) {
    await secrets.set(keyService, account(p), key);
    keyCache.set(account(p), key);
  },
  async delete(p: LLMAPIProfile) {
    await secrets.remove(keyService, account(p)).catch(() => {});
    keyCache.delete(account(p));
  },
};

/** The app's model settings. Changes notify `onChange` so the store can re-render. */
export class LLMConfiguration {
  mode: LLMMode;
  profiles: LLMAPIProfile[];
  activeID: string | null;
  listedModels: Record<string, string[]> = {};
  onChange?: () => void;

  constructor() {
    this.mode = prefs.string("nomi.llm.mode") === "api" ? "api" : "local";
    this.profiles = (prefs.get<Partial<LLMAPIProfile>[]>("nomi.llm.profiles") ?? []).map(Profiles.decode);
    this.activeID = prefs.string("nomi.llm.active") ?? null;
  }

  get activeProfile(): LLMAPIProfile | null {
    return this.profiles.find((p) => p.id === this.activeID) ?? null;
  }

  setMode(value: LLMMode) {
    this.mode = value;
    prefs.set("nomi.llm.mode", value);
    this.onChange?.();
  }

  selectModel(modelID: string) {
    const id = modelID.trim();
    const p = this.activeProfile;
    if (!id || !p) return;
    this.profiles = this.profiles.map((x) => (x.id === p.id ? { ...x, modelID: id, savedModelIDs: x.savedModelIDs.includes(id) ? x.savedModelIDs : [...x.savedModelIDs, id] } : x));
    this.persist();
  }

  setListedModels(models: string[], id: string) {
    this.listedModels = { ...this.listedModels, [id]: models };
    this.onChange?.();
  }

  activate(id: string) {
    if (!this.profiles.some((p) => p.id === id)) return;
    this.activeID = id;
    prefs.set("nomi.llm.active", id);
    this.onChange?.();
  }

  async save(draft: LLMAPIProfile, key: string) {
    const value = Profiles.validated(draft);
    const existing = this.profiles.find((p) => p.id === value.id);
    if (existing && existing.baseURL !== value.baseURL) {
      value.responsesUnsupported = false;
      value.noThinkingModels = [];
    }
    if (existing && existing.apiMode !== value.apiMode) value.responsesUnsupported = false;
    if (existing && existing.thinking !== value.thinking) value.noThinkingModels = [];
    const replacement = key.trim();
    if (!Profiles.isLoopback(value) && !replacement) {
      const kept = existing?.baseURL === value.baseURL ? await LLMKeys.read(value).catch(() => "") : "";
      if (!kept) throw new Error(tr("请输入 API 密钥。"));
    }
    if (replacement) await LLMKeys.save(replacement, value);
    if (existing && existing.baseURL !== value.baseURL) await LLMKeys.delete(existing);
    this.profiles = existing ? this.profiles.map((p) => (p.id === value.id ? value : p)) : [...this.profiles, value];
    this.persist();
    if (!this.activeID) this.activate(value.id);
  }

  noteUnsupported(profileID: string, responses: boolean, thinking: boolean) {
    if (!responses && !thinking) return;
    this.profiles = this.profiles.map((p) => {
      if (p.id !== profileID) return p;
      const next = { ...p };
      if (responses) next.responsesUnsupported = true;
      if (thinking && !(next.noThinkingModels ?? []).includes(next.modelID)) next.noThinkingModels = [...(next.noThinkingModels ?? []), next.modelID];
      return next;
    });
    this.persist();
  }

  async delete(profile: LLMAPIProfile) {
    await LLMKeys.delete(profile);
    this.profiles = this.profiles.filter((p) => p.id !== profile.id);
    if (this.activeID === profile.id) {
      this.activeID = null;
      prefs.remove("nomi.llm.active");
    }
    this.persist();
  }

  private persist() {
    prefs.set("nomi.llm.profiles", this.profiles);
    this.onChange?.();
  }
}
