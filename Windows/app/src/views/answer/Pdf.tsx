// PDF pages through pdf.js: card thumbnails and Pages/PDFViewerSheet.swift (open at the cited page,
// the quoted words marked).
import { useEffect, useRef, useState } from "react";
import * as pdfjs from "pdfjs-dist";
import workerURL from "pdfjs-dist/build/pdf.worker.min.mjs?url";
import { tr, trf } from "../../i18n";
import { fs, paths, shell } from "../../platform";
import { useModel } from "../../app";
import { Icon } from "../ui/Icon";
import { PushButton, Sheet } from "../ui/controls";

pdfjs.GlobalWorkerOptions.workerSrc = workerURL;

const documents = new Map<string, Promise<pdfjs.PDFDocumentProxy>>();
export function pdfDocument(path: string) {
  let hit = documents.get(path);
  if (!hit) {
    hit = fs.readBase64(path).then((b64) => {
      const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      return pdfjs.getDocument({ data: bytes, isEvalSupported: false }).promise;
    });
    hit.catch(() => documents.delete(path));
    documents.set(path, hit);
    if (documents.size > 12) documents.delete(documents.keys().next().value!);
  }
  return hit;
}

const thumbs = new Map<string, string>();
export function PdfThumbnail({ path, page, width }: { path: string; page: number; width: number }) {
  const key = `${path}#${page}`;
  const [src, setSrc] = useState(thumbs.get(key) ?? null);
  useEffect(() => {
    if (src) return;
    let live = true;
    (async () => {
      const doc = await pdfDocument(path);
      const p = await doc.getPage(Math.min(Math.max(1, page), doc.numPages));
      const base = p.getViewport({ scale: 1 });
      const viewport = p.getViewport({ scale: (width * 2) / base.width });
      const canvas = document.createElement("canvas");
      canvas.width = viewport.width;
      canvas.height = viewport.height;
      await p.render({ canvasContext: canvas.getContext("2d")!, viewport }).promise;
      const url = canvas.toDataURL("image/png");
      thumbs.set(key, url);
      if (live) setSrc(url);
    })().catch(() => {});
    return () => {
      live = false;
    };
  }, [key]);
  if (!src) return <div style={{ width, height: width * 1.3 }} className="rounded-[4px] bg-[var(--surface-inset)]" />;
  return <img src={src} style={{ width }} className="rounded-[4px] shadow-[0_0_0_0.5px_var(--outline)]" />;
}

