// Pages/AnswerBody.swift: one answer drawn by the shared answer page (public/answer/answer.html):
// Markdown through markdown-it, formulas through KaTeX, demo cards in sandboxed frames. The page is a
// same-origin frame; it reports its height and clicks through `frameElement.__nomi`.
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { tr, trf } from "../../i18n";
import { formatClock } from "../../support/format";
import { useDark } from "../../support/appearance";
import { AnswerDocument } from "../../models/answerDocument";
import { ChatFiles, type AnswerExport } from "../../models/answerFiles";
import { ChatContext } from "../../models/chatContext";
import { Citations, type ChatCitation } from "../../models/chatSession";
import { model, useModel } from "../../app";
import { CitationKind, type CitationDetails } from "../../app/citations";
import { shell } from "../../platform";
import { Menu, pointAnchor, type MenuEntry } from "../ui/controls";
import { CitationCard, CitationCardLayer } from "./CitationCard";

const heights = new Map<string, number>();
const fileScheme = "nomi-file:";
const fileURL = (path: string) => fileScheme + encodeURIComponent(path);

export const citationSourceKey = (c: ChatCitation) => (c.meetingID ? `meeting:${c.meetingID}` : c.sourceID ? `source:${c.sourceID}` : c.chatID ? `chat:${c.chatID}` : c.url ? `url:${c.url}` : `id:${c.id}`);

function chipKind(c: ChatCitation) {
  const kind = CitationKind.of(c);
  return { lecture: "lecture", summary: "summary", pdf: "doc", document: "doc", missing: "doc", slides: "slides", picture: "photo", web: "web", chat: "chat" }[kind];
}

function citationChips(citations: Map<number, ChatCitation>) {
  const meetings = new Set([...citations.values()].map((c) => c.meetingID).filter(Boolean));
  const oneMeeting = meetings.size === 1 && [...citations.values()].every((c) => c.meetingID);
  const chips: Record<string, { label: string; key: string; url: string; kind: string }> = {};
  for (const [number, c] of citations) {
    const label = Citations.inlineLabel(c);
    const url = Citations.inlineURL(c);
    if (!label || !url) continue;
    let moment = c.detail.trim();
    if (c.meetingID) {
      const d = model.citationDetails(c);
      const at = d.lineAt ?? d.at;
      if (d.kind === "lecture" && at != null) moment = moment.replace(/\d{1,2}:\d{2}(?::\d{2})?$/, formatClock(at));
    }
    chips[String(number)] = { label: oneMeeting && moment ? moment : label, key: citationSourceKey(c), url, kind: chipKind(c) };
  }
  return chips;
}

const host = (url: string) => {
  try {
    const h = new URL(url).hostname;
    return h.startsWith("www.") ? h.slice(4) : h;
  } catch {
    return "";
  }
};

function sourceRow(citations: Map<number, ChatCitation>) {
  const seen = new Set<string>();
  const row: { url: string; kind: string; label: string }[] = [];
  for (const number of [...citations.keys()].sort((a, b) => a - b)) {
    const c = citations.get(number)!;
    const url = Citations.inlineURL(c);
    if (!url) continue;
    const key = citationSourceKey(c);
    if (seen.has(key)) continue;
    seen.add(key);
    const kind = CitationKind.of(c);
    let label = c.title;
    if (kind === "chat") label = trf("对话 · %@", c.title);
    else if (kind === "web" || kind === "missing") label = host(url) || Citations.inlineLabel(c);
    row.push({ url, kind: kind === "summary" ? "lecture" : chipKind(c), label: label || Citations.inlineLabel(c) });
  }
  return row.length >= 2 ? row : [];
}

