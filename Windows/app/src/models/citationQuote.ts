// Models/CitationQuote.swift
const enders = new Set(["。", "！", "？", "；", ".", "!", "?", ";", "\n"]);
const stopWords = new Set(["the", "and", "for", "that", "this", "with", "from", "are", "was", "were", "you", "your", "its", "it's",
  "but", "not", "can", "will", "has", "have", "had", "they", "them", "their", "there", "which", "what", "when",
  "about", "into", "than", "then", "also", "more", "most", "such", "very", "just", "only", "one", "all"]);
const isCJK = (c: string) => {
  const v = c.codePointAt(0) ?? 0;
  return (v >= 0x3040 && v <= 0x30ff) || (v >= 0x3400 && v <= 0x9fff) || (v >= 0xf900 && v <= 0xfaff);
};
const clipped = (text: string, limit: number) => ([...text].length > limit ? [...text].slice(0, limit).join("") + "…" : text);

export const CitationQuote = {
  excerptLimit: 520,
  quoteLimit: 320,

  sentences(text: string): string[] {
    const result: string[] = [];
    let current = "";
    for (const ch of text) {
      current += ch;
      if (enders.has(ch)) {
        const piece = current.trim();
        if (piece) result.push(piece);
        current = "";
      }
    }
    const rest = current.trim();
    if (rest) result.push(rest);
    return result;
  },

  /** The answer's own words just before a citation marker at `marker` (a string index). */
  claim(answer: string, marker: number): string {
    const head = [...answer.slice(0, marker)];
    let start = 0;
    let index = head.length;
    while (index > 0) {
      const previous = index - 1;
      if (enders.has(head[previous]) && head.length - previous > 3) {
        start = index;
        break;
      }
      index = previous;
    }
    return head.slice(start).join("").replace(/[[【]\d+[\]】]/g, " ").replace(/[*_`#>|]/g, " ").trim();
  },

  tokens(text: string): Set<string> {
    const result = new Set<string>();
    let word = "";
    let previousCJK: string | null = null;
    const flush = () => {
      if (word.length >= 2 && !stopWords.has(word)) result.add(word);
      word = "";
    };
    for (const ch of text.toLowerCase()) {
      if (isCJK(ch)) {
        flush();
        if (previousCJK) result.add(previousCJK + ch);
        previousCJK = ch;
      } else {
        previousCJK = null;
        if (/[\p{L}\p{N}]/u.test(ch)) word += ch;
        else flush();
      }
    }
    flush();
    return result;
  },

  pick(body: string, claim: string): { quote: string; excerpt: string } {
    const parts = this.sentences(body);
    if (!parts.length) return { quote: "", excerpt: "" };
    const wanted = this.tokens(claim);
    let best = 0;
    let bestScore = 0;
    parts.forEach((sentence, index) => {
      const have = this.tokens(sentence);
      if (!have.size) return;
      let shared = 0;
      for (const t of have) if (wanted.has(t)) shared++;
      const score = shared / Math.sqrt(have.size);
      if (score > bestScore) {
        bestScore = score;
        best = index;
      }
    });
    let quote = parts[best];
    let last = best;
    if ([...quote].length < 40 && best + 1 < parts.length) {
      quote += " " + parts[best + 1];
      last = best + 1;
    }
    quote = clipped(quote, this.quoteLimit);
    let excerpt = quote;
    if (best > 0) excerpt = parts[best - 1] + " " + excerpt;
    if (last + 1 < parts.length) excerpt += " " + parts[last + 1];
    return { quote, excerpt: clipped(excerpt, this.excerptLimit) };
  },

  clockSeconds(detail: string): number | null {
    const matches = [...detail.matchAll(/(\d{1,2}):(\d{2})(?::(\d{2}))?/g)];
    const m = matches.at(-1);
    if (!m) return null;
    const first = Number(m[1]), second = Number(m[2]);
    if (m[3] !== undefined) return first * 3600 + second * 60 + Number(m[3]);
    return first * 60 + second;
  },

  pageNumber(detail: string): number | null {
    const zh = detail.match(/第\s*(\d+)\s*[页张]/);
    if (zh) return Number(zh[1]);
    const en = detail.match(/(?:page|p\.|slide)\s*(\d+)/i);
    return en ? Number(en[1]) : null;
  },
};
