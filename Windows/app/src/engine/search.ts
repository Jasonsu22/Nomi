// Models/SearchConfiguration.swift and Engine/SearchClient.swift: web search through Tavily, Exa
// or the student's own SearXNG.
import { fetch } from "@tauri-apps/plugin-http";
import { tr, trf } from "../i18n";
import type { ContextBlock } from "../models/contextBlock";
import { prefs } from "../support/prefs";
import { secrets } from "../platform";

export type SearchVendor = "tavily" | "exa" | "searxng";
export const searchVendors: SearchVendor[] = ["tavily", "exa", "searxng"];
export const vendorTitle = (v: SearchVendor) => ({ tavily: "Tavily", exa: "Exa", searxng: "SearXNG" })[v];
export const vendorLogo = (v: SearchVendor) => `search-${v}`;
export const needsBaseURL = (v: SearchVendor) => v === "searxng";
export const accountURL = (v: SearchVendor) => ({ tavily: "https://app.tavily.com/home", exa: "https://dashboard.exa.ai/api-keys", searxng: "https://docs.searxng.org/" })[v];

export type SearchHit = { title: string; url: string; snippet: string };

export function hitBlock(hit: SearchHit): ContextBlock {
  let host = "";
  try {
    host = new URL(hit.url).hostname;
  } catch {
    host = "";
  }
  return { title: hit.title || host || hit.url, detail: host, body: hit.snippet ? `${hit.snippet}\n${hit.url}` : hit.url, url: hit.url };
}

export function normalizeSearchURL(raw: string): string {
  const trimmed = raw.trim().replace(/\/+$/, "");
  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    throw new Error(tr("请填写有效的搜索地址。"));
  }
  if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || url.search || url.hash) throw new Error(tr("请填写有效的搜索地址。"));
  return `${url.protocol}//${url.host}${url.pathname && url.pathname !== "/" ? url.pathname : ""}`;
}

const service = "local.nomi.search-api";
const savedFlag = (v: SearchVendor) => `nomi.search.hasKey.${v}`;

export const SearchKeys = {
  contains: (v: SearchVendor) => prefs.bool(savedFlag(v)) === true,
  read: async (v: SearchVendor) => (await secrets.get(service, v)) ?? "",
  async save(key: string, v: SearchVendor) {
    await secrets.set(service, v, key);
    prefs.set(savedFlag(v), true);
  },
  async delete(v: SearchVendor) {
    await secrets.remove(service, v).catch(() => {});
    prefs.remove(savedFlag(v));
  },
};

const plain = (t: string) => t.replace(/<[^>]+>/g, "").trim();
const clip = (t: string) => ([...t].length > 600 ? [...t].slice(0, 600).join("") : t);

export const SearchClient = {
  async search(vendor: SearchVendor, key: string, baseURL: string, query: string, limit = 5): Promise<SearchHit[]> {
    const k = key.trim();
    let url: string;
    const init: { method: string; headers: Record<string, string>; body?: string; connectTimeout?: number } = { method: "GET", headers: {}, connectTimeout: 15_000 };
    if (vendor === "tavily") {
      url = "https://api.tavily.com/search";
      init.method = "POST";
      init.headers.Authorization = `Bearer ${k}`;
      init.body = JSON.stringify({ query, max_results: limit, search_depth: "basic" });
    } else if (vendor === "exa") {
      url = "https://api.exa.ai/search";
      init.method = "POST";
      init.headers["x-api-key"] = k;
      init.body = JSON.stringify({ query, numResults: limit, contents: { highlights: true } });
    } else {
      url = `${normalizeSearchURL(baseURL)}/search?q=${encodeURIComponent(query)}&format=json`;
      if (k) init.headers.Authorization = `Bearer ${k}`;
    }
    if (init.body) init.headers["Content-Type"] = "application/json";
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15_000);
    try {
      const response = await fetch(url, { ...init, signal: controller.signal });
      const text = await response.text();
      if (!response.ok) throw new Error(this.failureMessage(vendor, response.status, text, k));
      return this.hits(vendor, text, limit);
    } finally {
      clearTimeout(timer);
    }
  },

  hits(vendor: SearchVendor, text: string, limit = 5): SearchHit[] {
    let o: Record<string, unknown>;
    try {
      o = JSON.parse(text);
    } catch {
      throw new Error(tr("搜索响应无法解析。"));
    }
    const rows = Array.isArray(o.results) ? (o.results as Record<string, unknown>[]) : [];
    const hits: SearchHit[] = [];
    for (const row of rows) {
      const raw = String(row.url ?? "").trim();
      try {
        const u = new URL(raw);
        if (!["http:", "https:"].includes(u.protocol)) continue;
      } catch {
        continue;
      }
      let snippet = "";
      if (vendor === "exa") {
        const h = row.highlights;
        const contents = row.contents as Record<string, unknown> | undefined;
        snippet = Array.isArray(h) && h.length ? String(h[0]) : Array.isArray(contents?.highlights) && (contents!.highlights as unknown[]).length ? String((contents!.highlights as unknown[])[0]) : String(row.text ?? "");
      } else snippet = String(row.content ?? "");
      hits.push({ title: plain(String(row.title ?? "")), url: raw, snippet: clip(plain(snippet)) });
    }
    return hits.slice(0, Math.max(0, limit));
  },

  failureMessage(vendor: SearchVendor, status: number, text: string, key: string): string {
    if (vendor === "searxng" && status === 403) return tr("这台 SearXNG 没有打开 JSON。在它的设置里把 json 加进 search.formats。");
    let body = text.slice(0, 180);
    try {
      const o = JSON.parse(text);
      body = String(o.message ?? (typeof o.error === "string" ? o.error : o.error?.message) ?? o.detail ?? body).slice(0, 180);
    } catch {
      /* raw text */
    }
    if (key) body = body.split(key).join("••••");
    return trf("API 请求失败（HTTP %d）：%@", status, body);
  },
};

