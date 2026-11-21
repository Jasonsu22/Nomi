// Models/MeetingVoices.swift (0.10): who speaks in a recording, line labels, and "This is me".
import { tr, trf } from "../i18n";
import { prefs } from "../support/prefs";
import type { Commit, Paragraph } from "./transcript";

export type MeetingVoices = {
  teacher: string;
  seconds: Record<string, number>;
  checkedAt: number;
  prints?: Record<string, number[]> | null;
  me?: string | null;
  meChosen?: boolean | null;
  names?: Record<string, string> | null;
};

export type VoiceSpan = { start: number; end: number; speaker: string };

export function mostHeard(seconds: Record<string, number>): string | null {
  let best: string | null = null;
  for (const [key, value] of Object.entries(seconds)) {
    if (best === null || value > seconds[best] || (value === seconds[best] && key < best)) best = key;
  }
  return best;
}

export const Voices = {
  others(v: MeetingVoices): string[] {
    const blends = MyVoice.blends(v.prints ?? {});
    return Object.keys(v.seconds)
      .filter((k) => k !== v.teacher && !blends.has(k))
      .sort((a, b) => {
        const x = v.seconds[a] ?? 0, y = v.seconds[b] ?? 0;
        return x === y ? (a < b ? -1 : 1) : y - x;
      });
  },

  number(v: MeetingVoices, speaker: string): number {
    if (speaker === v.teacher) return 1;
    const others = this.others(v);
    const index = others.indexOf(speaker);
    return (index < 0 ? others.length : index) + 2;
  },

  name(v: MeetingVoices, speaker: string): string {
    const given = v.names?.[speaker]?.trim();
    if (given) return given;
    if (speaker === v.me) return tr("我");
    if (MyVoice.blends(v.prints ?? {}).has(speaker)) return tr("多人");
    return trf("说话人 %d", this.number(v, speaker));
  },

  side(v: MeetingVoices, commit: Commit): "teacher" | "me" | "classmate" {
    if (!commit.speaker || commit.speaker === v.teacher) return "teacher";
    return commit.speaker === v.me ? "me" : "classmate";
  },

  isClassmate(v: MeetingVoices, commit: Commit) {
    return this.side(v, commit) === "classmate";
  },
};

