// Models/LibrarySearch.swift
import { tr, trf } from "../i18n";
import { formatClock } from "../support/format";
import { ContextBudgets } from "./contextBudget";
import type { ContextBlock } from "./contextBlock";

export type LibraryKind = "meeting" | "chat" | "source";
export const allLibraryKinds: LibraryKind[] = ["meeting", "chat", "source"];

export type LibraryDocument = {
  kind: LibraryKind;
  title: string;
  date: Date;
  detail: string;
  body: string;
  group: string;
  meetingID?: string | null;
  sourceID?: string | null;
  chatID?: string | null;
};

export type DateRange = { start: Date; end: Date };
const inRange = (r: DateRange, d: Date) => d >= r.start && d <= r.end;

export type LibraryRequest = { query: string; kinds: Set<LibraryKind>; range?: DateRange | null };

export function libraryRequest(query: string, kinds: Set<LibraryKind> = new Set(allLibraryKinds), range?: DateRange | null): LibraryRequest {
  return { query, kinds: kinds.size ? kinds : new Set(allLibraryKinds), range: range ?? null };
}

const pastCues = ["上次", "上回", "之前", "以前", "刚才", "聊过", "聊了", "说过", "讲过", "问过", "提到过", "老师说", "老师讲", "教授说", "上节课", "上一节课", "那节课", "课上说", "课上讲", "我们讨论",
  "last time", "earlier", "previously", "we talked", "we discussed", "we chatted", "you said", "you told", "i asked", "teacher said", "professor said", "lecturer said", "in class", "last class", "last lecture", "last session", "remember when"];
const outsideClassCues = ["上次", "上回", "上节课", "上一节课", "那节课", "其他课", "别的课", "另一节课", "聊过", "问过",
  "last time", "last class", "last lecture", "last session", "another class", "other class", "other lecture", "we chatted", "i asked"];

function kindNamed(name: string): LibraryKind | null {
  const n = name.toLowerCase().trim();
  if (["meeting", "meetings", "lecture", "lectures", "transcript", "transcripts", "recording", "recordings"].includes(n)) return "meeting";
  if (["chat", "chats", "conversation", "conversations", "history"].includes(n)) return "chat";
  if (["source", "sources", "file", "files", "document", "documents", "material", "materials"].includes(n)) return "source";
  return null;
}

export const LibraryRequests = {
  parse(body: string, now = new Date()): LibraryRequest {
    const trimmed = body.trim();
    let object: Record<string, unknown> | null = null;
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) object = parsed;
    } catch {
      object = null;
    }
    if (!object) return libraryRequest(trimmed, undefined, LibraryDates.range(trimmed, now));
    const query = String(object.query ?? "").trim();
    const raw = object.in;
    const names = Array.isArray(raw) ? raw.map(String) : typeof raw === "string" ? [raw] : [];
    const kinds = new Set(names.map(kindNamed).filter((k): k is LibraryKind => !!k));
    const from = typeof object.from === "string" ? LibraryDates.day(object.from) : null;
    const to = typeof object.to === "string" ? LibraryDates.day(object.to) : null;
    let range: DateRange | null;
    if (from || to) {
      const start = from?.start ?? new Date(-8.64e15);
      const end = to?.end ?? now;
      range = start <= end ? { start, end } : { start: end, end: start };
    } else {
      range = LibraryDates.range(query, now);
    }
    return libraryRequest(query, kinds, range);
  },

  pointsOutsideClass(question: string, classStartedAt: Date, now = new Date()): boolean {
    const folded = question.toLowerCase();
    if (outsideClassCues.some((c) => folded.includes(c))) return true;
    const range = LibraryDates.range(question, now);
    return !!range && !inRange(range, classStartedAt);
  },

  referencesPast(question: string, now = new Date()): boolean {
    const folded = question.toLowerCase();
    if (pastCues.some((c) => folded.includes(c))) return true;
    return LibraryDates.range(question, now) !== null;
  },
};

