// Models/ChatSession.swift
import { tr, trf } from "../i18n";
import { newID, nowReference } from "../support/format";
import type { AnswerStep } from "./answerSteps";
import type { ChatFileRef, ChatImage } from "./chatImage";

export type ScopeCheck = "off" | "mixed" | "on";
export type ScopeItem = { id: string; categoryID?: string | null; live?: boolean };
export type ScopeCategoryName = { id: string | null; name: string };

/** Sets are stored as arrays, as Swift's JSONEncoder writes them. */
export type ChatScope = {
  includeAll: boolean;
  categoryIDs: string[];
  includesUncategorized: boolean;
  excludedMeetingIDs: string[];
  excludedSourceIDs: string[];
  meetingIDs: string[];
  sourceIDs: string[];
};

export const emptyScope = (): ChatScope => ({
  includeAll: false, categoryIDs: [], includesUncategorized: false, excludedMeetingIDs: [], excludedSourceIDs: [], meetingIDs: [], sourceIDs: [],
});

const cat = (id: string | null | undefined) => id ?? null;

export const Scope = {
  normalize(s: Partial<ChatScope> | null | undefined): ChatScope {
    return { ...emptyScope(), ...(s ?? {}) };
  },

  covers(s: ChatScope, category: string | null): boolean {
    if (s.includeAll) return true;
    if (category) return s.categoryIDs.includes(category);
    return s.includesUncategorized;
  },

  resolve(s: ChatScope, items: ScopeItem[], explicit: string[], excluded: string[], skipLive: boolean): Set<string> {
    const result = new Set<string>();
    for (const item of items) {
      if (skipLive && item.live) continue;
      if (excluded.includes(item.id)) continue;
      if (s.includeAll || this.covers(s, cat(item.categoryID)) || explicit.includes(item.id)) result.add(item.id);
    }
    return result;
  },

  selectedMeetings(s: ChatScope, items: ScopeItem[]) {
    return this.resolve(s, items, s.meetingIDs, s.excludedMeetingIDs, true);
  },
  selectedSources(s: ChatScope, items: ScopeItem[]) {
    return this.resolve(s, items, s.sourceIDs, s.excludedSourceIDs, false);
  },

  state(s: ChatScope, category: string | null, meetings: ScopeItem[], sources: ScopeItem[]): ScopeCheck {
    const meetingPool = meetings.filter((m) => !m.live && cat(m.categoryID) === category);
    const sourcePool = sources.filter((x) => cat(x.categoryID) === category);
    const pool = meetingPool.length + sourcePool.length;
    if (pool === 0) return this.covers(s, category) ? "on" : "off";
    const chosen = this.selectedMeetings(s, meetingPool).size + this.selectedSources(s, sourcePool).size;
    return chosen === 0 ? "off" : chosen === pool ? "on" : "mixed";
  },

  stateAll(s: ChatScope, meetings: ScopeItem[], sources: ScopeItem[]): ScopeCheck {
    const pool = meetings.filter((m) => !m.live).length + sources.length;
    if (pool === 0) return s.includeAll || s.categoryIDs.length || s.includesUncategorized ? "on" : "off";
    const chosen = this.selectedMeetings(s, meetings).size + this.selectedSources(s, sources).size;
    return chosen === 0 ? "off" : chosen === pool ? "on" : "mixed";
  },

  toggleAll(s: ChatScope, meetings: ScopeItem[], sources: ScopeItem[]): ChatScope {
    return this.stateAll(s, meetings, sources) === "on" ? emptyScope() : { ...emptyScope(), includeAll: true };
  },

  toggleCategory(s0: ChatScope, category: string | null, meetings: ScopeItem[], sources: ScopeItem[]): ChatScope {
    let s = clone(s0);
    if (this.state(s, category, meetings, sources) === "on") {
      if (s.includeAll) s = materializeAll(s, category, meetings, sources);
      if (category) s.categoryIDs = s.categoryIDs.filter((c) => c !== category);
      else s.includesUncategorized = false;
      return dropItems(s, category, meetings, sources);
    }
    if (category) s.categoryIDs = [...new Set([...s.categoryIDs, category])];
    else s.includesUncategorized = true;
    return dropItems(s, category, meetings, sources);
  },

  toggleMeeting(s: ChatScope, item: ScopeItem, meetings: ScopeItem[], sources: ScopeItem[]): ChatScope {
    if (item.live) return s;
    return toggle(s, item, "meeting", meetings, sources);
  },

  toggleSource(s: ChatScope, item: ScopeItem, meetings: ScopeItem[], sources: ScopeItem[]): ChatScope {
    return toggle(s, item, "source", meetings, sources);
  },

  chipTitle(s: ChatScope, meetings: ScopeItem[], sources: ScopeItem[], categories: ScopeCategoryName[]): string {
    if (s.includeAll && !s.excludedMeetingIDs.length && !s.excludedSourceIDs.length) return tr("全部会议和资料");
    const chosenMeetings = this.selectedMeetings(s, meetings);
    const chosenSources = this.selectedSources(s, sources);
    const names: string[] = [];
    for (const c of categories) {
      const hasMeeting = meetings.some((m) => cat(m.categoryID) === c.id && chosenMeetings.has(m.id));
      const hasSource = sources.some((x) => cat(x.categoryID) === c.id && chosenSources.has(x.id));
      const flagged = !s.includeAll && this.covers(s, c.id);
      if (hasMeeting || hasSource || flagged) names.push(c.name);
    }
    if (!names.length) return tr("选择范围");
    if (names.length === 1) return trf("%@ · %d 份资料 · %d 场会议", names[0], chosenSources.size, chosenMeetings.size);
    return trf("%d 个分类 · %d 份资料 · %d 场会议", names.length, chosenSources.size, chosenMeetings.size);
  },
};