/** The menu for a file the answer wrote: open, reveal, save a copy, copy its path or contents. */
export function fileMenu(path: string): MenuEntry[] {
  return [
    { kind: "item", title: tr("打开文件"), onSelect: () => void shell.openPath(path) },
    { kind: "divider" },
    { kind: "item", title: tr("存储为…"), onSelect: () => void model.saveFileCopy(path) },
    { kind: "item", title: tr("拷贝路径"), onSelect: () => void navigator.clipboard.writeText(path) },
    { kind: "item", title: tr("拷贝文件内容"), onSelect: () => void model.copyFileContents(path) },
    { kind: "item", title: tr("在资源管理器中显示"), onSelect: () => void shell.reveal(path) },
  ];
}

type Hover = { url: string; label: string; rect: DOMRect };

export function AnswerBody({ source, streaming = false, citations = [], onOpenCitation }: { source: string; streaming?: boolean; citations?: ChatCitation[]; onOpenCitation?: (c: ChatCitation) => void }) {
  useModel();
  const dark = useDark();
  const frame = useRef<HTMLIFrameElement>(null);
  const [ready, setReady] = useState(false);
  const [height, setHeight] = useState(heights.get(source) ?? 22);
  const [exported, setExported] = useState<AnswerExport>({ named: {}, widgets: [] });
  const [hover, setHover] = useState<Hover | null>(null);
  const [fileMenuAt, setFileMenuAt] = useState<{ path: string; x: number; y: number } | null>(null);
  const cards = useRef<{ rect: number[]; file: string }[]>([]);
  const insideCard = useRef(false);
  const closeTicket = useRef(0);
  const rendered = useRef("");

  useEffect(() => {
    if (streaming) return;
    let live = true;
    void ChatFiles.export(source).then((e) => live && setExported(e));
    return () => {
      live = false;
    };
  }, [source, streaming]);

  const linked = ChatContext.linkedCitations(source, citations);
  const colors = dark ? { text: "#E6E8EB", surface: "#1F242B", accent: "#7CC4F2" } : { text: "#111418", surface: "#EBF0F6", accent: "#004A77" };
  const widgets = AnswerDocument.widgets(source, streaming, colors).map((w, i) => ({ title: w.title, page: w.page, file: exported.widgets[i] ? fileURL(exported.widgets[i]) : "" }));
  const rows = streaming ? [] : sourceRow(linked);
  const payload = {
    markdown: source,
    streaming,
    dark,
    citations: citationChips(linked),
    sources: rows,
    sourcesLabel: trf("来自 %d 个来源", rows.length),
    files: Object.fromEntries(Object.entries(exported.named).map(([k, v]) => [k, fileURL(v)])),
    widgets,
    fenceRoles: AnswerDocument.fenceRoles(source, streaming),
    preparing: tr("正在准备图示…"),
    cardTitle: tr("互动图示"),
  };
  const json = JSON.stringify(payload);

  const citationFor = (url: string) => {
    if (url.startsWith("nomi-cite://")) {
      const id = url.slice("nomi-cite://".length).replace(/\/$/, "");
      return citations.find((c) => c.id.toUpperCase() === id.toUpperCase()) ?? null;
    }
    return citations.find((c) => c.url === url) ?? null;
  };
  const open = (url: string) => {
    setHover(null);
    if (url.startsWith("nomi-cite://")) {
      const c = citationFor(url);
      if (c) (onOpenCitation ?? ((x: ChatCitation) => model.openCitation(x)))(c);
    } else if (url.startsWith(fileScheme)) void shell.openPath(decodeURIComponent(url.slice(fileScheme.length)));
    else if (/^https?:\/\//i.test(url)) void shell.openURL(url);
  };
  const scheduleClose = () => {
    const ticket = ++closeTicket.current;
    setTimeout(() => {
      if (closeTicket.current === ticket && !insideCard.current) setHover(null);
    }, 250);
  };

  const handler = useRef<(msg: Record<string, unknown>) => void>(() => {});
  handler.current = (msg) => {
    if (msg.ready) {
      rendered.current = "";
      setReady(true);
    } else if (typeof msg.height === "number" && isFinite(msg.height)) {
      setHeight(msg.height);
      heights.set(source, msg.height);
      if (heights.size > 400) heights.delete(heights.keys().next().value!);
    } else if (typeof msg.open === "string") open(msg.open);
    else if (typeof msg.hover === "string" && Array.isArray(msg.rect)) {
      closeTicket.current++;
      const box = frame.current!.getBoundingClientRect();
      const [x, y, w, h] = msg.rect as number[];
      setHover({ url: msg.hover, label: String(msg.label ?? ""), rect: new DOMRect(box.left + x, box.top + y, Math.max(w, 1), Math.max(h, 1)) });
    } else if (msg.escape) setHover(null);
    else if (msg.unhover) {
      if (msg.now && !insideCard.current) setHover(null);
      else scheduleClose();
    } else if (Array.isArray(msg.cards)) cards.current = (msg.cards as unknown[][]).filter((c) => c.length === 5).map((c) => ({ rect: c.slice(0, 4) as number[], file: decodeURIComponent(String(c[4]).slice(fileScheme.length)) }));
  };

  useLayoutEffect(() => {
    const el = frame.current as (HTMLIFrameElement & { __nomi?: (m: Record<string, unknown>) => void }) | null;
    if (el) el.__nomi = (m) => handler.current(m);
  }, []);

  // Render whenever the answer changes.
  useEffect(() => {
    if (!ready || rendered.current === json) return;
    rendered.current = json;
    const win = frame.current?.contentWindow as (Window & { nomi?: { render: (p: unknown) => void } }) | null;
    win?.nomi?.render(JSON.parse(json));
  }, [ready, json]);

  // The page never scrolls by itself: vertical wheels move the chat around it.
  const onLoad = () => {
    const win = frame.current?.contentWindow;
    if (!win) return;
    win.addEventListener(
      "wheel",
      (e) => {
        if (Math.abs(e.deltaY) < Math.abs(e.deltaX)) return;
        let el: HTMLElement | null = frame.current!.parentElement;
        while (el && !(el.scrollHeight > el.clientHeight && /(auto|scroll)/.test(getComputedStyle(el).overflowY))) el = el.parentElement;
        if (el) {
          e.preventDefault();
          el.scrollTop += e.deltaMode === 1 ? e.deltaY * 16 : e.deltaY;
        }
      },
      { passive: false },
    );
    win.addEventListener("contextmenu", (e) => {
      const hit = cards.current.find((c) => e.clientX >= c.rect[0] && e.clientX <= c.rect[0] + c.rect[2] && e.clientY >= c.rect[1] && e.clientY <= c.rect[1] + c.rect[3]);
      if (!hit || !hit.file) return;
      e.preventDefault();
      const box = frame.current!.getBoundingClientRect();
      setFileMenuAt({ path: hit.file, x: box.left + e.clientX, y: box.top + e.clientY });
    });
  };

  const hovered = hover ? citationFor(hover.url) : null;
  const details: CitationDetails | null = hover ? (hovered ? model.citationDetails(hovered) : { ...model.citationDetails({ id: "", title: hover.label, detail: "", url: hover.url } as ChatCitation), kind: "web", origin: host(hover.url), title: hover.label === host(hover.url) ? "" : hover.label, webURL: hover.url }) : null;

  return (
    <>
      <iframe ref={frame} src="/answer/answer.html" onLoad={onLoad} title={tr("回答")} className="block w-full border-0 bg-transparent" style={{ height: Math.max(height, 22), colorScheme: dark ? "dark" : "light" }} />
      {hover && details && (
        <CitationCardLayer anchor={hover.rect}>
          <CitationCard
            details={details}
            citation={hovered}
            onOpen={() => open(hover.url)}
            onInside={(inside) => {
              insideCard.current = inside;
              if (inside) closeTicket.current++;
              else scheduleClose();
            }}
          />
        </CitationCardLayer>
      )}
      {fileMenuAt && <Menu anchor={pointAnchor(fileMenuAt.x, fileMenuAt.y)} items={fileMenu(fileMenuAt.path)} onClose={() => setFileMenuAt(null)} />}
    </>
  );
}