const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const addDays = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes(), d.getSeconds());
const dayRange = (d: Date): DateRange => ({ start: startOfDay(d), end: new Date(startOfDay(addDays(d, 1)).getTime() - 1) });
/** Weeks start on Monday. */
const weekRange = (d: Date): DateRange => {
  const offset = (d.getDay() + 6) % 7;
  const start = startOfDay(addDays(d, -offset));
  return { start, end: new Date(addDays(start, 7).getTime() - 1) };
};
const monthRange = (d: Date): DateRange => ({ start: new Date(d.getFullYear(), d.getMonth(), 1), end: new Date(new Date(d.getFullYear(), d.getMonth() + 1, 1).getTime() - 1) });
const two = (n: number) => String(n).padStart(2, "0");

export const LibraryDates = {
  day(text: string): DateRange | null {
    const parts = text.split("-").map((p) => Number(p));
    if (parts.length !== 3 || parts.some((p) => !Number.isFinite(p))) return null;
    return dayRange(new Date(parts[0], parts[1] - 1, parts[2]));
  },

  range(text: string, now = new Date()): DateRange | null {
    const folded = text.toLowerCase();
    const has = (words: string[]) => words.some((w) => folded.includes(w));
    const days = lastDays(folded);
    if (days) return { start: startOfDay(addDays(now, -days)), end: now };
    if (has(["day before yesterday", "前天"])) return dayRange(addDays(now, -2));
    if (has(["yesterday", "昨天", "昨晚"])) return dayRange(addDays(now, -1));
    if (has(["today", "今天", "今早", "今晚"])) return dayRange(now);
    if (has(["last week", "previous week", "上周", "上星期", "上个星期", "上礼拜", "上个礼拜"])) return weekRange(addDays(now, -7));
    if (has(["this week", "这周", "本周", "这个星期", "这星期", "这礼拜"])) return weekRange(now);
    if (has(["last month", "previous month", "上个月", "上月"])) return monthRange(new Date(now.getFullYear(), now.getMonth() - 1, 15));
    if (has(["this month", "这个月", "本月"])) return monthRange(now);
    if (has(["recently", "lately", "past few days", "最近", "这几天", "近几天"])) return { start: startOfDay(addDays(now, -7)), end: now };
    return null;
  },

  stamp: (d: Date) => `${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())} ${two(d.getHours())}:${two(d.getMinutes())}`,
  shortDay: (d: Date) => `${two(d.getMonth() + 1)}-${two(d.getDate())}`,
  dayStamp: (d: Date) => `${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())}`,
};

function lastDays(text: string): number | null {
  for (const pattern of [/(?:last|past)\s+(\d{1,3})\s+days?/, /(?:最近|过去|近)\s*(\d{1,3})\s*天/]) {
    const m = text.match(pattern);
    if (m && Number(m[1]) > 0) return Number(m[1]);
  }
  return null;
}

const stopWords = new Set(["the", "and", "for", "what", "did", "does", "was", "were", "about", "that", "this", "with", "from", "you", "we", "our", "my", "me", "is", "are", "of", "to", "in", "on", "a", "an", "it", "do", "say", "said", "tell", "talk", "talked", "chat", "chatted", "last", "week", "month", "today", "yesterday", "earlier", "before", "teacher", "professor", "class", "lecture", "time", "previously", "recently",
  "什么", "我们", "你们", "上周", "这周", "本周", "昨天", "今天", "前天", "上次", "之前", "以前", "老师", "教授", "说了", "说过", "讲了", "讲过", "聊了", "聊过", "聊天", "一下", "这个", "那个", "有没", "没有", "哪些", "怎么", "时候", "最近", "个月", "上个", "星期", "礼拜", "提到", "上课", "节课"]);

const isLetterOrNumber = (c: string) => /[\p{L}\p{N}]/u.test(c);
const isASCII = (c: string) => (c.codePointAt(0) ?? 0) < 128;

