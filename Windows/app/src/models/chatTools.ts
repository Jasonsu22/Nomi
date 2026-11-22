// Models/ChatTools.swift
export const ChatTools = {
  webSearch: "web_search",
  searchLibrary: "search_library",
  createDemo: "create_demo",
  lookups: new Set(["web_search", "search_library"]),

  parse(raw: string, streaming: boolean, stopAtSearch = false): { visible: string; calls: { name: string; body: string }[] } {
    let visible = "";
    const calls: { name: string; body: string }[] = [];
    let searching = false;
    let index = 0;
    const lower = raw.toLowerCase();
    while (index < raw.length) {
      const start = lower.indexOf("<tool", index);
      if (start < 0) {
        if (!searching) visible += raw.slice(index);
        break;
      }
      if (!searching) visible += raw.slice(index, start);
      const openEnd = raw.indexOf(">", start + 5);
      if (openEnd < 0) {
        if (!streaming && !searching) visible += raw.slice(start);
        break;
      }
      const open = raw.slice(start, openEnd + 1);
      const name = (attribute("name", open) ?? "").toLowerCase();
      const bodyStart = openEnd + 1;
      let bodyEnd: number;
      const close = lower.indexOf("</tool>", bodyStart);
      if (close >= 0) {
        bodyEnd = close;
        index = close + "</tool>".length;
      } else {
        if (streaming) break;
        const ends = ["```", "\n\n", "<tool"].map((m) => lower.indexOf(m, bodyStart)).filter((i) => i >= 0);
        bodyEnd = ends.length ? Math.min(...ends) : raw.length;
        index = bodyEnd;
      }
      const body = raw.slice(bodyStart, bodyEnd).trim();
      if (name && body && (!searching || this.lookups.has(name))) calls.push({ name, body });
      if (stopAtSearch && this.lookups.has(name) && body) searching = true;
    }
    if (streaming) visible = droppingOpenTag(visible);
    return { visible, calls };
  },
};

function attribute(name: string, tag: string): string | null {
  const folded = tag.toLowerCase();
  const found = folded.indexOf(name.toLowerCase());
  if (found < 0) return null;
  let index = found + name.length;
  while (index < tag.length && (/\s/.test(tag[index]) || tag[index] === "=")) index++;
  if (index >= tag.length) return null;
  const quote = tag[index];
  if (quote !== '"' && quote !== "'") return null;
  const end = tag.indexOf(quote, index + 1);
  if (end < 0) return null;
  const value = tag.slice(index + 1, end).trim();
  return value || null;
}

function droppingOpenTag(text: string): string {
  const marker = "<tool";
  const lower = text.toLowerCase();
  for (let count = marker.length; count >= 1; count--) if (lower.endsWith(marker.slice(0, count))) return text.slice(0, text.length - count);
  return text;
}
