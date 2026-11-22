// Models/ChatHistory.swift: which earlier turns go into the next prompt, and chat summaries.
import { toDate } from "../support/format";
import { ChatContext } from "./chatContext";
import { ChatTools } from "./chatTools";
import type { ContextBudget } from "./contextBudget";
import { LibraryDates } from "./librarySearch";
import type { ChatSummary, ChatTurn } from "./chatSession";
import type { LLMMessage } from "../engine/llmRequest";

export type HistoryTurn = { question: string; answer: string };

export type HistoryWindow = {
  text: string;
  includedTurns: Set<string>;
  omittedOlderTurns: number;
  turns: HistoryTurn[];
  summary: string;
};

export const emptyHistory = (): HistoryWindow => ({ text: "", includedTurns: new Set(), omittedOlderTurns: 0, turns: [], summary: "" });

export function historyMessages(w: HistoryWindow): LLMMessage[] {
  const result: LLMMessage[] = [];
  w.turns.forEach((turn, index) => {
    const lead = index === 0 && w.summary ? w.summary + "\n\n" : "";
    result.push({ role: "user", text: lead + turn.question, images: [] });
    result.push({ role: "assistant", text: turn.answer, images: [] });
  });
  if (result.length) result[result.length - 1].cacheMark = true;
  return result;
}

export function forMessages(w: HistoryWindow): HistoryWindow {
  return { ...w, text: w.turns.length ? "" : w.summary };
}

const len = (s: string) => [...s].length;
const sentenceEnds = new Set(["。", "！", "？", "；", ".", "!", "?", ";", "\n"]);

export const ChatHistory = {
  questionLimit: 800,

  window(turns: ChatTurn[], budget: ContextBudget, o: { summary?: ChatSummary | null; omittedImageTurns?: Set<string>; dated?: boolean; stableStart?: boolean } = {}): HistoryWindow {
    const answered = this.answeredTurns(turns);
    const summaryBlock = o.summary ? `Summary of earlier conversation (reference only):\n${o.summary.text}` : "";
    const room = Math.max(Math.floor(budget.history / 2), budget.history - len(summaryBlock));
    const dated = o.dated ?? true;
    let shown: [string, string, HistoryTurn][] = [];
    let used = 0;
    for (const turn of [...answered].reverse()) {
      const image = o.omittedImageTurns?.has(turn.id) ?? false;
      let answerLimit = budget.turnAnswer;
      let text = render(turn, answerLimit, image, dated);
      if (!shown.length && len(text) > room) {
        answerLimit = Math.max(200, room - Math.min(len(turn.question), this.questionLimit) - 60);
        text = render(turn, answerLimit, image, dated);
      } else if (shown.length && used + len(text) > room) break;
      shown.push([turn.id, text, messageParts(turn, answerLimit, image, dated)]);
      used += len(text);
    }
    if (o.stableStart && shown.length > 1) {
      const start = answered.length - shown.length;
      const keep = answered.length - Math.floor((start + 3) / 4) * 4;
      if (keep >= Math.max(2, Math.floor(shown.length / 2)) && keep < shown.length) shown = shown.slice(0, keep);
    }
    if (!shown.length && !summaryBlock) return emptyHistory();
    const parts: string[] = [];
    if (summaryBlock) parts.push(summaryBlock);
    if (shown.length) parts.push("Previous conversation (reference only):\n" + [...shown].reverse().map((s) => s[1]).join("\n\n"));
    const older = answered.length - shown.length;
    const covered = o.summary ? this.coveredCount(answered, o.summary.throughTurnID) : 0;
    return {
      text: parts.join("\n\n"),
      includedTurns: new Set(shown.map((s) => s[0])),
      omittedOlderTurns: Math.max(0, older - covered),
      turns: [...shown].reverse().map((s) => s[2]),
      summary: summaryBlock,
    };
  },

  answeredTurns(turns: ChatTurn[]): ChatTurn[] {
    return turns.filter((t) => !t.error && (t.interrupted === true || t.answer.trim().length > 0));
  },

  coveredCount(answered: ChatTurn[], turnID: string): number {
    const i = answered.findIndex((t) => t.id === turnID);
    return i < 0 ? 0 : i + 1;
  },

  rendered(turn: ChatTurn, answerLimit: number, dated = true): string {
    return render(turn, answerLimit, false, dated);
  },

  cleanedAnswer(answer: string, limit: number): string {
    let text = ChatContext.splitVisual(answer, false).text;
    text = ChatTools.parse(text, false).visible;
    text = replacingPages(text).trim();
    return this.trimmed(text, limit);
  },

  trimmed(text0: string, limit: number): string {
    const text = text0.trim();
    const chars = [...text];
    if (chars.length <= limit || limit <= 0) return text;
    const headLength = Math.floor((limit * 7) / 10);
    const tailLength = Math.max(0, limit - headLength - 3);
    const head = cutAfterLastSentence(chars.slice(0, headLength).join(""));
    if (tailLength <= 0) return head + "…";
    const tail = cutBeforeFirstSentence(chars.slice(chars.length - tailLength).join(""));
    return head + "\n…\n" + tail;
  },
};

