// Models/TranscriptionTopic.swift
import { tr } from "../i18n";

const isHan = (c: string) => [...c].every((ch) => {
  const v = ch.codePointAt(0) ?? 0;
  return v >= 0x4e00 && v <= 0x9fff;
});
const functionHan = new Set([..."的了是在和与及或等这那一个我你他她它们也就都而被把从对为以之其"]);
const stopWords = new Set(["this", "that", "with", "from", "have", "they", "will", "your", "what", "when", "which", "there",
  "their", "about", "would", "these", "those", "into", "than", "then", "them", "were", "been", "more",
  "some", "such", "only", "also", "each", "other", "many", "most", "much", "very", "just", "like",
  "over", "here", "where", "after", "before", "because", "between", "through", "while", "does", "make",
  "used", "using", "use", "example", "examples", "page", "slide", "slides", "figure", "table", "note",
  "chapter", "section", "lecture", "week", "today", "question", "questions", "answer", "first", "second",
  "next", "last", "same", "different", "know", "need", "want", "show", "shows", "shown", "good", "well",
  "http", "https", "www", "com", "html", "should", "could", "must", "can't", "don't", "it's", "how"]);

export const TranscriptionTopic = {
  maxTerms: 30,

  text(title: string, course: string | null | undefined, terms: string[]): string {
    const parts: string[] = [];
    const t = title.trim();
    if (t && t !== tr("未命名会议")) parts.push(`Lecture: ${t}.`);
    const c = course?.trim();
    if (c) parts.push(`Course: ${c}.`);
    if (terms.length) parts.push(`Terms: ${terms.join(", ")}.`);
    return parts.join(" ");
  },

  terms(text: string, limit = 30): string[] {
    const counts = new Map<string, number>();
    const shown = new Map<string, string>();
    for (const match of text.matchAll(/\b[A-Z]{2,}[0-9]*\b|[A-Za-z][A-Za-z-]{3,}/g)) {
      const word = match[0].replace(/^-+|-+$/g, "");
      const key = word.toLowerCase();
      const acronym = word.length >= 2 && word === word.toUpperCase();
      if (!(acronym || key.length >= 4) || stopWords.has(key)) continue;
      counts.set(key, (counts.get(key) ?? 0) + 1);
      if (!shown.has(key) || word === word.toUpperCase()) shown.set(key, word);
    }
    for (const run of text.split(/[^一-鿿]+/)) {
      const chars = [...run];
      if (chars.length < 2) continue;
      for (let size = 2; size <= 4; size++) {
        for (let start = 0; start + size <= chars.length; start++) {
          const term = chars.slice(start, start + size).join("");
          if ([...term].some((c) => functionHan.has(c))) continue;
          counts.set(term, (counts.get(term) ?? 0) + 1);
          shown.set(term, term);
        }
      }
    }
    const recurring = [...counts].filter(([term, count]) => count >= (isHan([...term][0] ?? "") ? 3 : 2));
    const ranked = recurring.sort((a, b) => (a[1] !== b[1] ? b[1] - a[1] : a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0)).map(([k]) => k);
    const kept = ranked.filter((term) => !ranked.some((other) => other !== term && other.includes(term) && counts.get(other) === counts.get(term)));
    return kept.slice(0, limit).map((k) => shown.get(k)!).filter(Boolean);
  },
};