export const VoiceLabels = {
  share: 0.7,
  minimumSpeech: 0.4,

  speaker(commit: Commit, spans: VoiceSpan[]): string | null {
    const heard: Record<string, number> = {};
    for (const s of spans) {
      if (s.end > commit.start && s.start < commit.end) heard[s.speaker] = (heard[s.speaker] ?? 0) + Math.min(s.end, commit.end) - Math.max(s.start, commit.start);
    }
    const total = Object.values(heard).reduce((a, b) => a + b, 0);
    const top = mostHeard(heard);
    if (total < this.minimumSpeech || !top || heard[top] / total < this.share) return null;
    return top;
  },

  /** For spans sorted by start: only those that can reach the line are looked at. */
  speakerSorted(commit: Commit, spans: VoiceSpan[], longest: number): string | null {
    let low = 0, high = spans.length;
    const from = commit.start - longest;
    while (low < high) {
      const mid = (low + high) >> 1;
      if (spans[mid].start < from) low = mid + 1;
      else high = mid;
    }
    const near: VoiceSpan[] = [];
    for (let i = low; i < spans.length && spans[i].start < commit.end; i++) if (spans[i].end > commit.start) near.push(spans[i]);
    return this.speaker(commit, near);
  },

  apply(spans: VoiceSpan[], paragraphs: Paragraph[]): Paragraph[] {
    if (!spans.length) return paragraphs;
    const first = Math.min(...spans.map((s) => s.start));
    const last = Math.max(...spans.map((s) => s.end));
    const sorted = [...spans].sort((a, b) => a.start - b.start);
    const longest = Math.max(0, ...sorted.map((s) => s.end - s.start));
    return paragraphs.map((p) => ({
      ...p,
      commits: p.commits.map((c) => (c.end > first && c.start < last ? { ...c, speaker: this.speakerSorted(c, sorted, longest) } : c)),
    }));
  },

  merging(prior: MeetingVoices | null | undefined, spans: VoiceSpan[], prints: Record<string, number[]>, now: number): { voices: MeetingVoices; spans: VoiceSpan[] } | null {
    const seconds: Record<string, number> = {};
    for (const s of spans) seconds[s.speaker] = (seconds[s.speaker] ?? 0) + Math.max(0, s.end - s.start);
    const top = mostHeard(seconds);
    if (!top) return prior ? { voices: prior, spans } : null;
    if (!prior) {
      return { voices: { teacher: top, seconds, checkedAt: now, prints: Object.keys(prints).length ? prints : null }, spans };
    }
    const voices: MeetingVoices = { ...prior, seconds: { ...prior.seconds } };
    const renamed = spans.map((s) => (s.speaker === top ? { ...s, speaker: voices.teacher } : s));
    for (const [speaker, time] of Object.entries(seconds)) {
      const key = speaker === top ? voices.teacher : speaker;
      voices.seconds[key] = (voices.seconds[key] ?? 0) + time;
    }
    const all = { ...(voices.prints ?? {}) };
    for (const [speaker, print] of Object.entries(prints)) if (speaker !== top) all[speaker] = print;
    voices.prints = Object.keys(all).length ? all : null;
    voices.checkedAt = now;
    return { voices, spans: renamed };
  },

  label(paragraphs: Paragraph[], spans: VoiceSpan[], now: number): { paragraphs: Paragraph[]; voices: MeetingVoices } | null {
    const seconds: Record<string, number> = {};
    for (const s of spans) seconds[s.speaker] = (seconds[s.speaker] ?? 0) + Math.max(0, s.end - s.start);
    const teacher = mostHeard(seconds);
    if (!teacher) return null;
    const sorted = [...spans].sort((a, b) => a.start - b.start);
    return {
      paragraphs: paragraphs.map((p) => ({ ...p, commits: p.commits.map((c) => ({ ...c, speaker: this.speaker(c, sorted) })) })),
      voices: { teacher, seconds, checkedAt: now },
    };
  },

  mainVoice(paragraph: Paragraph, excluding: string | null | undefined): string | null {
    const heard: Record<string, number> = {};
    for (const c of paragraph.commits) if (c.speaker && c.speaker !== excluding) heard[c.speaker] = (heard[c.speaker] ?? 0) + c.end - c.start;
    return mostHeard(heard);
  },

  voiceToPromote(paragraph: Paragraph, voices: MeetingVoices): string | null {
    return this.mainVoice(paragraph, voices.teacher);
  },
};

export const MyVoice = {
  key: "lecturenote.myVoice",
  threshold: 0.65,
  lead: 0.1,
  blendBar: 0.6,

  get print(): number[] | null {
    return prefs.get<number[]>(this.key) ?? null;
  },
  set print(value: number[] | null) {
    if (value) prefs.set(this.key, value);
    else prefs.remove(this.key);
  },

  cosine(a: number[], b: number[]): number {
    if (a.length !== b.length || !a.length) return 0;
    let dot = 0, na = 0, nb = 0;
    for (let i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    return na > 0 && nb > 0 ? dot / (Math.sqrt(na) * Math.sqrt(nb)) : 0;
  },

  unit(v: number[]): number[] {
    const n = Math.sqrt(v.reduce((a, x) => a + x * x, 0));
    return n > 0 ? v.map((x) => x / n) : v;
  },

  blended(old: number[] | null | undefined, next: number[]): number[] {
    if (!old || old.length !== next.length) return this.unit(next);
    const a = this.unit(old), b = this.unit(next);
    return this.unit(a.map((x, i) => 0.7 * x + 0.3 * b[i]));
  },

  blends(prints: Record<string, number[]>): Set<string> {
    const keys = Object.keys(prints);
    return new Set(keys.filter((key) => keys.filter((o) => o !== key && this.cosine(prints[o], prints[key]) >= this.blendBar).length >= 2));
  },

  match(mine: number[], prints: Record<string, number[]>, teacher: string): string | null {
    const blends = this.blends(prints);
    const scored = Object.entries(prints)
      .filter(([k]) => k !== teacher && !blends.has(k))
      .map(([k, p]) => [k, this.cosine(mine, p)] as const)
      .sort((a, b) => b[1] - a[1]);
    const best = scored[0];
    if (!best || best[1] < this.threshold) return null;
    if (scored.length > 1 && best[1] - scored[1][1] < this.lead) return null;
    return best[0];
  },
};