export const LibrarySearch = {
  get budget() {
    return ContextBudgets.local.library;
  },
  limit: 14,

  run(request: LibraryRequest, documents: LibraryDocument[], now = new Date(), budget = ContextBudgets.local.library, limit = 14): ContextBlock[] {
    const candidates = documents.filter((d) => request.kinds.has(d.kind) && (!request.range || inRange(request.range, d.date)));
    if (!candidates.length) return [];
    const terms = new Set(this.searchTerms(request.query));
    const ranked = terms.size ? rank(candidates, terms, now) : [];
    const picked = ranked.length ? ranked : overview(candidates);
    return fill(picked, budget, limit);
  },

  relevance(texts: string[], query: string): number[] {
    const terms = new Set(this.searchTerms(query));
    if (!terms.size || !texts.length) return texts.map(() => 0);
    const tokenized = texts.map((t) => this.searchTerms(t));
    const lengths = tokenized.map((t) => Math.max(t.length, 1));
    const average = lengths.reduce((a, b) => a + b, 0) / lengths.length;
    const frequency = new Map<string, number>();
    for (const tokens of tokenized) for (const term of new Set(tokens)) if (terms.has(term)) frequency.set(term, (frequency.get(term) ?? 0) + 1);
    const count = texts.length;
    return tokenized.map((tokens, index) => {
      const counts = new Map<string, number>();
      for (const t of tokens) if (terms.has(t)) counts.set(t, (counts.get(t) ?? 0) + 1);
      let score = 0;
      for (const [term, hits] of counts) {
        const df = frequency.get(term) ?? 0;
        const idf = Math.log(1 + (count - df + 0.5) / (df + 0.5));
        score += (idf * hits * 2.2) / (hits + 1.2 * (0.25 + (0.75 * lengths[index]) / average));
      }
      return score;
    });
  },

  searchTerms(text: string): string[] {
    const terms: string[] = [];
    let latin = "";
    let run: string[] = [];
    const flushLatin = () => {
      if (latin.length >= 2 && !stopWords.has(latin)) terms.push(latin);
      latin = "";
    };
    const flushRun = () => {
      if (run.length === 1) terms.push(run[0]);
      else if (run.length > 1) for (let i = 0; i < run.length - 1; i++) {
        const pair = run[i] + run[i + 1];
        if (!stopWords.has(pair)) terms.push(pair);
      }
      run = [];
    };
    for (const ch of text.toLowerCase()) {
      if (isLetterOrNumber(ch)) {
        if (isASCII(ch)) {
          flushRun();
          latin += ch;
        } else {
          flushLatin();
          run.push(ch);
        }
      } else {
        flushLatin();
        flushRun();
      }
    }
    flushLatin();
    flushRun();
    return terms;
  },

  meetingDocuments(id: string, title: string, startedAt: Date, paragraphs: { openedAt: number; source: string; translation: string }[], summary?: string | null): LibraryDocument[] {
    const documents: LibraryDocument[] = [];
    const s = summary?.trim();
    if (s) documents.push({ kind: "meeting", title, date: startedAt, detail: LibraryDates.dayStamp(startedAt) + " · " + tr("会议摘要"), body: s, group: id, meetingID: id });
    let text = "";
    let opened: number | null = null;
    const flush = () => {
      if (opened === null || !text) return;
      documents.push({
        kind: "meeting", title, date: new Date(startedAt.getTime() + opened * 1000),
        detail: LibraryDates.dayStamp(startedAt) + " · " + formatClock(opened), body: text, group: id, meetingID: id,
      });
    };
    for (const p of paragraphs) {
      const source = p.source.trim();
      if (!source) continue;
      if (opened === null) opened = p.openedAt;
      const translation = p.translation.trim();
      text += (text ? "\n" : "") + source + (translation ? "\n(" + translation + ")" : "");
      if ([...text].length >= 700) {
        flush();
        text = "";
        opened = null;
      }
    }
    flush();
    return documents;
  },

  chatDocuments(id: string, turns: { question: string; answer: string; error?: string | null; createdAt: Date }[], summary?: { text: string; throughDate: Date } | null): LibraryDocument[] {
    const out: LibraryDocument[] = [];
    if (summary) out.push({
      kind: "chat", title: trf("%@ 的对话", LibraryDates.shortDay(summary.throughDate)), date: summary.throughDate, detail: tr("对话摘要"),
      body: `Summary of an earlier conversation.\n${summary.text}`, group: id, chatID: id,
    });
    for (const turn of turns) {
      const answer = turn.answer.trim();
      if (turn.error || (!turn.question && !answer)) continue;
      out.push({
        kind: "chat", title: trf("%@ 的对话", LibraryDates.shortDay(turn.createdAt)), date: turn.createdAt, detail: LibraryDates.stamp(turn.createdAt),
        body: `Earlier conversation.\nStudent: ${[...turn.question].slice(0, 600).join("")}\nNomi: ${[...answer].slice(0, 1000).join("")}`, group: id, chatID: id,
      });
    }
    return out;
  },

  sourceDocuments(source: { id: string; importedAt: Date }, blocks: ContextBlock[]): LibraryDocument[] {
    return blocks.map((b) => ({ kind: "source", title: b.title, date: source.importedAt, detail: b.detail, body: b.body, group: source.id, sourceID: source.id }));
  },
};