function interruptedAnswer(answer: string) {
  return answer ? "(Interrupted by the student.)\n" + answer : "(Interrupted by the student before any answer was written.)";
}

function timeStamp(reference: number): string {
  const d = toDate(reference);
  return LibraryDates.dayStamp(d) + ` ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

function messageParts(turn: ChatTurn, answerLimit: number, image: boolean, dated: boolean): HistoryTurn {
  const stamp = dated ? `[${timeStamp(turn.createdAt)}] ` : "";
  let question = stamp + ChatHistory.trimmed(turn.question, ChatHistory.questionLimit);
  if (image) question += "\n用户发过一张图片";
  let answer = ChatHistory.cleanedAnswer(turn.answer, answerLimit);
  if (turn.interrupted) answer = interruptedAnswer(answer);
  return { question, answer };
}

function render(turn: ChatTurn, answerLimit: number, image: boolean, dated: boolean): string {
  const stamp = dated ? `[${timeStamp(turn.createdAt)}] ` : "";
  const label = turn.interrupted ? "Answer (interrupted by the student)" : "Answer";
  const answer = ChatHistory.cleanedAnswer(turn.answer, answerLimit);
  const shown = turn.interrupted && !answer ? "(none yet: the student interrupted before any answer was written)" : answer;
  let text = `${stamp}Question: ${ChatHistory.trimmed(turn.question, ChatHistory.questionLimit)}\n${label}: ${shown}`;
  if (image) text += "\n用户发过一张图片";
  return text;
}

function cutAfterLastSentence(head: string): string {
  const chars = [...head];
  let index = -1;
  chars.forEach((c, i) => {
    if (sentenceEnds.has(c)) index = i;
  });
  if (index < 0 || index < Math.floor(chars.length / 2)) return head;
  return chars.slice(0, index + 1).join("").trim();
}

function cutBeforeFirstSentence(tail: string): string {
  const chars = [...tail];
  const index = chars.findIndex((c) => sentenceEnds.has(c));
  if (index < 0 || index >= Math.floor(chars.length / 2)) return tail;
  return chars.slice(index + 1).join("").trim();
}

function replacingPages(text: string): string {
  return text.replace(/```([^\n`]*)\n([\s\S]*?)(?:```|$)/g, (whole, info: string, body: string) => {
    const lowered = body.toLowerCase();
    const isPage = info.trim().toLowerCase().startsWith("html") || lowered.includes("<!doctype html") || lowered.includes("<html");
    if (!isPage) return whole;
    const title = body.match(/<title>([^<]{1,80})<\/title>/i)?.[1]?.trim() ?? "";
    return title ? `[交互演示：${title}]` : "[交互演示]";
  });
}

export const ChatSummaries = {
  minimumTurns: 6,
  batchTurns: 3,
  batchCharacters: 3000,
  maxFailures: 3,

  limit(mode: "local" | "api") {
    return mode === "local" ? 600 : 1500;
  },

  pending(turns: ChatTurn[], summary: ChatSummary | null | undefined, budget: ContextBudget): ChatTurn[] | null {
    const answered = ChatHistory.answeredTurns(turns);
    if (answered.length < this.minimumTurns) return null;
    const window = ChatHistory.window(turns, budget, { summary });
    const oldestShown = answered.findIndex((t) => window.includedTurns.has(t.id));
    if (oldestShown < 0) return null;
    const covered = summary ? ChatHistory.coveredCount(answered, summary.throughTurnID) : 0;
    if (covered >= oldestShown) return null;
    const uncovered = answered.slice(covered, oldestShown);
    const characters = uncovered.reduce((n, t) => n + len(ChatHistory.rendered(t, budget.turnAnswer)), 0);
    if (uncovered.length < this.batchTurns && characters < this.batchCharacters) return null;
    return uncovered;
  },

  system(language: string, limit: number): string {
    return `You keep a running summary of one study conversation between a student and Nomi, their study assistant. Merge the earlier summary with the new turns into one summary.
Keep the topics covered, conclusions and definitions given, numbers, names and dates, decisions the student made, and questions still open. Drop greetings, demos and anything repeated.
Write in ${language}, as short plain sentences or bullets, at most ${limit} characters. Reply with the summary only.`;
  },

  prompt(previous: ChatSummary | null | undefined, turns: ChatTurn[], budget: ContextBudget): string {
    const body = turns.map((t) => ChatHistory.rendered(t, budget.turnAnswer)).join("\n\n");
    return `Earlier summary:\n${previous?.text ?? "(none)"}\n\nNew turns:\n${body}`;
  },

  cleaned(reply: string, limit: number): string | null {
    let text = ChatContext.splitVisual(reply, false).text;
    text = ChatTools.parse(text, false).visible.trim();
    if (!text) return null;
    return ChatHistory.trimmed(text, limit);
  },
};
