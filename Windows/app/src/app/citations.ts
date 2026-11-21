// App/AppModel+Citations.swift: what a citation shows in its preview card, the cited PDF page,
// and "Play this moment" (played by Rust from the meeting's recordings, sample-accurate).
import { invoke } from "@tauri-apps/api/core";
import { tr, trf } from "../i18n";
import { formatClock, formatMonthDay, newID, toDate } from "../support/format";
import { CitationQuote } from "../models/citationQuote";
import { ChatHistory } from "../models/chatHistory";
import { LectureMoments } from "../models/lectureMoment";
import { renderedSource, renderedTranslation } from "../models/transcript";
import { SourceTextCache } from "../models/sourceText";
import type { ChatCitation } from "../models/chatSession";
import { paths } from "../platform";
import { MeetingStore, SourceStore } from "./stores";
import { AppModel } from "./model";

export type CitationKindName = "lecture" | "summary" | "pdf" | "slides" | "document" | "picture" | "web" | "chat" | "missing";

const slideTypes = new Set(["ppt", "pptx", "key", "odp"]);
const pictureTypes = new Set(["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "bmp"]);

export const CitationKind = {
  of(c: ChatCitation, fileName?: string): CitationKindName {
    if (c.chatID) return "chat";
    if (c.meetingID) {
      const detail = c.detail.trim();
      return detail === tr("会议摘要") || detail === "会议摘要" ? "summary" : "lecture";
    }
    if (c.sourceID) {
      const type = paths.ext(fileName ?? c.title);
      if (type === "pdf") return "pdf";
      if (slideTypes.has(type)) return "slides";
      if (pictureTypes.has(type)) return "picture";
      return "document";
    }
    return "web";
  },
};

export type CitationDetails = {
  kind: CitationKindName;
  origin: string;
  place: string;
  title: string;
  quote: string;
  excerpt: string;
  translation: string;
  translationQuote: string;
  fileURL: string | null;
  page: number | null;
  meetingID: string | null;
  at: number | null;
  lineAt: number | null;
  until: number | null;
  webURL: string | null;
  missing: string | null;
  hasAudio: boolean;
};

const blank = (kind: CitationKindName, origin: string): CitationDetails => ({
  kind, origin, place: "", title: "", quote: "", excerpt: "", translation: "", translationQuote: "", fileURL: null, page: null, meetingID: null, at: null, lineAt: null, until: null, webURL: null, missing: null, hasAudio: false,
});

declare module "./model" {
  interface AppModel {
    citationDetails(c: ChatCitation): CitationDetails;
    citationFileExcerpt(c: ChatCitation): Promise<string>;
    playMoment(meetingID: string, at: number, until: number | null): Promise<number | null>;
    stopMoment(): void;
    showPDF(path: string, page: number | null, quote: string | null): void;
  }
}

const P = AppModel.prototype;

export function fromNear(text: string, quote: string, lead = 120, limit = 2400): string {
  const chars = [...text];
  const index = quote ? text.indexOf(quote) : -1;
  if (!quote || index < 0) return chars.length > limit ? chars.slice(0, limit).join("") + "…" : text;
  const start = [...text.slice(0, index)].length;
  let head = 0;
  if (start > lead + 40) {
    const earliest = start - lead;
    const ends = new Set(["。", "！", "？", ".", "!", "?"]);
    let found = -1;
    for (let i = earliest; i < start; i++) if (ends.has(chars[i])) {
      found = i + 1;
      break;
    }
    head = found >= 0 ? found : earliest;
    while (head < start && /\s/.test(chars[head])) head++;
  }
  const tail = Math.min(chars.length, head + limit);
  return (head > 0 ? "…" : "") + chars.slice(head, tail).join("") + (tail < chars.length ? "…" : "");
}

export function windowAround(text: string, quote: string, limit = CitationQuote.excerptLimit): string {
  const chars = [...text];
  if (chars.length <= limit) return text;
  const index = quote ? text.indexOf(quote) : -1;
  if (index < 0) return chars.slice(0, limit).join("") + "…";
  const start = [...text.slice(0, index)].length;
  const from = Math.max(0, Math.min(start - Math.floor(limit / 4), chars.length - limit));
  const to = Math.min(chars.length, from + limit);
  return (from > 0 ? "…" : "") + chars.slice(from, to).join("") + (to < chars.length ? "…" : "");
}

P.citationDetails = function (c) {
  if (c.meetingID) {
    const stored = this.meetings.find((m) => m.id === c.meetingID);
    if (!stored) return { ...blank("missing", c.title), missing: tr("这场会议已经删除，无法预览。") };
    const meeting = this.current(stored);
    const origin = `${meeting.title} · ${formatMonthDay(toDate(meeting.startedAt))}`;
    if (CitationKind.of(c) === "summary") {
      const summary = meeting.assistant?.summary ?? "";
      return { ...blank("summary", origin), place: tr("摘要"), quote: c.quote ?? "", excerpt: c.excerpt ?? [...summary].slice(0, CitationQuote.excerptLimit).join(""), meetingID: meeting.id };
    }
    const near = c.at ?? CitationQuote.clockSeconds(c.detail);
    const needle = [c.quote, c.excerpt].find((x) => x) ?? "";
    const moment = LectureMoments.locate(meeting.paragraphs, near, needle, meeting.sourceLanguage, meeting.targetLanguage);
    const hasAudio = (meeting.audioFiles ?? []).length > 0;
    if (moment) {
      const paragraph = meeting.paragraphs[moment.paragraph];
      const lineAt = Math.max(moment.at, paragraph.openedAt);
      return {
        ...blank("lecture", origin),
        place: formatClock(lineAt), meetingID: meeting.id, at: moment.at, lineAt, until: moment.end, hasAudio,
        quote: moment.source,
        excerpt: fromNear(renderedSource(paragraph, meeting.sourceLanguage), moment.source),
        translationQuote: moment.translation,
        translation: fromNear(renderedTranslation(paragraph, meeting.targetLanguage), moment.translation),
      };
    }
    const details = { ...blank("lecture", origin), place: near != null ? formatClock(near) : c.detail, meetingID: meeting.id, at: near };
    let index = -1;
    if (near != null) {
      meeting.paragraphs.forEach((p, i) => {
        if (p.openedAt <= near + 1.5) index = i;
      });
      if (index < 0 && meeting.paragraphs.length) index = 0;
    }
    if (near != null && index >= 0) {
      const paragraph = meeting.paragraphs[index];
      let spoken = "";
      for (const next of meeting.paragraphs.slice(index)) {
        const text = renderedSource(next, meeting.sourceLanguage).trim();
        if (!text) continue;
        spoken += (spoken ? " " : "") + text;
        if ([...spoken].length >= CitationQuote.excerptLimit) break;
      }
      const opening = CitationQuote.sentences(spoken).slice(0, 2).join(" ");
      const picked = c.quote ? [c.quote, c.excerpt ?? spoken] : [opening, spoken];
      details.quote = picked[0];
      details.excerpt = windowAround(picked[1] || spoken, picked[0]);
      const translated = renderedTranslation(paragraph, meeting.targetLanguage).trim();
      details.translation = [...translated].length > 260 ? [...translated].slice(0, 260).join("") + "…" : translated;
      details.until = paragraph.commits.at(-1)?.end ?? null;
    } else {
      details.quote = c.quote ?? "";
      details.excerpt = c.excerpt ?? "";
    }
    details.hasAudio = hasAudio && near != null;
    return details;
  }
  if (c.sourceID) {
    const source = this.sources.find((s) => s.id === c.sourceID);
    if (!source) return { ...blank("missing", c.title), missing: tr("这个文件已从资料中移除，无法预览。") };
    const kind = CitationKind.of(c, source.fileName);
    const page = c.page ?? CitationQuote.pageNumber(c.detail);
    const place = page != null ? (kind === "slides" ? trf("第 %d 张", page) : trf("第 %d 页", page)) : c.detail;
    return { ...blank(kind, source.fileName), place, quote: c.quote ?? "", excerpt: c.excerpt ?? "", fileURL: SourceStore.fileURL(source), page };
  }
  if (c.chatID) {
    const chat = this.chats.find((x) => x.id === c.chatID);
    if (!chat) return { ...blank("missing", c.title), missing: tr("这段对话已经删除，无法预览。") };
    const first = chat.turns.find((t) => t.answer);
    return {
      ...blank("chat", chat.title || tr("对话")),
      place: formatMonthDay(toDate(chat.updatedAt)),
      title: c.quote == null && first ? `“${[...first.question].slice(0, 80).join("")}”` : "",
      quote: c.quote ?? "",
      excerpt: c.excerpt ?? (first ? ChatHistory.cleanedAnswer(first.answer, 300) : ""),
    };
  }
  let host = c.detail;
  try {
    host = new URL(c.url ?? "").hostname.replace(/^www\./, "");
  } catch {
    /* keep detail */
  }
  const title = c.title === host || c.title === c.url ? "" : c.title;
  return { ...blank("web", host), title, quote: c.quote ?? "", excerpt: c.excerpt ?? "", webURL: c.url ?? null };
};

P.citationFileExcerpt = async function (c) {
  const source = c.sourceID ? this.sources.find((s) => s.id === c.sourceID) : null;
  if (!source) return "";
  const blocks = await SourceTextCache.blocks(source, SourceStore.fileURL(source));
  const page = c.page ?? CitationQuote.pageNumber(c.detail);
  const block = blocks.find((b) => b.page != null && b.page === page) ?? blocks.find((b) => b.detail === c.detail) ?? blocks[0];
  return block ? CitationQuote.pick(block.body, "").excerpt : "";
};

/** Mac's MomentPlayer constants. */
export const MomentTiming = {
  clipSeconds: 10,
  tail: 1.0,
  longest: 180,
  leadIn: 0.8,
  length(moment: number, until: number | null): number {
    if (until == null || until <= moment) return this.clipSeconds + this.leadIn;
    return Math.min(this.longest, until - moment + this.leadIn + this.tail);
  },
};

P.playMoment = async function (meetingID, at, until) {
  const meeting = this.meetings.find((m) => m.id === meetingID);
  if (!meeting?.audioFiles?.length) return null;
  const dir = MeetingStore.audioDirectory(meeting.id);
  return invoke<number | null>("moment_play", {
    files: meeting.audioFiles.map((f) => paths.join(dir, f)),
    start: Math.max(0, at - MomentTiming.leadIn),
    seconds: MomentTiming.length(at, until),
  }).catch(() => null);
};

P.stopMoment = function () {
  void invoke("moment_stop");
};

P.showPDF = function (path, page, quote) {
  this.pdfViewer = { id: newID(), path, page, quote };
  this.changed();
};
