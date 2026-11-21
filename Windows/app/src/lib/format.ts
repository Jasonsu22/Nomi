// Small formatting helpers shared by the pages.
import type { Paragraph, VoiceName } from "./api";

/** 1:05, or 1:11:45 past an hour. */
export function clock(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const r = s % 60;
  const two = (n: number) => String(n).padStart(2, "0");
  return h > 0 ? `${h}:${two(m)}:${two(r)}` : `${m}:${two(r)}`;
}

export function bytes(n: number): string {
  if (n >= 1e9) return `${(n / 1e9).toFixed(2)} GB`;
  if (n >= 1e6) return `${Math.round(n / 1e6)} MB`;
  return `${Math.round(n / 1e3)} KB`;
}

/** Dates are stored as seconds since 2001-01-01, as Swift writes them. */
export function fromReference(seconds: number): Date {
  return new Date((seconds + 978_307_200) * 1000);
}

function usesSpaces(language: string): boolean {
  const code = language.toLowerCase();
  return !(code === "none" || code.startsWith("zh") || code.startsWith("ja"));
}

function isCJK(ch: string): boolean {
  const c = ch.codePointAt(0) ?? 0;
  return (c >= 0x3000 && c <= 0x30ff) || (c >= 0x3400 && c <= 0x9fff) || (c >= 0xf900 && c <= 0xfaff) || (c >= 0xff00 && c <= 0xffef) || (c >= 0x20000 && c <= 0x323af);
}

/** Joins a paragraph's pieces the way the Mac does (transcript.rs `join`). */
export function join(parts: string[], language: string): string {
  const pieces = parts.map((p) => p.trim()).filter(Boolean);
  if (language === "auto") {
    return pieces.reduce((out, piece) => {
      const last = out.at(-1);
      const first = piece[0];
      const space =
        !!last && !!first && !/\s/.test(last) && !/\s/.test(first) && !isCJK(last) && !isCJK(first) && !",.!?;:)]}".includes(first) && !"([{\"".includes(last);
      return out + (space ? " " : "") + piece;
    }, "");
  }
  return usesSpaces(language) ? pieces.join(" ") : pieces.join("");
}

export function paragraphText(p: Paragraph, language: string, field: "source" | "translation"): string {
  return join(p.commits.map((c) => c[field]), field === "source" ? p.sourceLanguage ?? language : language);
}

export function voiceLabel(name: VoiceName | undefined, t: (k: string, ...a: (string | number)[]) => string): string {
  if (!name) return "";
  switch (name.kind) {
    case "named":
      return name.name;
    case "me":
      return t("我");
    case "several":
      return t("多人");
    case "number":
      return t("说话人 %d", name.number);
  }
}

/** A steady color per speaker number, from Nomi's palette. */
export function voiceColor(name: VoiceName | undefined): string {
  const palette = ["#20b68a", "#3b82c4", "#c4793b", "#8a5cc4", "#c43b6e", "#3bb0c4", "#7a8a2b"];
  if (!name) return "var(--text-2)";
  if (name.kind === "me") return "#3b82c4";
  if (name.kind === "several") return "var(--text-2)";
  if (name.kind === "number") return palette[(name.number - 1) % palette.length];
  let hash = 0;
  for (const ch of name.name) hash = (hash * 31 + (ch.codePointAt(0) ?? 0)) >>> 0;
  return palette[hash % palette.length];
}
