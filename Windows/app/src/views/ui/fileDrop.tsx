// Pages/FileDrop.swift: files dropped from Explorer onto an element. The web view's own drop events
// carry no paths, so this listens to Tauri's drag-and-drop and checks the pointer is over the element.
import { useEffect, useRef, useState } from "react";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import { tr } from "../../i18n";
import { SourceText } from "../../models/sourceText";

type Target = { el: () => HTMLElement | null; onHover: (over: boolean) => void; onDrop: (paths: string[]) => void };
const targets = new Set<Target>();
let listening = false;

function inside(el: HTMLElement | null, x: number, y: number) {
  if (!el || !el.offsetParent) return false;
  const r = el.getBoundingClientRect();
  return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
}

/** The innermost target under the pointer gets the drop. */
function pick(x: number, y: number): Target | null {
  let best: Target | null = null;
  for (const t of targets) {
    const el = t.el();
    if (!inside(el, x, y)) continue;
    if (!best || best.el()!.contains(el)) best = t;
  }
  return best;
}

function listen() {
  if (listening) return;
  listening = true;
  try {
    void getCurrentWebview().onDragDropEvent((event) => {
      const p = event.payload;
      const ratio = window.devicePixelRatio || 1;
      if (p.type === "leave") {
        targets.forEach((t) => t.onHover(false));
        return;
      }
      const x = p.position.x / ratio, y = p.position.y / ratio;
      const target = pick(x, y);
      targets.forEach((t) => t.onHover(t === target && p.type !== "drop"));
      if (p.type === "drop" && target) target.onDrop(p.paths);
    });
  } catch {
    /* not inside Tauri (browser preview) */
  }
}

export function useFileDrop(onDrop: (paths: string[]) => void, enabled = true) {
  const ref = useRef<HTMLDivElement>(null);
  const [targeted, setTargeted] = useState(false);
  const drop = useRef(onDrop);
  drop.current = onDrop;
  useEffect(() => {
    if (!enabled) return;
    listen();
    const target: Target = { el: () => ref.current, onHover: setTargeted, onDrop: (p) => drop.current(p) };
    targets.add(target);
    return () => {
      targets.delete(target);
    };
  }, [enabled]);
  return { ref, targeted };
}

export const sourceFilters = () => [{ name: tr("资料"), extensions: [...SourceText.readableExtensions] }];

/** The dashed outline shown while files are dragged over a drop area. */
export function DropOutline({ shown, inset = 12, radius = 16 }: { shown: boolean; inset?: number; radius?: number }) {
  if (!shown) return null;
  return <div className="pointer-events-none absolute border-2 border-dashed border-[var(--accent)]" style={{ inset, borderRadius: radius }} />;
}
