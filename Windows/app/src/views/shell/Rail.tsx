// Shell/Rail.swift and DesignSystem/Components/RailItem.swift.
import { pageTitle, type AppPage } from "../../app/model";
import { useModel } from "../../app";
import { Icon } from "../ui/Icon";
import { railWidth } from "./TopBar";

const symbols: Record<AppPage, string> = { meetings: "calendar", ask: "text.bubble", sources: "folder", help: "questionmark.circle", settings: "gearshape" };
const tutorial: Partial<Record<AppPage, string>> = { meetings: "meetings", sources: "sources", ask: "chat", settings: "settings" };

function RailItem({ page }: { page: AppPage }) {
  const m = useModel();
  const selected = m.page === page;
  return (
    <button
      data-tutorial={tutorial[page]}
      onClick={() => m.select(page)}
      aria-label={pageTitle(page)}
      aria-selected={selected}
      className="press relative flex h-[54px] w-[60px] flex-col items-center justify-center gap-1"
      style={{ color: selected ? "var(--on-selection)" : "var(--text-2)" }}
    >
      <span className="absolute inset-0 rounded-[12px] bg-[var(--selection)] transition-all duration-300" style={{ opacity: selected ? 1 : 0, transform: selected ? "none" : "scale(0.9)", transitionTimingFunction: "var(--ease-smooth)" }} />
      <span className="relative">
        <Icon name={symbols[page]} size={18} weight={selected ? 2.3 : 1.8} />
      </span>
      <span className="font-caption relative whitespace-nowrap">{pageTitle(page)}</span>
    </button>
  );
}

export function Rail() {
  return (
    <div className="flex h-full shrink-0 flex-col items-center gap-1 pt-2 pb-4" style={{ width: railWidth }}>
      <RailItem page="meetings" />
      <RailItem page="sources" />
      <RailItem page="ask" />
      <div className="flex-1" />
      <RailItem page="help" />
      <RailItem page="settings" />
    </div>
  );
}
