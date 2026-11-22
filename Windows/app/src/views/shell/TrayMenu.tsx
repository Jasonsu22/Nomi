// Windows: the menu that opens from Nomi's icon in the system tray. It is its own small window
// (label "tray-menu"), drawn in Nomi's style and sized to its two rows; Rust places and hides it.
import { useEffect, useState, type ReactNode } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { tr } from "../../i18n";
import { loadPrefs } from "../../support/prefs";
import { Appearance } from "../../support/appearance";
import { BrandLogo } from "../ui/Logos";

function PowerIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 16 16" aria-hidden fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
      <path d="M8 2.2v5.3" />
      <path d="M4.6 4.4a5 5 0 1 0 6.8 0" />
    </svg>
  );
}

function Row({ icon, title, danger, onClick }: { icon: ReactNode; title: string; danger?: boolean; onClick: () => void }) {
  return (
    <button onClick={onClick} className={`tray-row font-secondary flex h-8 w-full items-center gap-2.5 rounded-[7px] px-2.5 text-left font-medium ${danger ? "tray-row-danger" : ""}`}>
      <span className="flex w-4 shrink-0 justify-center">{icon}</span>
      <span className="truncate">{title}</span>
    </button>
  );
}

export function TrayMenu() {
  // Re-read the settings each time the menu opens, so its language and light or dark look follow
  // the main window's.
  const [, refresh] = useState(0);
  useEffect(() => {
    Appearance.apply();
    const off = listen("nomi://tray-menu-open", () => {
      void loadPrefs().then(() => {
        Appearance.apply();
        refresh((n) => n + 1);
      });
    });
    const key = (e: KeyboardEvent) => {
      if (e.key === "Escape") void getCurrentWindow().hide();
    };
    window.addEventListener("keydown", key);
    return () => {
      void off.then((f) => f());
      window.removeEventListener("keydown", key);
    };
  }, []);
  return (
    <div className="tray-menu flex h-full flex-col gap-0.5 p-[5px] text-[var(--text)] select-none">
      <Row icon={<BrandLogo side={15} />} title={tr("显示 Nomi")} onClick={() => void invoke("tray_show_main")} />
      <Row icon={<PowerIcon />} title={tr("退出 Nomi")} danger onClick={() => void invoke("app_quit")} />
    </div>
  );
}
