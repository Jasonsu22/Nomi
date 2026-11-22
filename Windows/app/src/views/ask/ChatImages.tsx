// Pages/ChatImageViews.swift: thumbnails and file chips above a question, and the picture viewer.
import { useEffect, useRef, useState } from "react";
import { tr } from "../../i18n";
import { formatBytes } from "../../support/format";
import { ChatImages, isDraftFile, type ChatFileRef, type ChatImage, type ChatImageDraft } from "../../models/chatImage";
import { SourceStore } from "../../app/stores";
import { model, useModel } from "../../app";
import { fileSrc, fs, paths, shell } from "../../platform";
import { Icon } from "../ui/Icon";
import { Menu, pointAnchor } from "../ui/controls";
import { fileMenu } from "../answer/AnswerBody";

const side = 48;

function RemoveBadge({ onClick, shown, label }: { onClick: () => void; shown: boolean; label: string }) {
  return (
    <button onClick={onClick} aria-label={label} className="absolute top-[3px] right-[3px] flex h-4 w-4 items-center justify-center rounded-full bg-black/70 text-white transition-opacity duration-100" style={{ opacity: shown ? 1 : 0, pointerEvents: shown ? "auto" : "none" }}>
      <Icon name="xmark" size={8} weight={3.5} />
    </button>
  );
}

export function ChatThumb({ path, name, onRemove }: { path: string; name: string; onRemove?: () => void }) {
  const [hover, setHover] = useState(false);
  const [menu, setMenu] = useState<{ x: number; y: number } | null>(null);
  const [failed, setFailed] = useState(false);
  return (
    <div className="relative shrink-0" style={{ width: side, height: side }} onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}>
      <button
        onClick={() => !failed && model.set("enlargedImage", { path, name })}
        onContextMenu={(e) => {
          e.preventDefault();
          setMenu({ x: e.clientX, y: e.clientY });
        }}
        className="relative h-full w-full overflow-hidden rounded-[8px] bg-[var(--surface-inset)]"
      >
        {!failed && <img src={fileSrc(path)} onError={() => setFailed(true)} className="h-full w-full object-cover" alt={name} />}
        <span className="absolute inset-0 bg-black transition-opacity duration-100" style={{ opacity: hover && !failed ? 0.22 : 0 }} />
      </button>
      {onRemove && <RemoveBadge onClick={onRemove} shown={hover} label={tr("移走图片")} />}
      {menu && (
        <Menu
          anchor={pointAnchor(menu.x, menu.y)}
          onClose={() => setMenu(null)}
          items={[
            { kind: "item", title: tr("拷贝图片"), onSelect: () => void model.copyImage(path) },
            { kind: "item", title: tr("将图片存储为…"), onSelect: () => void model.saveFileCopy(path, name) },
          ]}
        />
      )}
    </div>
  );
}

