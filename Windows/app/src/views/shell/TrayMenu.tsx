// Windows: the menu that opens from Nomi's icon in the system tray. It is its own small window
// (label "tray-menu"), drawn in Nomi's style and sized to its two rows; Rust places and hides it.
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
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

const words = {
  "zh-Hans": { show: "显示 Nomi", quit: "退出 Nomi" },
  en: { show: "Show Nomi", quit: "Quit Nomi" },
};

export function TrayMenu() {
  // Each time the menu opens it re-reads the settings (for light or dark) and takes the language
  // the main window is showing, so the two always match.
  const [language, setLanguage] = useState<keyof typeof words>(navigator.language.toLowerCase().startsWith("zh") ? "zh-Hans" : "en");
  const card = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const el = card.current;
    if (el) void invoke("tray_menu_fit", { width: el.offsetWidth, height: el.offsetHeight }).catch(() => {});
  }, [language]);
  useEffect(() => {
    Appearance.apply();
    const off = listen<string>("nomi://tray-menu-open", (event) => {
      if (event.payload === "zh-Hans" || event.payload === "en") setLanguage(event.payload);
      void loadPrefs().then(() => Appearance.apply());
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
    <div ref={card} className="tray-menu flex w-[148px] flex-col gap-0.5 p-[5px] text-[var(--text)] select-none">
      <Row icon={<BrandLogo side={15} />} title={words[language].show} onClick={() => void invoke("tray_show_main")} />
      <Row icon={<PowerIcon />} title={words[language].quit} danger onClick={() => void invoke("app_quit")} />
    </div>
  );
}
