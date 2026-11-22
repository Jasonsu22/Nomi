// Pages/CitationCard.swift: the card shown while the pointer rests on a citation.
import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { tr } from "../../i18n";
import { prefs } from "../../support/prefs";
import { useModel } from "../../app";
import type { CitationDetails, CitationKindName } from "../../app/citations";
import type { ChatCitation } from "../../models/chatSession";
import { fileSrc, images } from "../../platform";
import { Icon } from "../ui/Icon";
import { PdfThumbnail } from "./Pdf";

export const citationSymbol: Record<CitationKindName, string> = {
  lecture: "clock", summary: "sparkles", pdf: "doc.richtext", slides: "rectangle.on.rectangle", document: "doc.text", picture: "photo", web: "globe", chat: "bubble.left.and.bubble.right", missing: "exclamationmark.triangle",
};

export const WebPreviews = {
  settingKey: "nomi.citations.webPreviews",
  get enabled() {
    return prefs.bool(this.settingKey) ?? true;
  },
};

function Marked({ text, quote, quoted, base = "var(--text)", markWhole = false }: { text: string; quote: string; quoted: boolean; base?: string; markWhole?: boolean }) {
  const shown = quoted ? `“${text}”` : text;
  const needle = quote.trim();
  const at = needle && ([...needle].length < [...text].length || quoted || markWhole) ? shown.indexOf(needle) : -1;
  if (at < 0) return <span style={{ color: base }}>{shown}</span>;
  return (
    <span style={{ color: base }}>
      {shown.slice(0, at)}
      <mark className="rounded-[2px] bg-[var(--selection)] text-[var(--text)]">{needle}</mark>
      {shown.slice(at + needle.length)}
    </span>
  );
}

function SmallButton({ title, symbol, onClick }: { title: string; symbol: string; onClick: () => void }) {
  return (
    <button onClick={onClick} className="press inline-flex items-center gap-[5px] rounded-[7px] bg-[var(--surface-inset)] px-[9px] py-1 text-[12px]">
      <Icon name={symbol} size={10} weight={2.6} />
      {title}
    </button>
  );
}

