// The fence and demo-page rules of Models/AnswerDocument.swift. The Markdown itself is drawn by
// the shared answer page (AnswerWeb/answer.js); these decide which html fences become live demos.

export type AnswerPiece =
  | { kind: "text"; body: string }
  | { kind: "code"; body: string }
  | { kind: "widget"; title: string; html: string }
  | { kind: "preparing" };

export type FenceRole = "code" | "widget" | "preparing" | "empty";

type Region = { kind: "text" | "fence"; info: string; body: string; closed: boolean };

const banned = ["<iframe", "<object", "<embed", "<link", "<base", "<form", "<img", "<image", "<video", "<audio", "<source", "<track",
  "<frame", "<frameset", "<applet", "<foreignobject", "javascript:", "@import", "formaction"];

function regions(source: string): Region[] {
  const lines = source.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
  const out: Region[] = [];
  let text: string[] = [];
  const flushText = () => {
    if (!text.length) return;
    out.push({ kind: "text", info: "", body: text.join("\n"), closed: true });
    text = [];
  };
  let index = 0;
  while (index < lines.length) {
    const info = openingInfo(lines[index]);
    if (info !== null) {
      flushText();
      index++;
      const body: string[] = [];
      let closed = false;
      while (index < lines.length) {
        if (isClosingFence(lines[index])) {
          closed = true;
          index++;
          break;
        }
        body.push(lines[index]);
        index++;
      }
      out.push({ kind: "fence", info, body: body.join("\n"), closed });
    } else {
      text.push(lines[index]);
      index++;
    }
  }
  flushText();
  return out;
}

function openingInfo(line: string): string | null {
  const spaces = line.length - line.replace(/^ +/, "").length;
  if (spaces > 3) return null;
  const trimmed = line.slice(spaces);
  if (!trimmed.startsWith("```")) return null;
  return trimmed.slice(3).trim();
}

function isClosingFence(line: string): boolean {
  const spaces = line.length - line.replace(/^ +/, "").length;
  if (spaces > 3) return false;
  const core = line.slice(spaces).trim();
  return core.length >= 3 && /^`+$/.test(core);
}

const isTagBoundary = (c: string) => c === ">" || c === "/" || /\s/.test(c);

function tagIndex(folded: string, tag: string, from = 0): number {
  const needle = `<${tag}`;
  let at = folded.indexOf(needle, from);
  while (at >= 0) {
    const after = at + needle.length;
    if (after >= folded.length || isTagBoundary(folded[after])) return at;
    at = folded.indexOf(needle, at + 1);
  }
  return -1;
}

const containsTag = (folded: string, tag: string) => tagIndex(folded, tag) >= 0;

function tagInner(html: string, tag: string): string | null {
  const folded = html.toLowerCase();
  const start = tagIndex(folded, tag);
  if (start < 0) return null;
  const gt = folded.indexOf(">", start + tag.length + 1);
  if (gt < 0) return null;
  const end = tagIndex(folded, `/${tag}`, gt + 1);
  return html.slice(gt + 1, end < 0 ? html.length : end);
}

function tagBlocks(html: string, tag: string): string[] {
  const result: string[] = [];
  const re = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}`, "gi");
  for (const m of html.matchAll(re)) result.push(m[1]);
  return result;
}

function inlineScriptBlocks(html: string): string[] {
  const result: string[] = [];
  for (const m of html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script/gi)) if (!/src/i.test(m[1])) result.push(m[2]);
  return result;
}

function scriptHasSource(folded: string) {
  return /<script\b[^>]*\ssrc\s*=/i.test(folded);
}

