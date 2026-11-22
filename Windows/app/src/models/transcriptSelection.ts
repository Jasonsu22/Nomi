// Models/TranscriptSelection.swift
import { LibrarySearch } from "./librarySearch";

const len = (s: string) => [...s].length;

export const TranscriptSelection = {
  pick(lines: string[], query: string, budget: number): string[] {
    if (this.size(lines) <= budget) return lines;
    const scores = LibrarySearch.relevance(lines, query);
    const chosen = new Set<number>();
    let used = 0;
    const take = (index: number): boolean => {
      if (index < 0 || index >= lines.length || chosen.has(index)) return true;
      const cost = len(lines[index]) + 1;
      if (used + cost > budget) return false;
      chosen.add(index);
      used += cost;
      return true;
    };
    if (scores.every((s) => s === 0)) {
      for (let i = 0; i < lines.length; i++) if (!take(i)) break;
    } else {
      const ranked = scores.map((_, i) => i).filter((i) => scores[i] > 0).sort((a, b) => (scores[a] !== scores[b] ? scores[b] - scores[a] : a - b));
      for (const i of ranked) {
        if (!take(i)) continue;
        take(i - 1);
        take(i + 1);
      }
    }
    return [...chosen].sort((a, b) => a - b).map((i) => lines[i]);
  },

  chunks(lines: string[], budget: number, maxChunks?: number): { chunks: string[][]; skipped: boolean } {
    const all: string[][] = [];
    let current: string[] = [];
    let used = 0;
    for (const line of lines) {
      const cost = len(line) + 1;
      if (current.length && used + cost > budget) {
        all.push(current);
        current = [];
        used = 0;
      }
      current.push(len(line) > budget ? [...line].slice(0, budget).join("") : line);
      used += Math.min(cost, budget);
    }
    if (current.length) all.push(current);
    if (!maxChunks || maxChunks <= 0 || all.length <= maxChunks) return { chunks: all, skipped: false };
    if (maxChunks <= 1) return { chunks: [all[0]], skipped: true };
    const picked = Array.from({ length: maxChunks }, (_, i) => all[Math.round((i * (all.length - 1)) / (maxChunks - 1))]);
    return { chunks: picked, skipped: true };
  },

  size: (lines: string[]) => lines.reduce((n, l) => n + len(l) + 1, 0),
};
