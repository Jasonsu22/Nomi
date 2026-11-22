// Models/SourceText.swift: which files Nomi reads, and their text as passages. The reading itself
// is in Rust (document_segments); the passage rules and wording are the Mac's.
import { tr, trf } from "../i18n";
import { documents, paths } from "../platform";
import type { ContextBlock } from "./contextBlock";

const plainExtensions = new Set(["txt", "text", "md", "markdown", "csv", "tsv", "json", "xml", "yaml", "yml", "tex", "bib", "srt", "vtt", "log",
  "py", "swift", "js", "mjs", "ts", "tsx", "jsx", "java", "kt", "c", "cc", "cpp", "h", "hpp", "m", "mm", "cs",
  "go", "rs", "rb", "php", "sh", "zsh", "sql", "r", "scala", "lua", "css", "scss", "ipynb"]);
/** The Mac reads .doc and .rtfd through macOS; Windows has no reader for those, so they are turned away. */
const documentExtensions = new Set(["docx", "rtf", "odt"]);
const pageExtensions = new Set(["html", "htm", "xhtml"]);
const imageExtensions = new Set(["png", "jpg", "jpeg", "heic", "gif", "webp", "tif", "tiff", "bmp"]);
const unreadableExtensions = new Set(["key", "pages", "numbers", "ppt", "xls", "doc", "rtfd", "webarchive"]);

export const SourceText = {
  plainExtensions,
  documentExtensions,
  pageExtensions,
  imageExtensions,
  unreadableExtensions,
  passageLength: 4000,
  passageLimit: 300,
  pictureLimit: 40,

  get readableExtensions(): Set<string> {
    return new Set([...plainExtensions, ...documentExtensions, ...pageExtensions, ...imageExtensions, "pdf", "pptx", "xlsx", "epub"]);
  },

  canRead(path: string): boolean {
    return this.readableExtensions.has(paths.ext(path));
  },

  refusal(path: string): string {
    const ext = paths.ext(path);
    if (unreadableExtensions.has(ext)) return trf("Nomi 读不了 .%@ 文件，请先导出成 PDF 或新版 Office 格式。", ext);
    return tr("Nomi 还读不了这种文件。");
  },

  passages(text: string): string[] {
    const result: string[] = [];
    let current = "";
    const len = (s: string) => [...s].length;
    for (const paragraph of text.split("\n")) {
      if (len(current) + len(paragraph) + 1 > this.passageLength && current) {
        result.push(current);
        current = "";
        if (result.length >= this.passageLimit) return result;
      }
      if (len(paragraph) > this.passageLength) {
        let rest = [...paragraph];
        while (rest.length > this.passageLength) {
          result.push(rest.slice(0, this.passageLength).join(""));
          rest = rest.slice(this.passageLength);
          if (result.length >= this.passageLimit) return result;
        }
        current = rest.join("");
      } else {
        current += current ? "\n" + paragraph : paragraph;
      }
    }
    const tail = current.trim();
    if (tail && result.length < this.passageLimit) result.push(tail);
    return result;
  },

  chunk(text: string, title: string, detail: string, sourceID: string | null): ContextBlock[] {
    const trimmed = text.trim();
    if (!trimmed) return [];
    const parts = this.passages(trimmed);
    if (parts.length === 1) return [{ title, detail, body: parts[0], sourceID }];
    return parts.map((body, index) => {
      const part = trf("第 %d 部分", index + 1);
      return { title, detail: detail ? `${detail} · ${part}` : part, body, sourceID };
    });
  },

  async blocks(path: string, title: string, sourceID: string | null): Promise<ContextBlock[]> {
    let segments;
    try {
      segments = await documents.segments(path);
    } catch {
      return [];
    }
    const blocks: ContextBlock[] = [];
    let pictures = 0;
    for (const s of segments) {
      const text = s.text.trim();
      if (!text) continue;
      switch (s.kind) {
        case "text":
          blocks.push(...this.chunk(text, title, "", sourceID));
          break;
        case "page":
          blocks.push({ title, detail: trf("第 %d 页", s.index), body: [...text].slice(0, 4000).join(""), sourceID, page: s.index });
          break;
        case "slide":
          blocks.push({ title, detail: trf("第 %d 页", s.index), body: [...text].slice(0, this.passageLength).join(""), sourceID, page: s.index });
          break;
        case "sheet":
          blocks.push(...this.chunk(text, title, s.name || trf("工作表 %d", s.index), sourceID));
          break;
        case "chapter":
          blocks.push(...this.chunk(text, title, trf("第 %d 章", s.index), sourceID));
          break;
        case "picture":
          if (pictures++ < this.pictureLimit) blocks.push(...this.chunk(text, title, trf("第 %d 张图片", s.index), sourceID));
          break;
      }
      if (blocks.length >= this.passageLimit) break;
    }
    return blocks.slice(0, this.passageLimit);
  },
};

/** Extracted text of imported files, kept until the file changes. */
const cache = new Map<string, { modified: number; blocks: ContextBlock[] }>();
export const SourceTextCache = {
  async blocks(source: { id: string; title: string; fileModifiedAt: number }, path: string): Promise<ContextBlock[]> {
    const hit = cache.get(source.id);
    if (hit && hit.modified === source.fileModifiedAt) return hit.blocks;
    const blocks = await SourceText.blocks(path, source.title, source.id);
    cache.set(source.id, { modified: source.fileModifiedAt, blocks });
    return blocks;
  },
  keepOnly(ids: Set<string>) {
    for (const key of [...cache.keys()]) if (!ids.has(key)) cache.delete(key);
  },
};
