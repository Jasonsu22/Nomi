// Live/Transcript.swift: finished lines (commits) grouped into paragraphs, and the grey line still
// being spoken (tail). Same rules and JSON as the Mac.

export type Commit = {
  id: number;
  source: string;
  translation: string;
  start: number;
  end: number;
  /** Whose voice this is ("S1", "R2-S1"…); absent when unchecked, too short, or mixed. */
  speaker?: string | null;
};

export type Paragraph = {
  id: number;
  openedAt: number;
  commits: Commit[];
  tail: string;
  closed: boolean;
  sourceLanguage?: string | null;
  targetLanguage?: string | null;
};

export const automatic = "auto";

export const TranscriptText = {
  usesSpaces(language: string): boolean {
    const code = language.toLowerCase();
    return !(code === "none" || code.startsWith("zh") || code.startsWith("ja"));
  },

  isCJK(ch: string): boolean {
    for (const c of ch) {
      const v = c.codePointAt(0) ?? 0;
      if ((v >= 0x3000 && v <= 0x30ff) || (v >= 0x3400 && v <= 0x9fff) || (v >= 0xf900 && v <= 0xfaff) || (v >= 0xff00 && v <= 0xffef) || (v >= 0x20000 && v <= 0x323af)) return true;
    }
    return false;
  },

  needsSeparator(left: string, right: string, language: string): boolean {
    const last = [...left].at(-1);
    const first = [...right][0];
    if (!last || !first || !this.usesSpaces(language)) return false;
    if (language !== automatic) return true;
    return !/\s/.test(last) && !/\s/.test(first) && !this.isCJK(last) && !this.isCJK(first) && !",.!?;:)]}".includes(first) && !"([{\"".includes(last);
  },

  join(parts: string[], language: string): string {
    const pieces = parts.map((p) => p.trim()).filter((p) => p.length > 0);
    if (language === automatic) {
      return pieces.reduce((result, piece) => result + (this.needsSeparator(result, piece, language) ? " " : "") + piece, "");
    }
    if (!this.usesSpaces(language)) return pieces.join("");
    return pieces.join(" ");
  },
};

export function renderedSource(p: Paragraph, language: string): string {
  return TranscriptText.join(p.commits.map((c) => c.source), p.sourceLanguage ?? language);
}

export function renderedTranslation(p: Paragraph, language: string): string {
  return TranscriptText.join(p.commits.map((c) => c.translation), p.targetLanguage ?? language);
}

export const isLiveParagraph = (p: Paragraph) => !p.closed;

export type TranscriptChange = "tailReplaced" | "paragraphOpened" | "committed";

export class TranscriptBuilder {
  static maxCharacters = 200;
  static spacedCharacterLimit = 600;
  static pauseGap = 2;

  sourceLanguage: string;
  paragraphs: Paragraph[];
  private nextParagraphID: number;

  constructor(sourceLanguage = "zh", paragraphs: Paragraph[] = []) {
    this.sourceLanguage = sourceLanguage;
    this.paragraphs = paragraphs.map((p) => ({ ...p, closed: true, tail: "" }));
    this.nextParagraphID = Math.max(0, ...paragraphs.map((p) => p.id)) + 1;
  }

  clone(): TranscriptBuilder {
    const copy = new TranscriptBuilder(this.sourceLanguage);
    copy.paragraphs = this.paragraphs.map((p) => ({ ...p, commits: [...p.commits] }));
    copy.nextParagraphID = this.nextParagraphID;
    return copy;
  }

  applyTail(text: string, start: number): TranscriptChange {
    const before = this.paragraphs.length;
    const index = this.indexForIncoming(start);
    this.paragraphs[index] = { ...this.paragraphs[index], tail: text };
    return this.paragraphs.length > before ? "paragraphOpened" : "tailReplaced";
  }

  applyCommit(commit: Commit, tail: string): TranscriptChange {
    const index = this.indexForIncoming(commit.start);
    const p = { ...this.paragraphs[index], commits: [...this.paragraphs[index].commits, commit] };
    this.paragraphs[index] = p;
    if (this.shouldClose(p)) {
      this.paragraphs[index] = { ...p, tail: "", closed: true };
      if (tail) {
        const next = this.openParagraph(commit.end);
        this.paragraphs[next] = { ...this.paragraphs[next], tail };
      }
    } else {
      this.paragraphs[index] = { ...p, tail };
    }
    return "committed";
  }