function rank(documents: LibraryDocument[], terms: Set<string>, now: Date): LibraryDocument[] {
  const tokenized = documents.map((d) => LibrarySearch.searchTerms(d.title + "\n" + d.body));
  const lengths = tokenized.map((t) => Math.max(t.length, 1));
  const average = lengths.reduce((a, b) => a + b, 0) / lengths.length;
  const frequency = new Map<string, number>();
  for (const tokens of tokenized) for (const term of new Set(tokens)) if (terms.has(term)) frequency.set(term, (frequency.get(term) ?? 0) + 1);
  const count = documents.length;
  const scored: [number, number][] = [];
  tokenized.forEach((tokens, index) => {
    const counts = new Map<string, number>();
    for (const t of tokens) if (terms.has(t)) counts.set(t, (counts.get(t) ?? 0) + 1);
    if (!counts.size) return;
    let score = 0;
    for (const [term, hits] of counts) {
      const df = frequency.get(term) ?? 0;
      const idf = Math.log(1 + (count - df + 0.5) / (df + 0.5));
      score += (idf * hits * 2.2) / (hits + 1.2 * (0.25 + (0.75 * lengths[index]) / average));
    }
    const ageDays = Math.max(0, (now.getTime() - documents[index].date.getTime()) / 86_400_000);
    score *= 1 + 0.15 * Math.exp(-ageDays / 30);
    scored.push([score, index]);
  });
  return scored.sort((a, b) => (a[0] !== b[0] ? b[0] - a[0] : documents[b[1]].date.getTime() - documents[a[1]].date.getTime())).map(([, i]) => documents[i]);
}

function overview(documents: LibraryDocument[]): LibraryDocument[] {
  const seen = new Set<string>();
  const picked: LibraryDocument[] = [];
  for (const d of [...documents].sort((a, b) => b.date.getTime() - a.date.getTime())) {
    if (d.kind !== "chat") {
      if (seen.has(d.group)) continue;
      seen.add(d.group);
    }
    picked.push(d);
  }
  return picked;
}

function fill(documents: LibraryDocument[], budget: number, limit: number): ContextBlock[] {
  const blocks: ContextBlock[] = [];
  let used = 0;
  for (const d of documents) {
    if (blocks.length >= limit || used >= budget) break;
    let body = d.body.trim();
    const room = Math.min(budget - used, 1400);
    if (room < 120) break;
    if ([...body].length > room) body = [...body].slice(0, room).join("") + "…";
    used += [...body].length;
    blocks.push({ title: d.title, detail: d.detail, body, meetingID: d.meetingID, sourceID: d.sourceID, chatID: d.chatID });
  }
  return blocks;
}

export type LibraryExclusions = { turns: Set<string>; meetings: Set<string>; sources: Set<string> };
