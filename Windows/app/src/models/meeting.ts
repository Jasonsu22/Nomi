// Models/Meeting.swift
import { tr, trf } from "../i18n";
import { formatClock, formatDuration, formatMeetingTime, languageName, newID, nowReference, toDate } from "../support/format";
import { LectureLanguages } from "../support/languages";
import { renderedSource, renderedTranslation, type Paragraph } from "./transcript";
import type { MeetingVoices } from "./meetingVoices";

export type CaptureSource = "microphone" | "system";

export const captureSourceTitle = (s: CaptureSource) => (s === "microphone" ? tr("麦克风") : tr("系统声音"));

export type AssistantAnswer = { id: string; question: string; answer: string; modelName: string; createdAt: number };

export type MeetingAssistantRecord = {
  summary?: string | null;
  summaryModelName?: string | null;
  summaryAt?: number | null;
  /** The transcript time the summary saw. */
  summaryCoversUntil?: number | null;
  answers: AssistantAnswer[];
};

export const MeetingAssistantRecordOps = {
  answerLimit: 50,
  append(record: MeetingAssistantRecord, answer: AssistantAnswer): MeetingAssistantRecord {
    const answers = [...record.answers, answer];
    return { ...record, answers: answers.slice(Math.max(0, answers.length - this.answerLimit)) };
  },
  /** True when the transcript runs more than a minute past what the summary saw. */
  summaryIsStale(record: MeetingAssistantRecord, transcriptEnd: number): boolean {
    if (record.summary == null || record.summaryCoversUntil == null) return false;
    return transcriptEnd > record.summaryCoversUntil + 60;
  },
};

export type Meeting = {
  id: string;
  title: string;
  /** Seconds since 2001-01-01. */
  startedAt: number;
  duration: number;
  source: CaptureSource;
  sourceLanguage: string;
  targetLanguage: string;
  categoryID?: string | null;
  paragraphs: Paragraph[];
  isLive: boolean;
  inputDeviceName?: string | null;
  audioFiles?: string[] | null;
  assistant?: MeetingAssistantRecord | null;
  voices?: MeetingVoices | null;
  hiddenSpeakers?: string[] | null;
};

/** The paragraphs without the hidden speakers' lines; paragraphs left empty are dropped. */
export function shownParagraphs(meeting: Meeting, paragraphs: Paragraph[] = meeting.paragraphs): Paragraph[] {
  const hidden = new Set(meeting.hiddenSpeakers ?? []);
  if (hidden.size === 0) return paragraphs;
  return paragraphs.flatMap((p) => {
    if (!p.commits.some((c) => c.speaker && hidden.has(c.speaker))) return [p];
    const kept = { ...p, commits: p.commits.filter((c) => !(c.speaker && hidden.has(c.speaker))) };
    return kept.commits.length === 0 && !kept.tail ? [] : [kept];
  });
}

export const inputTitle = (m: Meeting) => m.inputDeviceName ?? captureSourceTitle(m.source);

export const characterCount = (m: Meeting) => m.paragraphs.reduce((n, p) => n + [...renderedSource(p, m.sourceLanguage)].length, 0);

export function meetingMarkdown(m: Meeting, categoryName?: string | null): string {
  const lines = [`# ${m.title}`, ""];
  lines.push(trf("- 时间：%@", formatMeetingTime(toDate(m.startedAt))));
  lines.push(trf("- 时长：%@", formatDuration(m.duration)));
  if (categoryName) lines.push(trf("- 分类：%@", categoryName));
  lines.push(trf("- 输入：%@ · %@ → %@", inputTitle(m), languageName(m.sourceLanguage), languageName(m.targetLanguage)));
  lines.push("");
  for (const p of m.paragraphs) {
    const source = renderedSource(p, m.sourceLanguage);
    if (!source) continue;
    lines.push(`## ${formatClock(p.openedAt)}`, "", source);
    const translation = renderedTranslation(p, m.targetLanguage);
    if (translation) lines.push("", translation);
    lines.push("");
  }
  return lines.join("\n");
}

export function liveMeeting(sourceLanguage?: string, targetLanguage?: string, inputDeviceName?: string | null): Meeting {
  const pair = LectureLanguages.currentPair();
  return {
    id: newID(),
    title: tr("未命名会议"),
    startedAt: nowReference(),
    duration: 0,
    source: "microphone",
    sourceLanguage: sourceLanguage ?? pair.source,
    targetLanguage: targetLanguage ?? pair.target,
    categoryID: null,
    paragraphs: [],
    isLive: true,
    inputDeviceName: inputDeviceName ?? null,
  };
}

/** The end of what a transcript covers. */
export const transcriptEnd = (paragraphs: Paragraph[]) => Math.max(0, ...paragraphs.flatMap((p) => p.commits.map((c) => c.end)));
