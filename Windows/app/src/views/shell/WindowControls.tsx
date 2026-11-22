// Windows only: Nomi draws its own title bar, so the window's minimize, maximize and close
// buttons live here, in the app's own style, at the right end of the top bar.
import { useEffect, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { tr } from "../../i18n";
import { platformOS } from "../../platform";

/** True where Nomi replaces the system title bar (Windows). The Mac keeps its own. */
export const drawsOwnTitleBar = () => platformOS === "windows";

type Glyph = "minimize" | "maximize" | "restore" | "close";

function GlyphIcon({ glyph }: { glyph: Glyph }) {
  const common = { fill: "none", stroke: "currentColor", strokeWidth: 1.3, strokeLinecap: "round" as const, strokeLinejoin: "round" as const };
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden>
      {glyph === "minimize" && <path d="M2 6.5h8" {...common} />}
      {glyph === "maximize" && <rect x="2" y="2" width="8" height="8" rx="2" {...common} />}
      {glyph === "restore" && (
        <>
          <rect x="2" y="4" width="6" height="6" rx="1.6" {...common} />
          <path d="M4.5 2.3h3.7a1.6 1.6 0 0 1 1.6 1.6v3.7" {...common} />
        </>
      )}
      {glyph === "close" && <path d="M2.6 2.6l6.8 6.8M9.4 2.6l-6.8 6.8" {...common} />}
    </svg>
  );
}

function ControlButton({ glyph, label, danger, onClick }: { glyph: Glyph; label: string; danger?: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      title={label}
      aria-label={label}
      className={`window-control flex h-8 w-10 items-center justify-center rounded-[9px] text-[var(--text-2)] transition-colors duration-150 ${danger ? "window-control-close" : ""}`}
    >
      <GlyphIcon glyph={glyph} />
    </button>
  );
}

/** Minimize, maximize or restore, and close. Close goes through the same path as Alt+F4, so
 *  the "minimize to tray or quit" choice applies. `compact` leaves out maximize. */
export function WindowControls({ compact = false }: { compact?: boolean }) {
  const [maximized, setMaximized] = useState(false);
  useEffect(() => {
    if (!drawsOwnTitleBar()) return;
    const win = getCurrentWindow();
    const sync = () => void win.isMaximized().then(setMaximized, () => {});
    sync();
    const off = win.onResized(sync);
    return () => void off.then((f) => f());
  }, []);
  if (!drawsOwnTitleBar()) return null;
  const win = getCurrentWindow();
  return (
    <div className="flex shrink-0 items-center gap-0.5">
      <ControlButton glyph="minimize" label={tr("最小化")} onClick={() => void win.minimize()} />
      {!compact && <ControlButton glyph={maximized ? "restore" : "maximize"} label={maximized ? tr("还原") : tr("最大化")} onClick={() => void win.toggleMaximize()} />}
      <ControlButton glyph="close" label={tr("关闭")} danger onClick={() => void win.close()} />
    </div>
  );
}