function PdfPage({ doc, number, width, quote, scrollTo }: { doc: pdfjs.PDFDocumentProxy; number: number; width: number; quote: string | null; scrollTo: boolean }) {
  const holder = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(scrollTo);
  const [size, setSize] = useState<{ w: number; h: number } | null>(null);
  const [marks, setMarks] = useState<{ x: number; y: number; w: number; h: number }[]>([]);
  useEffect(() => {
    doc.getPage(number).then((p) => {
      const v = p.getViewport({ scale: 1 });
      setSize({ w: width, h: (v.height / v.width) * width });
    });
  }, [doc, number, width]);
  useEffect(() => {
    const el = holder.current;
    if (!el) return;
    const io = new IntersectionObserver((e) => e[0].isIntersecting && setVisible(true), { rootMargin: "800px" });
    io.observe(el);
    return () => io.disconnect();
  }, []);
  useEffect(() => {
    if (!visible || !size || !holder.current) return;
    let cancelled = false;
    (async () => {
      const p = await doc.getPage(number);
      const base = p.getViewport({ scale: 1 });
      const scale = size.w / base.width;
      const ratio = window.devicePixelRatio || 1;
      const viewport = p.getViewport({ scale: scale * ratio });
      const canvas = document.createElement("canvas");
      canvas.width = viewport.width;
      canvas.height = viewport.height;
      canvas.style.width = `${size.w}px`;
      canvas.style.height = `${size.h}px`;
      await p.render({ canvasContext: canvas.getContext("2d")!, viewport }).promise;
      if (cancelled || !holder.current) return;
      holder.current.querySelector("canvas")?.remove();
      holder.current.prepend(canvas);
      if (quote) {
        const text = await p.getTextContent();
        const items = text.items.filter((i) => "str" in i) as { str: string; transform: number[]; width: number }[];
        const joined = items.map((i) => i.str).join("");
        const lower = joined.toLowerCase();
        const q = quote.trim().toLowerCase();
        let at = -1, length = 0;
        for (const candidate of [q, q.slice(0, 60), q.slice(0, 24)]) {
          if ([...candidate].length < 6) continue;
          at = lower.indexOf(candidate);
          if (at >= 0) {
            length = candidate.length;
            break;
          }
        }
        if (at >= 0) {
          const found: { x: number; y: number; w: number; h: number }[] = [];
          let offset = 0;
          const vp = p.getViewport({ scale });
          for (const item of items) {
            const start = offset, end = offset + item.str.length;
            offset = end;
            if (end <= at || start >= at + length) continue;
            const [x, y] = vp.convertToViewportPoint(item.transform[4], item.transform[5]);
            const h = Math.hypot(item.transform[2], item.transform[3]) * scale;
            found.push({ x, y: y - h, w: item.width * scale, h: h * 1.15 });
          }
          setMarks(found);
          if (scrollTo && found[0]) holder.current.parentElement?.parentElement?.scrollTo({ top: holder.current.offsetTop + found[0].y - 120 });
        }
      }
    })().catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [visible, size?.w, number, quote]);
  useEffect(() => {
    if (scrollTo && size && holder.current) holder.current.scrollIntoView({ block: "start" });
  }, [scrollTo, !!size]);
  return (
    <div ref={holder} className="relative mx-auto bg-white shadow-[0_1px_4px_rgba(0,0,0,0.18)]" style={{ width: size?.w ?? width, height: size?.h ?? width * 1.3 }}>
      {marks.map((r, i) => (
        <span key={i} className="pointer-events-none absolute rounded-[2px]" style={{ left: r.x, top: r.y, width: r.w, height: r.h, background: "rgba(255, 204, 0, 0.45)" }} />
      ))}
    </div>
  );
}

export function PDFViewerSheet() {
  const m = useModel();
  const request = m.pdfViewer;
  const [doc, setDoc] = useState<pdfjs.PDFDocumentProxy | null>(null);
  const [error, setError] = useState(false);
  const scroller = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(680);
  useEffect(() => {
    if (!request) return;
    setDoc(null);
    setError(false);
    pdfDocument(request.path).then(setDoc, () => setError(true));
  }, [request?.id]);
  useEffect(() => {
    const el = scroller.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setWidth(Math.max(320, el.clientWidth - 48)));
    ro.observe(el);
    return () => ro.disconnect();
  }, [!!request]);
  if (!request) return null;
  const close = () => m.set("pdfViewer", null);
  return (
    <Sheet width={820} onClose={close}>
      <div className="flex h-[min(820px,calc(100vh-48px))] flex-col">
        <div className="flex items-center gap-2 p-4">
          <span className="text-[var(--accent)]">
            <Icon name="doc.richtext" size={16} />
          </span>
          <span className="font-section-title min-w-0 truncate">{paths.name(request.path)}</span>
          {request.page && <span className="font-secondary text-[var(--text-2)]">{trf("第 %d 页", request.page)}</span>}
          <div className="flex-1" />
          <PushButton title={tr("在默认应用中打开")} onClick={() => void shell.openPath(request.path)} />
          <PushButton prominent title={tr("完成")} onClick={close} />
        </div>
        <div className="h-px bg-[var(--separator)]" />
        <div ref={scroller} className="scroll flex-1 bg-[var(--canvas)] py-6">
          <div className="flex flex-col gap-4">
            {error && <div className="font-secondary p-6 text-center text-[var(--text-2)]">{tr("无法打开这个 PDF。")}</div>}
            {doc && Array.from({ length: doc.numPages }, (_, i) => <PdfPage key={i} doc={doc} number={i + 1} width={width} quote={request.page === i + 1 ? request.quote : null} scrollTo={request.page === i + 1} />)}
          </div>
        </div>
      </div>
    </Sheet>
  );
}