export function ChatFileChip({ path, name, onRemove }: { path: string; name: string; onRemove?: () => void }) {
  const [hover, setHover] = useState(false);
  const [present, setPresent] = useState(true);
  const [size, setSize] = useState(0);
  const [menu, setMenu] = useState<{ x: number; y: number } | null>(null);
  useEffect(() => {
    void fs.stat(path).then(
      (s) => {
        setPresent(!!s);
        setSize(s?.size ?? 0);
      },
      () => setPresent(false),
    );
  }, [path]);
  const kind = paths.ext(path).toUpperCase();
  return (
    <div className="relative shrink-0" onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}>
      <button
        title={name}
        onClick={() => present && void shell.openPath(path)}
        onContextMenu={(e) => {
          if (!present) return;
          e.preventDefault();
          setMenu({ x: e.clientX, y: e.clientY });
        }}
        className="relative flex max-w-[240px] items-center gap-2 overflow-hidden rounded-[8px] bg-[var(--surface-inset)] px-2 text-left"
        style={{ height: side }}
      >
        <span className="flex h-[30px] w-[30px] shrink-0 items-center justify-center rounded-[6px] bg-[var(--surface)] text-[var(--accent)]" style={{ opacity: present ? 1 : 0.4 }}>
          <Icon name={paths.ext(path) === "pdf" ? "doc.richtext" : "doc.text"} size={16} />
        </span>
        <span className="flex min-w-0 flex-col gap-[1px]">
          <span className="font-secondary truncate font-medium" style={{ color: present ? "var(--text)" : "var(--text-2)" }}>{name}</span>
          <span className="font-caption truncate text-[var(--text-2)]">{present ? (kind ? `${kind} · ${formatBytes(size)}` : formatBytes(size)) : tr("文件已从资料中移除")}</span>
        </span>
        <span className="absolute inset-0 bg-black transition-opacity duration-100" style={{ opacity: hover && present ? 0.22 : 0 }} />
      </button>
      {onRemove && <RemoveBadge onClick={onRemove} shown={hover} label={tr("移走文件")} />}
      {menu && <Menu anchor={pointAnchor(menu.x, menu.y)} items={fileMenu(path)} onClose={() => setMenu(null)} />}
    </div>
  );
}

type Item = { id: string; path: string; name: string; isFile: boolean };

function ThumbRow({ items, trailing = false, onRemove }: { items: Item[]; trailing?: boolean; onRemove?: (id: string) => void }) {
  return (
    <div className="chip-strip flex gap-1.5" style={{ justifyContent: trailing ? "flex-end" : "flex-start", height: side }}>
      {items.map((i) => (i.isFile ? <ChatFileChip key={i.id} path={i.path} name={i.name} onRemove={onRemove && (() => onRemove(i.id))} /> : <ChatThumb key={i.id} path={i.path} name={i.name} onRemove={onRemove && (() => onRemove(i.id))} />))}
    </div>
  );
}

export function ChatImageStrip({ items, trailing, onRemove }: { items: ChatImageDraft[]; trailing?: boolean; onRemove?: (d: ChatImageDraft) => void }) {
  return <ThumbRow trailing={trailing} items={items.map((d) => ({ id: d.id, path: d.fileURL, name: d.name, isFile: isDraftFile(d) }))} onRemove={onRemove && ((id) => onRemove(items.find((d) => d.id === id)!))} />;
}

export function StoredImageStrip({ images, files = [] }: { images: ChatImage[]; files?: ChatFileRef[] }) {
  const items: Item[] = [
    ...images.map((i) => ({ id: i.id, path: ChatImages.fileURL(i), name: i.name, isFile: false })),
    ...files.map((f) => ({ id: f.sourceID, path: paths.join(SourceStore.directory(f.sourceID), f.name), name: f.name, isFile: true })),
  ];
  return <ThumbRow items={items} trailing />;
}