function hasExternalAddress(folded: string) {
  return [/\b(?:src|href|xlink:href)\s*=\s*['"]?\s*(?:https?:|\/\/)/i, /url\(\s*['"]?\s*(?:https?:|\/\/|data:)/i, /\bhref\s*=\s*['"](?!#)[^'"]+['"]/i, /\bhref\s*=\s*(?!['"#\s])\S+/i].some((r) => r.test(folded));
}

function hasBlockedInput(folded: string) {
  return /type\s*=\s*['"]?(?:file|password)\b/i.test(folded);
}

function hasUnsafeMeta(folded: string): boolean {
  for (const m of folded.matchAll(/<meta\b[^>]*>/gi)) {
    const tag = m[0];
    if (tag.includes("refresh")) return true;
    const contentType = tag.includes("content-type");
    if (tag.includes("http-equiv") && !contentType) return true;
    if (!tag.includes("charset") && !tag.includes("viewport") && !contentType) return true;
  }
  return false;
}

function passesSafety(html: string) {
  const folded = html.toLowerCase();
  if (banned.some((b) => folded.includes(b))) return false;
  return !(scriptHasSource(folded) || hasExternalAddress(folded) || hasBlockedInput(folded) || hasUnsafeMeta(folded));
}

function unwrapDocument(html: string): string {
  const folded = html.toLowerCase();
  const isDocument = folded.includes("<!doctype") || containsTag(folded, "html") || containsTag(folded, "head") || containsTag(folded, "body");
  if (!isDocument) return html;
  const head = tagInner(html, "head") ?? "";
  const assets = [...tagBlocks(head, "style").map((s) => `<style>${s}</style>`), ...inlineScriptBlocks(head).map((s) => `<script>${s}</script>`)].join("\n");
  const body = tagInner(html, "body");
  if (body === null) return html;
  return (assets + "\n" + body).trim();
}

function htmlTitle(info: string): string | null {
  const trimmed = info.trim();
  const lower = trimmed.toLowerCase();
  if (!(lower === "html" || lower.startsWith("html ") || lower.startsWith("html\t"))) return null;
  return trimmed.slice(4).trim();
}

function widgetTitle(info: string, body: string): string | null {
  const t = htmlTitle(info);
  if (t !== null) return t;
  if (info.trim()) return null;
  const folded = body.toLowerCase();
  if (!folded.includes("<!doctype") && !containsTag(folded, "html")) return null;
  return "";
}

function documentTitle(html: string): string | null {
  const inner = tagInner(html, "title")?.trim();
  return inner || null;
}

function isDisplayFence(info: string, body: string) {
  if (htmlTitle(info) !== null) return true;
  if (info.trim()) return false;
  const folded = body.toLowerCase();
  return folded.includes("<!doctype") || containsTag(folded, "html");
}

function finishedDocument(html: string) {
  const folded = html.toLowerCase();
  return containsTag(folded, "/body") || containsTag(folded, "/html");
}

export const AnswerDocument = {
  pieces(source: string, streaming = false): AnswerPiece[] {
    const result: AnswerPiece[] = [];
    for (const r of regions(source)) {
      if (r.kind === "text") {
        result.push({ kind: "text", body: r.body });
        continue;
      }
      if (streaming && !r.closed && isDisplayFence(r.info, r.body)) {
        result.push({ kind: "preparing" });
        continue;
      }
      if (!r.body.trim()) continue;
      const ready = r.closed || finishedDocument(r.body);
      const title = ready ? widgetTitle(r.info, r.body) : null;
      const fragment = title !== null ? this.widgetFragment(r.body) : null;
      if (title !== null && fragment) result.push({ kind: "widget", title: title || documentTitle(r.body) || "", html: fragment });
      else result.push({ kind: "code", body: r.body });
    }
    return result;
  },

  fenceRoles(source: string, streaming: boolean): FenceRole[] {
    return regions(source)
      .filter((r) => r.kind === "fence")
      .map((r) => {
        if (streaming && !r.closed && isDisplayFence(r.info, r.body)) return "preparing";
        if (!r.body.trim()) return "empty";
        const ready = r.closed || finishedDocument(r.body);
        if (ready && widgetTitle(r.info, r.body) !== null && this.widgetFragment(r.body)) return "widget";
        return "code";
      });
  },

  widgetFragment(html: string): string | null {
    if (!passesSafety(html)) return null;
    const fragment = unwrapDocument(html);
    return this.allowsWidget(fragment) ? fragment : null;
  },

  allowsWidget(html: string): boolean {
    const folded = html.toLowerCase();
    if (["body", "html", "head", "meta"].some((t) => containsTag(folded, t) || containsTag(folded, `/${t}`))) return false;
    if (folded.includes("<!doctype")) return false;
    if (banned.some((b) => folded.includes(b))) return false;
    return !(scriptHasSource(folded) || hasExternalAddress(folded) || hasBlockedInput(folded));
  },

  page(fragment: string, text: string, surface: string, accent: string): string {
    return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'none'; connect-src 'none'; frame-src 'none'; font-src 'none'; media-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
<style>
:root { color-scheme: light dark; --nomi-text: ${text}; --nomi-surface: ${surface}; --nomi-accent: ${accent}; }
html, body { margin: 0; background: var(--nomi-surface); color: var(--nomi-text); font: 15px "Segoe UI Variable Text", "Segoe UI", -apple-system, sans-serif; }
body { padding: 8px; box-sizing: border-box; }
button, input { font: inherit; color: inherit; }
</style>
</head>
<body>
${fragment}
<style>html, body { min-height: 0 !important; height: auto !important; }</style>
</body>
</html>`;
  },

  /** The widgets in order, each a finished sandbox page, for the answer page's demo cards. */
  widgets(source: string, streaming: boolean, colors: { text: string; surface: string; accent: string }): { title: string; page: string }[] {
    return this.pieces(source, streaming)
      .filter((p): p is Extract<AnswerPiece, { kind: "widget" }> => p.kind === "widget")
      .map((w) => ({ title: w.title, page: this.page(w.html, colors.text, colors.surface, colors.accent) }));
  },
};
