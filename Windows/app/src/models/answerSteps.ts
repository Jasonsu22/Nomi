// Models/AnswerSteps.swift
import { trf } from "../i18n";
import { newID } from "../support/format";
import type { ContextBlock } from "./contextBlock";

export type AnswerStepKind = "files" | "library" | "web" | "thinking" | "writing";

export type AnswerStep = {
  id: string;
  kind: AnswerStepKind;
  title: string;
  detail: string;
  /** Seconds since 2001-01-01. */
  startedAt: number;
  endedAt?: number | null;
  count: number;
  /** Not saved with the chat. */
  thought?: string;
};

export function newStep(kind: AnswerStepKind, title: string, startedAt: number): AnswerStep {
  return { id: newID(), kind, title, detail: "", startedAt, endedAt: null, count: 0, thought: "" };
}

export const isRunning = (s: AnswerStep) => s.endedAt == null;
export function stepSeconds(s: AnswerStep, now: number): number {
  return Math.max(1, Math.round((s.endedAt ?? now) - s.startedAt));
}

export const AnswerStepSummary = {
  line(steps: AnswerStep[], seconds: number | null | undefined, now: number): string {
    const parts: string[] = [];
    if (seconds != null && seconds >= 1) parts.push(trf("用时 %d 秒", Math.round(seconds)));
    const files = steps.filter((s) => s.kind === "files").reduce((n, s) => n + s.count, 0);
    if (files > 0) parts.push(trf("读了 %d 个文件", files));
    const searches = steps.filter((s) => s.kind === "library" || s.kind === "web").length;
    if (searches > 0) parts.push(trf("搜索 %d 次", searches));
    const thought = steps.find((s) => s.kind === "thinking");
    if (thought) parts.push(trf("思考了 %d 秒", stepSeconds(thought, now)));
    return parts.join(" · ");
  },
  kept(steps: AnswerStep[]): AnswerStep[] {
    return steps.filter((s) => !isRunning(s) && s.detail).map(({ thought: _t, ...rest }) => rest);
  },
  quoted(text: string): string {
    const flat = text.replace(/\n/g, " ").trim();
    return [...flat].length > 40 ? [...flat].slice(0, 40).join("") + "…" : flat;
  },
  sites(blocks: ContextBlock[]): string {
    const hosts: string[] = [];
    for (const b of blocks) {
      if (!b.url) continue;
      try {
        let host = new URL(b.url).host;
        if (host.startsWith("www.")) host = host.slice(4);
        if (!hosts.includes(host)) hosts.push(host);
      } catch {
        /* not a URL */
      }
    }
    return hosts.slice(0, 3).join(", ");
  },
};