/** ChatImageLightbox: the picture over a dimmed window; scroll or the buttons zoom, drag moves it. */
export function ChatImageLightbox() {
  const m = useModel();
  const image = m.enlargedImage;
  const [shown, setShown] = useState(false);
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(null);
  const [scale, setScale] = useState(1);
  const [fit, setFit] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const [menu, setMenu] = useState<{ x: number; y: number } | null>(null);
  const box = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!image) return;
    setShown(false);
    setNatural(null);
    setOffset({ x: 0, y: 0 });
    requestAnimationFrame(() => setShown(true));
  }, [image?.path]);
  const close = () => {
    setShown(false);
    setTimeout(() => m.set("enlargedImage", null), 160);
  };
  useEffect(() => {
    if (!image) return;
    const key = (e: KeyboardEvent) => {
      if (e.key === "Escape") close();
      if (e.ctrlKey && (e.key === "=" || e.key === "+")) setScale((s) => s * 1.5);
      if (e.ctrlKey && e.key === "-") setScale((s) => s / 1.5);
      if (e.ctrlKey && e.key === "0") {
        setScale(fit);
        setOffset({ x: 0, y: 0 });
      }
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  });
  if (!image) return null;
  const onLoad = (e: React.SyntheticEvent<HTMLImageElement>) => {
    const w = e.currentTarget.naturalWidth, h = e.currentTarget.naturalHeight;
    setNatural({ w, h });
    const el = box.current!;
    const f = Math.min(1, (el.clientWidth - 80) / w, (el.clientHeight - 120) / h);
    setFit(f);
    setScale(f);
  };
  return (
    <div
      ref={box}
      className="fixed inset-0 z-[980] overflow-hidden bg-black/70 transition-opacity duration-200"
      style={{ opacity: shown ? 1 : 0 }}
      onMouseDown={(e) => e.target === e.currentTarget && close()}
      onWheel={(e) => setScale((s) => Math.min(8, Math.max(0.05, s * (e.deltaY < 0 ? 1.1 : 1 / 1.1))))}
    >
      <img
        src={fileSrc(image.path)}
        onLoad={onLoad}
        alt={image.name}
        draggable={false}
        onDoubleClick={() => (scale > fit * 1.01 ? (setScale(fit), setOffset({ x: 0, y: 0 })) : setScale(Math.min(8, fit * 2.5)))}
        onContextMenu={(e) => {
          e.preventDefault();
          setMenu({ x: e.clientX, y: e.clientY });
        }}
        onPointerDown={(e) => {
          const start = { x: e.clientX - offset.x, y: e.clientY - offset.y };
          e.currentTarget.setPointerCapture(e.pointerId);
          const move = (ev: PointerEvent) => setOffset({ x: ev.clientX - start.x, y: ev.clientY - start.y });
          const up = () => {
            window.removeEventListener("pointermove", move);
            window.removeEventListener("pointerup", up);
          };
          window.addEventListener("pointermove", move);
          window.addEventListener("pointerup", up);
        }}
        className="absolute top-1/2 left-1/2 max-w-none select-none"
        style={{ width: natural ? natural.w * scale : undefined, transform: `translate(calc(-50% + ${offset.x}px), calc(-50% + ${offset.y}px)) scale(${shown ? 1 : 0.86})`, transition: "transform 200ms var(--ease-smooth), width 200ms var(--ease-smooth)" }}
      />
      <button onClick={close} aria-label={tr("关闭")} className="absolute top-4 right-4 flex h-8 w-8 items-center justify-center rounded-full bg-black/55 text-white">
        <Icon name="xmark" size={14} weight={3} />
      </button>
      <div className="absolute bottom-3.5 left-1/2 flex -translate-x-1/2 items-center gap-0.5 rounded-full bg-black/60 px-1 text-white">
        <button onClick={() => setScale((s) => s / 1.5)} title={tr("缩小")} aria-label={tr("缩小")} className="flex h-[30px] w-[30px] items-center justify-center">
          <Icon name="minus" size={12} weight={3} />
        </button>
        <button
          onClick={() => {
            setScale(fit);
            setOffset({ x: 0, y: 0 });
          }}
          title={tr("适合窗口")}
          className="min-w-[52px] text-[12px] font-semibold tabular-nums"
        >
          {Math.round(scale * 100)}%
        </button>
        <button onClick={() => setScale((s) => s * 1.5)} title={tr("放大")} aria-label={tr("放大")} className="flex h-[30px] w-[30px] items-center justify-center">
          <Icon name="plus" size={12} weight={3} />
        </button>
      </div>
      {menu && (
        <Menu
          anchor={pointAnchor(menu.x, menu.y)}
          onClose={() => setMenu(null)}
          items={[
            { kind: "item", title: tr("拷贝图片"), onSelect: () => void m.copyImage(image.path) },
            { kind: "item", title: tr("将图片存储为…"), onSelect: () => void m.saveFileCopy(image.path, image.name) },
          ]}
        />
      )}
    </div>
  );
}