  flush(end: number) {
    const index = this.paragraphs.length - 1;
    if (index >= 0 && this.paragraphs[index].tail) {
      const p = this.paragraphs[index];
      const tail = p.tail;
      const start = p.commits.at(-1)?.end ?? p.openedAt;
      const id = Math.max(0, ...this.paragraphs.flatMap((x) => x.commits.map((c) => c.id))) + 1;
      this.applyCommit({ id, source: tail, translation: "", start, end: Math.max(end, start) }, "");
    }
    this.paragraphs = this.paragraphs.map((p) => ({ ...p, closed: true, tail: "" }));
  }

  private indexForIncoming(start: number): number {
    const last = this.paragraphs.length - 1;
    if (last < 0) return this.openParagraph(start);
    const p = this.paragraphs[last];
    if (p.closed) return this.openParagraph(start);
    const anchor = p.commits.at(-1)?.end ?? p.openedAt;
    const hasContent = p.commits.length > 0 || p.tail.length > 0;
    if (hasContent && start - anchor > TranscriptBuilder.pauseGap) {
      // The grey line belonged to speech now finished in the new paragraph; kept, it shows twice.
      this.paragraphs[last] = { ...p, closed: true, tail: "" };
      return this.openParagraph(start);
    }
    return last;
  }

  private openParagraph(start: number): number {
    this.paragraphs.push({ id: this.nextParagraphID, openedAt: start, commits: [], tail: "", closed: false, sourceLanguage: this.sourceLanguage });
    this.nextParagraphID += 1;
    return this.paragraphs.length - 1;
  }

  private shouldClose(p: Paragraph): boolean {
    const text = renderedSource(p, this.sourceLanguage);
    const spaced = TranscriptText.usesSpaces(this.sourceLanguage);
    const limit = spaced ? TranscriptBuilder.spacedCharacterLimit : TranscriptBuilder.maxCharacters;
    const chars = [...text];
    const last = chars.at(-1);
    if (chars.length < limit || !last) return false;
    const endings = this.sourceLanguage === automatic ? "。！？.!?" : spaced ? ".!?" : "。！？!?";
    return endings.includes(last);
  }
}

/** The transcript of the recording that is running, on the meeting's clock. */
export class LiveTranscript {
  paragraphs: Paragraph[] = [];
  onCommitted?: () => void;
  onChange?: (paragraphs: Paragraph[]) => void;
  private builder = new TranscriptBuilder();
  private sourceLanguage = "zh";
  private timeOffset = 0;
  private commitIDOffset = 0;

  setSourceLanguage(code: string) {
    this.sourceLanguage = code;
    this.builder.sourceLanguage = code;
  }

  reset(existing: Paragraph[] = [], offset = 0) {
    this.timeOffset = Math.max(0, offset);
    this.commitIDOffset = Math.max(0, ...existing.flatMap((p) => p.commits.map((c) => c.id)));
    this.builder = new TranscriptBuilder(this.sourceLanguage, existing);
    this.publish();
  }

  applyTail(text: string, start: number) {
    this.builder.applyTail(text, start + this.timeOffset);
    this.publish();
  }

  applyCommit(commit: Commit, tail: string) {
    this.builder.applyCommit({ ...commit, id: commit.id + this.commitIDOffset, start: commit.start + this.timeOffset, end: commit.end + this.timeOffset }, tail);
    this.publish();
    this.onCommitted?.();
  }

  flush(end: number) {
    this.builder.flush(end);
    this.publish();
  }

  snapshot(end: number): Paragraph[] {
    const saved = this.builder.clone();
    saved.flush(end);
    return saved.paragraphs;
  }

  /** Labels from the live speaker model, applied in place. */
  replaceParagraphs(paragraphs: Paragraph[]) {
    this.builder.paragraphs = paragraphs;
    this.publish();
  }

  private publish() {
    this.paragraphs = [...this.builder.paragraphs];
    this.onChange?.(this.paragraphs);
  }
}