export function CitationCard({ details, citation, onOpen, onInside }: { details: CitationDetails; citation: ChatCitation | null; onOpen: () => void; onInside: (inside: boolean) => void }) {
  const m = useModel();
  const [loaded, setLoaded] = useState<string | null>(null);
  const [picture, setPicture] = useState<string | null>(null);
  const [icon, setIcon] = useState<string | null>(null);
  const [playing, setPlaying] = useState(false);
  const [copied, setCopied] = useState(false);
  const run = useRef(0);
  useEffect(() => {
    let live = true;
    (async () => {
      if (!details.excerpt && !details.quote && citation && ["pdf", "slides", "document"].includes(details.kind)) {
        const text = await m.citationFileExcerpt(citation).catch(() => "");
        if (live) setLoaded(text);
      }
      if (details.kind === "picture" && details.fileURL) {
        const thumb = await images.thumbnail(details.fileURL, 640).catch(() => null);
        if (live) setPicture(thumb);
      }
      if (details.kind === "web" && WebPreviews.enabled && details.webURL) {
        try {
          const host = new URL(details.webURL).hostname;
          if (live) setIcon(`https://icons.duckduckgo.com/ip3/${host}.ico`);
        } catch {
          /* no icon */
        }
      }
    })();
    return () => {
      live = false;
      if (playing) m.stopMoment();
    };
  }, [details.origin + details.place]);

  const excerpt = details.excerpt || loaded || "";
  const text = excerpt || details.quote;
  const passage = (quoted: boolean, clamp: number | null = 9) =>
    text ? (
      <div className="selectable text-[13px] leading-[19px]" style={clamp ? { display: "-webkit-box", WebkitLineClamp: clamp, WebkitBoxOrient: "vertical", overflow: "hidden" } : undefined}>
        <Marked text={text} quote={details.quote} quoted={quoted} />
      </div>
    ) : null;
  const copyText = details.quote || excerpt;
  const copy = copyText ? (
    <SmallButton
      title={copied ? tr("已复制") : tr("复制引文")}
      symbol={copied ? "checkmark" : "doc.on.doc"}
      onClick={() => {
        void navigator.clipboard.writeText(copyText);
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
      }}
    />
  ) : null;

  let content: React.ReactNode;
  switch (details.kind) {
    case "missing":
      content = <div className="font-secondary rounded-[8px] bg-[var(--surface-inset)] px-2.5 py-2 text-[var(--text-2)]">{details.missing}</div>;
      break;
    case "lecture":
      content = (
        <>
          <div className="scroll flex max-h-[300px] flex-col gap-[9px]">
            {passage(true, null)}
            {details.translation && (
              <div className="selectable text-[12px] leading-[17px]">
                <Marked text={details.translation} quote={details.translationQuote} quoted={false} base="var(--text-2)" markWhole />
              </div>
            )}
          </div>
          <div className="flex gap-2">
            {details.hasAudio && details.meetingID && details.at != null && (
              <SmallButton
                title={playing ? tr("正在播放…") : tr("播放这一刻")}
                symbol={playing ? "speaker.wave.2.fill" : "play.fill"}
                onClick={async () => {
                  if (playing) {
                    m.stopMoment();
                    setPlaying(false);
                    return;
                  }
                  const seconds = await m.playMoment(details.meetingID!, details.at!, details.until);
                  if (seconds == null) return;
                  const ticket = ++run.current;
                  setPlaying(true);
                  setTimeout(() => run.current === ticket && setPlaying(false), seconds * 1000);
                }}
              />
            )}
            {copy}
          </div>
        </>
      );
      break;
    case "pdf":
    case "slides":
      content = (
        <>
          <div className="flex items-start gap-2.5">
            {details.kind === "pdf" && details.fileURL && <PdfThumbnail path={details.fileURL} page={details.page ?? 1} width={74} />}
            <div className="min-w-0 flex-1">{passage(false)}</div>
          </div>
          {copy}
        </>
      );
      break;
    case "picture":
      content = (
        <>
          {picture && <img src={picture} className="max-h-[150px] w-full rounded-[8px] object-contain" />}
          {passage(false)}
        </>
      );
      break;
    case "web":
    case "chat":
      content = (
        <>
          {details.title && <div className="font-secondary line-clamp-2 font-semibold">{details.title}</div>}
          {passage(false)}
        </>
      );
      break;
    default:
      content = (
        <>
          {passage(false)}
          {details.kind === "document" && copy}
        </>
      );
  }
  return (
    <div onMouseEnter={() => onInside(true)} onMouseLeave={() => onInside(false)} className="flex w-[340px] flex-col gap-[9px] rounded-[14px] border border-[var(--separator)] bg-[var(--surface)] p-3.5 shadow-[0_12px_32px_rgba(0,0,0,0.16),0_2px_6px_rgba(0,0,0,0.08)]">
      <div className="flex items-center gap-[7px]">
        {icon ? (
          <img src={icon} className="h-4 w-4 rounded-[3px]" onError={() => setIcon(null)} />
        ) : (
          <span className="flex w-4 justify-center" style={{ color: details.kind === "missing" ? "var(--text-2)" : "var(--accent)" }}>
            <Icon name={citationSymbol[details.kind]} size={13} weight={2.4} />
          </span>
        )}
        <span className="font-caption min-w-0 flex-1 truncate">
          <span className="text-[var(--text-2)]">{details.origin}</span>
          {details.place && <span className="text-[var(--text-2)]"> · </span>}
          <span className="font-semibold text-[var(--accent)]">{details.place}</span>
        </span>
        {details.kind !== "missing" && (
          <button onClick={onOpen} className="font-caption inline-flex items-center gap-[3px] font-semibold text-[var(--accent)]">
            {details.kind === "lecture" ? tr("跳到这里") : tr("打开")}
            <Icon name="arrow.up.right" size={9} weight={3} />
          </button>
        )}
      </div>
      {content}
    </div>
  );
}

/** The floating card: under the citation, or above it when there is no room; fades and rises 4px. */
export function CitationCardLayer({ anchor, children }: { anchor: DOMRect; children: React.ReactNode }) {
  const box = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ left: number; top: number } | null>(null);
  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const place = () => {
      const r = el.getBoundingClientRect();
      let left = anchor.left + anchor.width / 2 - r.width / 2;
      left = Math.max(8, Math.min(left, window.innerWidth - r.width - 8));
      let top = anchor.bottom + 8;
      if (top + r.height > window.innerHeight - 8) top = Math.max(8, anchor.top - 8 - r.height);
      setPos({ left, top });
    };
    place();
    const observer = new ResizeObserver(place);
    observer.observe(el);
    return () => observer.disconnect();
  }, [anchor.left, anchor.top, anchor.width, anchor.height]);
  return createPortal(
    <div ref={box} className="fixed z-[950]" style={{ left: pos?.left ?? -9999, top: pos?.top ?? -9999, animation: pos ? "card-rise 140ms ease-out" : undefined }}>
      {children}
    </div>,
    document.body,
  );
}

export const fileImage = (path: string) => fileSrc(path);
