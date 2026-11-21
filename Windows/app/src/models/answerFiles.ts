// Models/AnswerFiles.swift (ChatFiles): each demo in an answer saved as a standalone page, so it can
// be opened, saved and revealed like a file. Same folder layout as the Mac: chat-files/<hash>/<name>.
import { fs, paths } from "../platform";
import { AnswerDocument, type AnswerPiece } from "./answerDocument";

export type AnswerExport = { named: Record<string, string>; widgets: string[] };

const stored = new Set<string>();
const cache = new Map<string, AnswerExport>();

function isHTMLName(name: string) {
  if (!name || [...name].length > 80 || name.includes("/") || name.includes("\\")) return false;
  const ext = paths.ext(name);
  return (ext === "html" || ext === "htm") && name.slice(0, name.lastIndexOf(".")).length > 0;
}

function inlineHTMLNames(pieces: AnswerPiece[]): string[] {
  const names: string[] = [];
  for (const piece of pieces) {
    if (piece.kind !== "text") continue;
    for (const match of piece.body.matchAll(/`([^`\n]+)`/g)) {
      const code = match[1].trim();
      if (isHTMLName(code) && !names.includes(code)) names.push(code);
    }
  }
  return names;
}

const fallbackName = (title: string, index: number) => (title.trim() ? title.trim() + ".html" : index === 0 ? "figure.html" : `figure-${index + 1}.html`);

function sanitized(name: string) {
  const base = name.split(/[\\/]/).pop()!.trim();
  let text = [...base].filter((c) => c === "-" || c === "_" || c === "." || /[\p{L}\p{N}]/u.test(c)).join("");
  while (text.startsWith(".")) text = text.slice(1);
  return !text || !paths.ext(text) ? "figure.html" : text;
}

const escape = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const standalonePage = (fragment: string, title: string) => `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)}</title>
</head>
<body>
${fragment}
</body>
</html>`;

async function digest(text: string) {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return [...bytes.slice(0, 8)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function store(name: string, contents: string, directory: string): Promise<string | null> {
  const folder = paths.join(directory, await digest(contents));
  const file = paths.join(folder, sanitized(name));
  if (stored.has(file)) return file;
  try {
    if (!(await fs.exists(file))) {
      await fs.mkdir(folder);
      await fs.writeText(file, contents);
    }
    stored.add(file);
    return file;
  } catch {
    return null;
  }
}

const chatFilesDirectory = () => paths.join(paths.root, "chat-files");

export const ChatFiles = {
  get directory() {
    return chatFilesDirectory();
  },

  /** Saves the answer's demos; cached by the answer's text. */
  async export(source: string, directory: string = chatFilesDirectory()): Promise<AnswerExport> {
    if (!source.includes("```")) return { named: {}, widgets: [] };
    const hit = cache.get(source);
    if (hit) return hit;
    const pieces = AnswerDocument.pieces(source);
    const html = pieces.filter((p): p is Extract<AnswerPiece, { kind: "widget" }> => p.kind === "widget");
    const result: AnswerExport = { named: {}, widgets: [] };
    if (!html.length) return result;
    const names = inlineHTMLNames(pieces);
    for (const [index, widget] of html.entries()) {
      const name = index < names.length ? names[index] : fallbackName(widget.title, index);
      const file = await store(name, standalonePage(widget.html, widget.title), directory);
      if (!file) continue;
      result.widgets.push(file);
      if (index < names.length) result.named[names[index]] = file;
    }
    cache.set(source, result);
    if (cache.size > 300) cache.delete(cache.keys().next().value!);
    return result;
  },

  symbol(path: string) {
    const ext = paths.ext(path);
    if (["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff"].includes(ext)) return "photo";
    if (ext === "pdf") return "doc.richtext";
    if (ext === "html" || ext === "htm") return "chevron.left.forwardslash.chevron.right";
    return "doc";
  },
};