export class SearchConfiguration {
  activeID: string | null;
  guideDismissed: boolean;
  revision = 0;
  onChange?: () => void;
  private keyCache = new Map<string, string>();

  constructor() {
    this.activeID = prefs.string("nomi.search.active") ?? null;
    this.guideDismissed = prefs.bool("nomi.search.guideDismissed") === true;
  }

  get activeVendor(): SearchVendor | null {
    return searchVendors.includes(this.activeID as SearchVendor) ? (this.activeID as SearchVendor) : null;
  }
  get selected(): SearchVendor | null {
    const v = this.activeVendor;
    return v && this.isReady(v) ? v : null;
  }
  get isActiveReady() {
    return this.selected !== null;
  }
  get hasReadyProvider() {
    return searchVendors.some((v) => this.isReady(v));
  }

  isReady(v: SearchVendor): boolean {
    if (needsBaseURL(v)) {
      try {
        normalizeSearchURL(prefs.string(`nomi.search.baseURL.${v}`) ?? "");
        return true;
      } catch {
        return false;
      }
    }
    return SearchKeys.contains(v);
  }

  status(v: SearchVendor): string {
    if (!this.isReady(v)) return tr("未配置");
    if (needsBaseURL(v) && !SearchKeys.contains(v)) return prefs.string(`nomi.search.baseURL.${v}`) ?? tr("已保存密钥");
    return tr("已保存密钥");
  }

  endpoint(v: SearchVendor) {
    return needsBaseURL(v) ? prefs.string(`nomi.search.baseURL.${v}`) ?? "" : "";
  }

  select(v: SearchVendor) {
    if (!this.isReady(v)) return;
    this.storeActive(v);
    this.bump();
  }

  dismissGuide() {
    this.guideDismissed = true;
    prefs.set("nomi.search.guideDismissed", true);
    this.bump();
  }

  async save(v: SearchVendor, key: string, baseURL: string) {
    const trimmed = key.trim();
    const normalized = needsBaseURL(v) ? normalizeSearchURL(baseURL) : null;
    if (!needsBaseURL(v) && !trimmed) throw new Error(tr("请输入 API 密钥。"));
    if (!trimmed) {
      await SearchKeys.delete(v);
      this.keyCache.set(v, "");
    } else {
      await SearchKeys.save(trimmed, v);
      this.keyCache.set(v, trimmed);
    }
    if (normalized) prefs.set(`nomi.search.baseURL.${v}`, normalized);
    if (!this.selected) this.storeActive(v);
    this.bump();
  }

  async delete(v: SearchVendor): Promise<boolean> {
    await SearchKeys.delete(v);
    this.keyCache.set(v, "");
    prefs.remove(`nomi.search.baseURL.${v}`);
    const wasActive = this.activeID === v;
    if (wasActive) this.storeActive(null);
    this.bump();
    return wasActive;
  }

  async test(v: SearchVendor, key: string, baseURL: string): Promise<number> {
    const trimmed = key.trim();
    let endpoint = "";
    if (needsBaseURL(v)) endpoint = normalizeSearchURL(baseURL);
    else if (!trimmed) throw new Error(tr("请输入 API 密钥。"));
    return (await SearchClient.search(v, trimmed, endpoint, "nomi")).length;
  }

  async testSaved(v: SearchVendor) {
    return this.test(v, await this.storedKey(v), this.endpoint(v));
  }

  async lookup(query: string): Promise<SearchHit[]> {
    const v = this.selected;
    if (!v) throw new Error(tr("先在设置里配置一个搜索服务"));
    return SearchClient.search(v, await this.storedKey(v), this.endpoint(v), query);
  }

  private async storedKey(v: SearchVendor): Promise<string> {
    const cached = this.keyCache.get(v);
    if (cached !== undefined) return cached;
    const key = await SearchKeys.read(v).catch(() => "");
    this.keyCache.set(v, key);
    return key;
  }

  private storeActive(v: SearchVendor | null) {
    this.activeID = v;
    if (v) prefs.set("nomi.search.active", v);
    else prefs.remove("nomi.search.active");
  }

  private bump() {
    this.revision++;
    this.onChange?.();
  }
}
