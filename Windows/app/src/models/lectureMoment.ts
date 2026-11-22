// Models/LectureMoment.swift: the exact spoken sentences a lecture citation points to.
import { CitationQuote } from "./citationQuote";
import { renderedSource, renderedTranslation, TranscriptText, type Paragraph } from "./transcript";

export type LectureMoment = {
  paragraph: number;
  commits: [number, number];
  at: number;
  end: number;
  source: string;
  translation: string;
};

type Piece = { commit: number; range: [number, number]; text: string; start: number; end: number };
const enders = new Set(["。", "！", "？", "；", ".", "!", "?", ";", "\n"]);

function score(text: string, wanted: Set<string>): number {
  const have = CitationQuote.tokens(text);
  if (!have.size) return 0;
  let shared = 0;
  for (const t of have) if (wanted.has(t)) shared++;
  return shared / Math.sqrt(have.size);
}

export const LectureMoments = {
  chunkReach: 1000,

  pieces(text: string, commit: number, start: number, end: number): Piece[] {
    const chars = [...text];
    if (!chars.length) return [];
    const total = chars.length, span = Math.max(0, end - start);
    const result: Piece[] = [];
    let from = 0;
    const close = (upTo: number) => {
      let lower = from, upper = upTo;
      while (lower < upper && /\s/.test(chars[lower])) lower++;
      while (upper > lower && /\s/.test(chars[upper - 1])) upper--;
      if (upper <= lower) return;
      result.push({ commit, range: [lower, upper], text: chars.slice(lower, upper).join(""), start: start + (span * lower) / total, end: start + (span * upper) / total });
    };
    chars.forEach((ch, index) => {
      if (!enders.has(ch)) return;
      if (ch === "." && index + 1 < chars.length && !/\s/.test(chars[index + 1])) return;
      close(index + 1);
      from = index + 1;
    });
    close(chars.length);
    return result;
  },

  locate(paragraphs: Paragraph[], near: number | null | undefined, needle: string, sourceLanguage = "en", targetLanguage = "zh"): LectureMoment | null {
    const wanted = CitationQuote.tokens(needle);
    if (!wanted.size || !paragraphs.length) return null;
    let window = paragraphs.map((_, i) => i);
    if (near !== null && near !== undefined) {
      let first = 0;
      paragraphs.forEach((p, i) => {
        if (p.openedAt <= near + 1.5) first = i;
      });
      let reach = 0;
      window = [];
      for (let i = first; i < paragraphs.length; i++) {
        window.push(i);
        reach += [...renderedSource(paragraphs[i], sourceLanguage)].length + [...renderedTranslation(paragraphs[i], targetLanguage)].length;
        if (reach >= this.chunkReach) break;
      }
    }
    let bestParagraph = -1;
    let bestRun: [number, number] = [0, 0];
    let bestScore = 0;
    for (const index of window) {
      const commits = paragraphs[index].commits;
      for (let start = 0; start < commits.length; start++) {
        for (let length = 1; length <= 3 && start + length <= commits.length; length++) {
          const run = commits.slice(start, start + length);
          const s = Math.max(score(run.map((c) => c.source).join(" "), wanted), score(run.map((c) => c.translation).join(" "), wanted));
          if (s > bestScore * (length > 1 ? 1.25 : 1)) {
            bestScore = s;
            bestParagraph = index;
            bestRun = [start, start + length];
          }
        }
      }
    }
    if (bestParagraph < 0) return null;
    const paragraph = paragraphs[bestParagraph];
    const range = (r: [number, number]) => Array.from({ length: r[1] - r[0] }, (_, k) => r[0] + k);
    const source = range(bestRun).flatMap((i) => this.pieces(paragraph.commits[i].source, i, paragraph.commits[i].start, paragraph.commits[i].end));
    const translated = range(bestRun).flatMap((i) => this.pieces(paragraph.commits[i].translation, i, paragraph.commits[i].start, paragraph.commits[i].end));
    const fromSource = bestSpan(source, wanted);
    const fromTranslation = bestSpan(translated, wanted);
    const useSource = fromSource.score >= fromTranslation.score;
    const picked = useSource ? fromSource.span : fromTranslation.span;
    const lead = useSource ? source : translated;
    const other = useSource ? translated : source;
    if (picked[1] <= picked[0]) return null;
    const from = lead[picked[0]].start, to = lead[picked[1] - 1].end;
    const matched = overlapping(other, from, to);
    const sourceSpan = useSource ? picked : matched;
    const translationSpan = useSource ? matched : picked;
    return {
      paragraph: bestParagraph,
      commits: bestRun,
      at: from,
      end: to,
      source: textOf(source, sourceSpan, paragraph, false, paragraph.sourceLanguage ?? sourceLanguage),
      translation: textOf(translated, translationSpan, paragraph, true, paragraph.targetLanguage ?? targetLanguage),
    };
  },
};

function bestSpan(pieces: Piece[], wanted: Set<string>): { span: [number, number]; score: number } {
  let best: [number, number] = [0, 0];
  let bestScore = 0;
  for (let start = 0; start < pieces.length; start++) {
    for (let length = 1; length <= 3 && start + length <= pieces.length; length++) {
      const s = score(pieces.slice(start, start + length).map((p) => p.text).join(" "), wanted);
      if (s > bestScore * (length > 1 ? 1.15 : 1)) {
        bestScore = s;
        best = [start, start + length];
      }
    }
  }
  return { span: best, score: bestScore };
}

function overlapping(pieces: Piece[], from: number, to: number): [number, number] {
  const inside = pieces.map((_, i) => i).filter((i) => {
    const middle = (pieces[i].start + pieces[i].end) / 2;
    return middle >= from - 0.01 && middle <= to + 0.01;
  });
  if (inside.length) return [inside[0], inside[inside.length - 1] + 1];
  const overlap = (p: Piece) => Math.max(0, Math.min(p.end, to) - Math.max(p.start, from));
  let best = -1;
  pieces.forEach((p, i) => {
    if (best < 0 || overlap(p) > overlap(pieces[best])) best = i;
  });
  if (best < 0 || overlap(pieces[best]) <= 0) return [0, 0];
  return [best, best + 1];
}

function textOf(pieces: Piece[], span: [number, number], paragraph: Paragraph, translation: boolean, language: string): string {
  if (span[1] <= span[0]) return "";
  const first = pieces[span[0]], last = pieces[span[1] - 1];
  const parts: string[] = [];
  for (let c = first.commit; c <= last.commit; c++) {
    const chars = [...(translation ? paragraph.commits[c].translation : paragraph.commits[c].source)];
    const lower = c === first.commit ? first.range[0] : 0;
    const upper = c === last.commit ? last.range[1] : chars.length;
    if (lower < upper) parts.push(chars.slice(lower, upper).join(""));
  }
  return TranscriptText.join(parts, language);
}
