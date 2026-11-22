// Pages/AskScopePopover.swift: which meetings and sources an answer may read.
import { useState } from "react";
import { tr } from "../../i18n";
import { formatMonthDay, toDate } from "../../support/format";
import { CategoryPalette } from "../../models/category";
import { emptyScope, Scope, type ChatScope, type ScopeCheck } from "../../models/chatSession";
import { useModel } from "../../app";
import { Icon } from "../ui/Icon";

type Column = { kind: "all" } | { kind: "category"; id: string } | { kind: "uncategorized" };

export function ScopeCheckBox({ state, onClick, enabled = true }: { state: ScopeCheck; onClick: () => void; enabled?: boolean }) {
  return (
    <button onClick={onClick} disabled={!enabled} className="flex h-[22px] w-[22px] shrink-0 items-center justify-center disabled:opacity-35" style={{ color: state === "off" ? "var(--text-2)" : "var(--accent)" }}>
      <Icon name={state === "on" ? "checkmark.circle.fill" : state === "mixed" ? "minus.circle.fill" : "circle"} size={17} />
    </button>
  );
}

export function AskScopePopover({ onClose }: { onClose: () => void }) {
  const m = useModel();
  const [column, setColumn] = useState<Column>({ kind: "all" });
  const meetings = m.chatMeetingItems();
  const sources = m.chatSourceItems();
  const scope: ChatScope = m.currentChat?.scope ?? emptyScope();
  const change = (next: ChatScope) => m.updateChatScope(next);
  const count = (category: string | null) => meetings.filter((x) => !x.live && (x.categoryID ?? null) === category).length + sources.filter((x) => (x.categoryID ?? null) === category).length;
  const selectedMeetings = Scope.selectedMeetings(scope, meetings);
  const selectedSources = Scope.selectedSources(scope, sources);
  const visible = column.kind === "all" ? { meetings: m.meetings, sources: m.sources } : column.kind === "category" ? { meetings: m.meetings.filter((x) => x.categoryID === column.id), sources: m.sources.filter((x) => x.categoryID === column.id) } : { meetings: m.meetings.filter((x) => !x.categoryID), sources: m.sources.filter((x) => !x.categoryID) };
  const title = column.kind === "all" ? tr("全部") : column.kind === "category" ? (m.category(column.id)?.name ?? tr("分类")) : tr("未分类");
  const toggleBrowsed = () => change(column.kind === "all" ? Scope.toggleAll(scope, meetings, sources) : Scope.toggleCategory(scope, column.kind === "category" ? column.id : null, meetings, sources));
  const same = (c: Column) => c.kind === column.kind && (c.kind !== "category" || (column.kind === "category" && column.id === c.id));
  const categoryRow = (key: string, title: string, count: number, state: ScopeCheck, dot: string | null, c: Column, toggle: () => void) => (
    <div key={key} className="flex items-center gap-2 rounded-[var(--r-tag)] px-2 py-1.5" style={{ background: same(c) ? "var(--surface-inset)" : "transparent" }}>
      <ScopeCheckBox state={state} onClick={toggle} />
      <button onClick={() => setColumn(c)} className="flex min-w-0 flex-1 items-center gap-2 text-left">
        {dot && <span className="h-2 w-2 shrink-0 rounded-full" style={{ background: dot }} />}
        <span className="font-secondary min-w-0 flex-1 truncate">{title}</span>
        <span className="font-caption text-[var(--text-2)]">{count}</span>
      </button>
    </div>
  );
  const itemRow = (key: string, title: string, detail: string, on: boolean, enabled: boolean, toggle: () => void) => (
    <button key={key} onClick={toggle} disabled={!enabled} className="flex w-full items-center gap-2 px-2 py-[5px] text-left disabled:opacity-55">
      <span className="flex h-[22px] w-[22px] shrink-0 items-center justify-center" style={{ color: on ? "var(--accent)" : "var(--text-2)" }}>
        <Icon name={on ? "checkmark.circle.fill" : "circle"} size={17} />
      </span>
      <span className="flex min-w-0 flex-col gap-0.5">
        <span className="font-secondary truncate" style={{ color: enabled ? "var(--text)" : "var(--text-2)" }}>{title}</span>
        <span className="font-caption text-[var(--text-2)]">{detail}</span>
      </span>
    </button>
  );
  return (
    <div className="pop-in flex h-[360px] w-[520px] flex-col overflow-hidden rounded-[var(--r-card)] border border-[var(--separator)] bg-[var(--surface)] shadow-[0_10px_44px_rgba(0,0,0,0.16)]">
      <div className="flex min-h-0 flex-1">
        <div className="scroll w-[188px] shrink-0 p-2">
          {categoryRow("all", tr("全部"), meetings.filter((x) => !x.live).length + sources.length, Scope.stateAll(scope, meetings, sources), null, { kind: "all" }, () => change(Scope.toggleAll(scope, meetings, sources)))}
          {[...m.categories].sort((a, b) => a.sortOrder - b.sortOrder).map((c) => categoryRow(c.id, c.name, count(c.id), Scope.state(scope, c.id, meetings, sources), CategoryPalette.ink(c.colorIndex), { kind: "category", id: c.id }, () => change(Scope.toggleCategory(scope, c.id, meetings, sources))))}
          {categoryRow("none", tr("未分类"), count(null), Scope.state(scope, null, meetings, sources), CategoryPalette.ink(CategoryPalette.uncategorizedIndex), { kind: "uncategorized" }, () => change(Scope.toggleCategory(scope, null, meetings, sources)))}
        </div>
        <div className="w-px bg-[var(--separator)]" />
        <div className="flex min-w-0 flex-1 flex-col">
          <div className="flex items-baseline px-4 pt-4 pb-2">
            <span className="font-section-title min-w-0 flex-1 truncate">{title}</span>
            {column.kind !== "all" && (
              <button onClick={toggleBrowsed} className="font-secondary font-medium text-[var(--accent)]">
                {tr("全选这个分类")}
              </button>
            )}
          </div>
          <div className="scroll min-h-0 flex-1 px-3 pb-3">
            {!visible.meetings.length && !visible.sources.length ? (
              <div className="font-secondary px-1 pt-3 text-[var(--text-2)]">{tr("这个分类里还没有内容。")}</div>
            ) : (
              <div className="flex flex-col gap-3">
                {visible.meetings.length > 0 && (
                  <div className="flex flex-col gap-0.5">
                    <div className="font-caption px-2 text-[var(--text-2)]">{tr("会议")}</div>
                    {visible.meetings.map((x) =>
                      itemRow(x.id, x.title, x.isLive ? tr("录制中") : formatMonthDay(toDate(x.startedAt)), !x.isLive && selectedMeetings.has(x.id), !x.isLive, () => {
                        const item = meetings.find((i) => i.id === x.id);
                        if (item) change(Scope.toggleMeeting(scope, item, meetings, sources));
                      }),
                    )}
                  </div>
                )}
                {visible.sources.length > 0 && (
                  <div className="flex flex-col gap-0.5">
                    <div className="font-caption px-2 text-[var(--text-2)]">{tr("资料")}</div>
                    {visible.sources.map((x) =>
                      itemRow(x.id, x.title, formatMonthDay(toDate(x.importedAt)), selectedSources.has(x.id), true, () => {
                        const item = sources.find((i) => i.id === x.id);
                        if (item) change(Scope.toggleSource(scope, item, meetings, sources));
                      }),
                    )}
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      </div>
      <div className="h-px bg-[var(--separator)]" />
      <div className="flex items-center justify-end gap-3 px-4 py-3">
        <button onClick={() => change(emptyScope())} className="font-secondary font-medium text-[var(--text-2)]">
          {tr("清空")}
        </button>
        <button onClick={onClose} className="press font-secondary rounded-full bg-[var(--accent)] px-3.5 py-1.5 font-medium text-[var(--on-accent)]">
          {tr("完成")}
        </button>
      </div>
    </div>
  );
}
