// Live/RepeatCleanup.swift
import type { Paragraph } from "./transcript";

const isCJK = (c: string) => {
  const v = c.codePointAt(0) ?? 0;
  return (v >= 0x3040 && v <= 0x30ff) || (v >= 0x3400 && v <= 0x9fff) || (v >= 0xac00 && v <= 0xd7af) || (v >= 0xf900 && v <= 0xfaff) || (v >= 0x20000 && v <= 0x323af);
};
const isWordCharacter = (c: string) => /[\p{L}\p{N}]/u.test(c) || c === "'" || c === "’";

type Unit = { text: string; key: string };

function units(text: string): Unit[] {
  const result: Unit[] = [];
  const chars = [...text];
  let start = 0;
  let inCore = false;
  let coreDone = false;
  let key = "";
  chars.forEach((c, index) => {
    const word = isWordCharacter(c);
    const lastKey = [...key].at(-1);
    const startsNew = word && (coreDone || (inCore && (isCJK(c) || (lastKey !== undefined && isCJK(lastKey)))));
    if (startsNew && index > start) {
      result.push({ text: chars.slice(start, index).join(""), key });
      key = "";
      start = index;
      coreDone = false;
    }
    if (word) {
      inCore = true;
      key += c.toLowerCase();
    } else if (inCore) {
      coreDone = true;
    }
  });
  if (start < chars.length) result.push({ text: chars.slice(start).join(""), key });
  return result;
}

export const RepeatCleanup = {
  longestPhrase: 12,
  allowedSameLines: 3,
  shortLineCharacters: 24,

  isLoop(phraseUnits: number, count: number) {
    return phraseUnits === 1 ? count >= 8 : count >= 4 && count * phraseUnits >= 12;
  },

  collapse(text: string): string {
    const u = units(text);
    const same = (a: number, b: number, length: number) => {
      for (let k = 0; k < length; k++) if (!u[a + k].key || u[a + k].key !== u[b + k].key) return false;
      return true;
    };
    let kept = "";
    let changed = false;
    let index = 0;
    while (index < u.length) {
      let best: { length: number; count: number } | null = null;
      for (let length = 1; length <= this.longestPhrase; length++) {
        if (index + length * 2 > u.length) break;
        let count = 1;
        while (index + (count + 1) * length <= u.length && same(index, index + count * length, length)) count++;
        if (this.isLoop(length, count) && count * length > (best ? best.length * best.count : 0)) best = { length, count };
      }
      if (best) {
        for (let k = index; k < index + best.length; k++) kept += u[k].text;
        index += best.length * best.count;
        changed = true;
      } else {
        kept += u[index].text;
        index++;
      }
    }
    return changed ? kept.replace(/\s+$/u, "") : text;
  },

  cleaned(paragraphs: Paragraph[]): Paragraph[] | null {
    let changed = false;
    let lastKey = "";
    let sameCount = 0;
    const lineKey = (t: string) => [...t].filter((c) => /[\p{L}\p{N}]/u.test(c)).join("").toLowerCase();
    const result = paragraphs.map((p) => ({
      ...p,
      commits: p.commits.flatMap((commit) => {
        let c = commit;
        const source = this.collapse(c.source);
        if (source !== c.source) {
          c = { ...c, source, translation: this.collapse(c.translation) };
          changed = true;
        }
        const key = lineKey(source);
        if (!key) return [c];
        if (key === lastKey && [...key].length <= this.shortLineCharacters) sameCount++;
        else {
          lastKey = key;
          sameCount = 1;
        }
        if (sameCount > this.allowedSameLines) {
          changed = true;
          return [];
        }
        return [c];
      }),
    }));
    return changed ? result.filter((p) => p.commits.length || p.tail) : null;
  },
};