function clone(s: ChatScope): ChatScope {
  return { ...s, categoryIDs: [...s.categoryIDs], excludedMeetingIDs: [...s.excludedMeetingIDs], excludedSourceIDs: [...s.excludedSourceIDs], meetingIDs: [...s.meetingIDs], sourceIDs: [...s.sourceIDs] };
}

function toggle(s0: ChatScope, item: ScopeItem, side: "meeting" | "source", meetings: ScopeItem[], sources: ScopeItem[]): ChatScope {
  const s = clone(s0);
  const explicit = side === "meeting" ? s.meetingIDs : s.sourceIDs;
  const excluded = side === "meeting" ? s.excludedMeetingIDs : s.excludedSourceIDs;
  const covered = s.includeAll || Scope.covers(s, cat(item.categoryID));
  const selected = !excluded.includes(item.id) && (covered || explicit.includes(item.id));
  const without = (list: string[]) => list.filter((x) => x !== item.id);
  const withItem = (list: string[]) => [...new Set([...list, item.id])];
  if (selected) {
    if (covered) {
      if (side === "meeting") {
        s.excludedMeetingIDs = withItem(s.excludedMeetingIDs);
        s.meetingIDs = without(s.meetingIDs);
      } else {
        s.excludedSourceIDs = withItem(s.excludedSourceIDs);
        s.sourceIDs = without(s.sourceIDs);
      }
    } else if (side === "meeting") s.meetingIDs = without(s.meetingIDs);
    else s.sourceIDs = without(s.sourceIDs);
    return s;
  }
  if (side === "meeting") s.excludedMeetingIDs = without(s.excludedMeetingIDs);
  else s.excludedSourceIDs = without(s.excludedSourceIDs);
  if (!covered) {
    if (side === "meeting") s.meetingIDs = withItem(s.meetingIDs);
    else s.sourceIDs = withItem(s.sourceIDs);
    return promoteIfComplete(s, cat(item.categoryID), meetings, sources);
  }
  return s;
}

function promoteIfComplete(s: ChatScope, category: string | null, meetings: ScopeItem[], sources: ScopeItem[]): ChatScope {
  if (s.includeAll || Scope.state(s, category, meetings, sources) !== "on") return s;
  const next = clone(s);
  if (category) next.categoryIDs = [...new Set([...next.categoryIDs, category])];
  else next.includesUncategorized = true;
  return dropItems(next, category, meetings, sources);
}

function dropItems(s: ChatScope, category: string | null, meetings: ScopeItem[], sources: ScopeItem[]): ChatScope {
  const m = new Set(meetings.filter((x) => cat(x.categoryID) === category).map((x) => x.id));
  const so = new Set(sources.filter((x) => cat(x.categoryID) === category).map((x) => x.id));
  return {
    ...s,
    meetingIDs: s.meetingIDs.filter((x) => !m.has(x)),
    sourceIDs: s.sourceIDs.filter((x) => !so.has(x)),
    excludedMeetingIDs: s.excludedMeetingIDs.filter((x) => !m.has(x)),
    excludedSourceIDs: s.excludedSourceIDs.filter((x) => !so.has(x)),
  };
}

