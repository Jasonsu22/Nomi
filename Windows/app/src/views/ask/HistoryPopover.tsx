// Pages/AskHistoryPopover.swift: earlier chats, searchable, grouped by day.
import { useState } from "react";
import { tr } from "../../i18n";
import { formatRelativeTime, toDate } from "../../support/format";
import { displayTitle, Scope, type ChatSession } from "../../models/chatSession";
import { useModel } from "../../app";
import { Icon } from "../ui/Icon";
import { Menu, pointAnchor } from "../ui/controls";

export function AskHistoryPopover({ anchorMeetingID, currentID, onRename, onDelete, onClose }: { anchorMeetingID: string | null; currentID: string | null; onRename: (s: ChatSession) => void; onDelete: (s: ChatSession) => void; onClose: () => void }) {
  const m = useModel();
  const [query, setQuery] = useState("");
  const [menu, setMenu] = useState<{ session: ChatSession; x: number; y: number } | null>(null);
  const pool = m.chatHistoryAnchored(anchorMeetingID);
  const needle = query.trim().toLowerCase();
  const sessions = needle ? pool.filter((s) => displayTitle(s).toLowerCase().includes(needle) || s.turns.some((t) => t.question.toLowerCase().includes(needle) || t.answer.toLowerCase().includes(needle))) : pool;
  const day = (d: Date) => d.toDateString();
  const today = day(new Date());
  const yesterday = day(new Date(Date.now() - 86_400_000));
  const groups = [
    { title: tr("今天"), match: (d: Date) => day(d) === today },
    { title: tr("昨天"), match: (d: Date) => day(d) === yesterday },
    { title: tr("更早"), match: (d: Date) => day(d) !== today && day(d) !== yesterday },
  ]
    .map((g) => ({ title: g.title, sessions: sessions.filter((s) => g.match(toDate(s.updatedAt))) }))
    .filter((g) => g.sessions.length);
  const scopeMeetings = m.chatMeetingItems(), scopeSources = m.chatSourceItems(), names = m.chatCategoryNames();
  const subtitle = (s: ChatSession) => {
    const meeting = s.anchorMeetingID ? m.meetings.find((x) => x.id === s.anchorMeetingID) : null;
    return meeting ? meeting.title : Scope.chipTitle(s.scope, scopeMeetings, scopeSources, names);
  };
  const current = currentID ?? m.currentChatID;
  return (
    <div className="pop-in flex flex-col overflow-hidden rounded-[var(--r-card)] border border-[var(--separator)] bg-[var(--surface)] shadow-[0_10px_44px_rgba(0,0,0,0.16)]" style={{ width: anchorMeetingID ? 300 : 360, maxHeight: !sessions.length ? 220 : anchorMeetingID ? 320 : 420, transformOrigin: "top right" }}>
      <div className="p-3">
        <input autoFocus value={query} onChange={(e) => setQuery(e.target.value)} placeholder={tr("搜索对话")} className="font-secondary w-full rounded-[var(--r-field)] bg-[var(--surface-inset)] px-3 py-2 outline-none" />
      </div>
      {!sessions.length ? (
        <div className="font-secondary flex min-h-[120px] flex-1 items-center justify-center text-[var(--text-2)]">{tr("还没有对话")}</div>
      ) : (
        <div className="scroll flex min-h-0 flex-col gap-3 px-2 pb-3">
          {groups.map((g) => (
            <div key={g.title} className="flex flex-col gap-0.5">
              <div className="font-caption px-2 pb-1 text-[var(--text-2)]">{g.title}</div>
              {g.sessions.map((s) => (
                <button
                  key={s.id}
                  onClick={() => {
                    m.openChat(s.id, anchorMeetingID);
                    onClose();
                  }}
                  onContextMenu={(e) => {
                    e.preventDefault();
                    setMenu({ session: s, x: e.clientX, y: e.clientY });
                  }}
                  className="flex items-start gap-2 rounded-[var(--r-tag)] px-3 py-2 text-left hover:bg-[var(--surface-inset)]"
                  style={{ background: s.id === current ? "var(--accent-soft)" : undefined }}
                >
                  <span className="flex min-w-0 flex-1 flex-col gap-[3px]">
                    <span className="font-secondary truncate font-medium">{displayTitle(s)}</span>
                    <span className="font-caption truncate text-[var(--text-2)]">{subtitle(s)}</span>
                  </span>
                  <span className="flex flex-col items-end gap-1">
                    <span className="font-caption whitespace-nowrap text-[var(--text-2)]">{formatRelativeTime(toDate(s.updatedAt))}</span>
                    {s.id === current && (
                      <span className="text-[var(--accent)]">
                        <Icon name="checkmark" size={11} weight={3} />
                      </span>
                    )}
                  </span>
                </button>
              ))}
            </div>
          ))}
        </div>
      )}
      {menu && (
        <Menu
          anchor={pointAnchor(menu.x, menu.y)}
          onClose={() => setMenu(null)}
          items={[
            { kind: "item", title: tr("重命名"), onSelect: () => onRename(menu.session) },
            { kind: "item", title: tr("删除"), destructive: true, onSelect: () => onDelete(menu.session) },
          ]}
        />
      )}
    </div>
  );
}
