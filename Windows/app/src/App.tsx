// The window: a glass rail on the left and the page on the right. Pages cross-fade.
import { Library, Mic, Settings as Gear } from "lucide-react";
import { useEffect } from "react";
import leaf from "./assets/leaf.svg";
import { useT } from "./lib/i18n";
import { LivePage } from "./pages/Live";
import { MeetingsPage } from "./pages/Meetings";
import { SettingsPage } from "./pages/Settings";
import { SetupPage } from "./pages/Setup";
import { connect, useApp, type Page } from "./store";

function RailItem({ page, icon, label, badge }: { page: Page; icon: React.ReactNode; label: string; badge?: boolean }) {
  const current = useApp((s) => s.page);
  const go = useApp((s) => s.go);
  const active = current === page;
  return (
    <button
      onClick={() => go(page)}
      className={`press group relative flex w-[60px] flex-col items-center gap-1 rounded-[14px] py-2 text-[11px] font-medium transition-colors duration-[var(--t-tap)] ${
        active ? "text-[var(--on-selection)]" : "text-[var(--text-2)] hover:text-[var(--text)]"
      }`}
    >
      <span
        className={`absolute inset-0 rounded-[14px] transition-all duration-[var(--t-layout)] ease-[var(--ease-spring)] ${
          active ? "scale-100 bg-[var(--selection)] opacity-100" : "scale-90 opacity-0"
        }`}
      />
      <span className="relative">
        {icon}
        {badge && <span className="absolute -top-0.5 -right-1 h-2 w-2 animate-pulse rounded-full bg-[#e5484d]" />}
      </span>
      <span className="relative">{label}</span>
    </button>
  );
}

export default function App() {
  const t = useT();
  const page = useApp((s) => s.page);
  const material = useApp((s) => s.overview?.material);
  const recording = useApp((s) => !!s.live && s.live.state !== "done");

  useEffect(() => {
    void connect();
  }, []);
  useEffect(() => {
    document.body.classList.toggle("solid", material === "none");
  }, [material]);

  if (page === "setup") return <SetupPage />;

  return (
    <div className="flex h-full">
      <nav className="glass m-2 mr-0 flex w-[76px] flex-col items-center gap-1 rounded-[20px] py-3">
        <img src={leaf} alt="Nomi" className="mb-3 h-8 w-8" draggable={false} />
        <RailItem page="live" icon={<Mic size={20} />} label={t("录音")} badge={recording} />
        <RailItem page="meetings" icon={<Library size={20} />} label={t("会议")} />
        <div className="flex-1" />
        <RailItem page="settings" icon={<Gear size={20} />} label={t("设置")} />
      </nav>
      <main key={page} className="fade-in flex min-w-0 flex-1 flex-col">
        {page === "live" && <LivePage />}
        {page === "meetings" && <MeetingsPage />}
        {page === "settings" && <SettingsPage />}
      </main>
    </div>
  );
}