function materializeAll(s: ChatScope, category: string | null, meetings: ScopeItem[], sources: ScopeItem[]): ChatScope {
  const next = clone(s);
  next.includeAll = false;
  const categories = new Set([...meetings, ...sources].map((x) => cat(x.categoryID)));
  categories.delete(category);
  for (const id of categories) {
    if (id) next.categoryIDs = [...new Set([...next.categoryIDs, id])];
    else next.includesUncategorized = true;
  }
  return next;
}

export type ChatCitation = {
  id: string;
  title: string;
  detail: string;
  meetingID?: string | null;
  sourceID?: string | null;
  url?: string | null;
  passage?: number | null;
  chatID?: string | null;
  at?: number | null;
  page?: number | null;
  quote?: string | null;
  excerpt?: string | null;
};

export const Citations = {
  inlineLabel(c: ChatCitation): string {
    const name = c.title.trim();
    const label = name || c.detail.trim();
    return [...label].length <= 40 ? label : [...label].slice(0, 40).join("") + "…";
  },
  inlineURL(c: ChatCitation): string | null {
    if (c.url) {
      try {
        const u = new URL(c.url);
        if (u.protocol === "http:" || u.protocol === "https:") return c.url;
      } catch {
        /* not a URL */
      }
    }
    if (c.meetingID || c.sourceID || c.chatID) return `nomi-cite://${c.id}`;
    return null;
  },
  /** An icon name for the citation chip. */
  symbol(c: ChatCitation): "chat" | "pdf" | "web" | "clock" | "doc" {
    if (c.chatID) return "chat";
    const folded = [c.title, c.detail, c.url ?? ""].map((v) => v.toLowerCase());
    if (folded.some((v) => (v.split(/[?#]/)[0] ?? v).endsWith(".pdf"))) return "pdf";
    if (c.url) return "web";
    if (c.meetingID) return "clock";
    if (c.sourceID) return "doc";
    return "web";
  },
};

export type ChatTurn = {
  id: string;
  question: string;
  answer: string;
  modelName: string;
  createdAt: number;
  citations: ChatCitation[];
  error?: string | null;
  images: ChatImage[];
  files?: ChatFileRef[] | null;
  memoryNote?: string[] | null;
  interrupted?: boolean | null;
  steps?: AnswerStep[] | null;
  answerSeconds?: number | null;
};

export function newTurn(question: string, answer: string, modelName: string, extra: Partial<ChatTurn> = {}): ChatTurn {
  return { id: newID(), question, answer, modelName, createdAt: nowReference(), citations: [], images: [], ...extra };
}

export function decodeTurn(raw: Partial<ChatTurn>): ChatTurn {
  return {
    id: raw.id ?? newID(),
    question: raw.question ?? "",
    answer: raw.answer ?? "",
    modelName: raw.modelName ?? "",
    createdAt: raw.createdAt ?? nowReference(),
    citations: raw.citations ?? [],
    error: raw.error ?? null,
    images: raw.images ?? [],
    files: raw.files ?? null,
    memoryNote: raw.memoryNote ?? null,
    interrupted: raw.interrupted ?? null,
    steps: raw.steps ?? null,
    answerSeconds: raw.answerSeconds ?? null,
  };
}

export type ChatSummary = { text: string; throughTurnID: string; throughDate: number; coveredTurns: number; modelName: string; updatedAt: number };

export type ChatSession = {
  id: string;
  title: string;
  titleCustom: boolean;
  createdAt: number;
  updatedAt: number;
  scope: ChatScope;
  allowsWeb: boolean;
  modelMode?: string | null;
  profileID?: string | null;
  turns: ChatTurn[];
  anchorMeetingID?: string | null;
  summary?: ChatSummary | null;
};

export function newChat(extra: Partial<ChatSession> = {}): ChatSession {
  const now = nowReference();
  return { id: newID(), title: "", titleCustom: false, createdAt: now, updatedAt: now, scope: emptyScope(), allowsWeb: false, turns: [], ...extra };
}

export function decodeChat(raw: Partial<ChatSession>): ChatSession {
  const createdAt = raw.createdAt ?? nowReference();
  return {
    id: raw.id ?? newID(),
    title: raw.title ?? "",
    titleCustom: raw.titleCustom ?? false,
    createdAt,
    updatedAt: raw.updatedAt ?? createdAt,
    scope: Scope.normalize(raw.scope),
    allowsWeb: raw.allowsWeb ?? false,
    modelMode: raw.modelMode ?? null,
    profileID: raw.profileID ?? null,
    turns: (raw.turns ?? []).map(decodeTurn),
    anchorMeetingID: raw.anchorMeetingID ?? null,
    summary: raw.summary ?? null,
  };
}

export const displayTitle = (c: ChatSession) => c.title || tr("新会话");
