// Meetings/MeetingListView.swift and DesignSystem/Components/MeetingCard.swift.
import { useEffect, useRef, useState } from "react";
import { tr, trf } from "../../i18n";
import { formatDuration, formatStartStamp, toDate } from "../../support/format";
import { CategoryPalette, sameFilter, type CategoryFilter, type MeetingCategory } from "../../models/category";
import type { Meeting } from "../../models/meeting";
import { useModel } from "../../app";
import { Icon } from "../ui/Icon";
import { Alert, CapsuleToggle, Menu, pointAnchor, NowDivider, PillButton, PillMenu, Popover, PromptAlert, Scroll, SearchField, SelectionMark, Sheet, TrailingBarSwap, type MenuEntry } from "../ui/controls";
import { CategoryEditor, CategoryIcon, CategorySectionTitle, newDraft, useCategoryDrag, type CategoryDraft } from "./Category";

type Section = { id: string; title: string; colorIndex: number | null; meetings: Meeting[]; showsNow: boolean };

const isToday = (m: Meeting) => toDate(m.startedAt).toDateString() === new Date().toDateString();
const sortMeetings = (a: Meeting, b: Meeting) => (a.isLive !== b.isLive ? (a.isLive ? -1 : 1) : b.startedAt - a.startedAt);

export function StartTimeEditor({ date, onChange, onDone }: { date: Date; onChange: (d: Date) => void; onDone: () => void }) {
  const two = (n: number) => String(n).padStart(2, "0");
  const value = `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())}T${two(date.getHours())}:${two(date.getMinutes())}`;
  return (
    <Sheet width={320} onClose={onDone}>
      <div className="flex flex-col gap-4 p-4">
        <div className="font-section-title">{tr("重设时间")}</div>
        <input type="datetime-local" value={value} onChange={(e) => e.target.value && onChange(new Date(e.target.value))} className="font-body h-8 rounded-[8px] border border-[var(--separator)] bg-[var(--surface)] px-2 outline-none" />
        <div className="flex justify-end">
          <button onClick={onDone} className="press font-secondary h-7 rounded-[7px] bg-[var(--surface-inset)] px-3 font-medium">{tr("完成")}</button>
        </div>
      </div>
    </Sheet>
  );
}

function LiveDot() {
  return <span className="live-dot h-[7px] w-[7px] rounded-full bg-[var(--accent)]" aria-label={tr("进行中")} />;
}

export function MeetingCard({ meeting, symbol, colorIndex, selected, onClick, onContextMenu }: { meeting: Meeting; symbol: string; colorIndex: number; selected: boolean | null; onClick: () => void; onContextMenu?: (e: React.MouseEvent) => void }) {
  const length = meeting.isLive ? tr("进行中") : formatDuration(meeting.duration);
  return (
    <button onClick={onClick} onContextMenu={onContextMenu} className="press flex w-full items-center rounded-[var(--r-card)] bg-[var(--surface)] p-4 text-left hover:bg-[var(--surface-inset)] active:scale-[0.99]">
      <SelectionMark selected={selected} />
      <span className="flex min-w-0 flex-1 items-center gap-3">
        <CategoryIcon symbol={symbol} colorIndex={colorIndex} />
        <span className="flex min-w-0 flex-1 flex-col gap-1.5">
          <span className="font-section-title truncate">{meeting.title}</span>
          <span className="font-secondary truncate text-[var(--text-2)]">{`${formatStartStamp(toDate(meeting.startedAt))} · ${length}`}</span>
        </span>
        {meeting.isLive ? (
          <span className="font-caption flex items-center gap-1.5 text-[var(--accent)]">
            <LiveDot />
            {tr("进行中")}
          </span>
        ) : (
          <span className="font-caption text-[var(--text-2)]">{formatDuration(meeting.duration)}</span>
        )}
      </span>
    </button>
  );
}

function Chip({ title, dot, selected, onClick, onContextMenu, drag, targeted }: { title: string; dot: string | null; selected: boolean; onClick: () => void; onContextMenu?: (e: React.MouseEvent) => void; drag?: object; targeted?: boolean }) {
  return (
    <button
      {...drag}
      onClick={onClick}
      onContextMenu={onContextMenu}
      className="press font-secondary relative flex h-8 shrink-0 items-center gap-1.5 rounded-full px-3 font-medium whitespace-nowrap"
      style={{ color: selected ? "var(--on-selection)" : "var(--text)", boxShadow: targeted ? "inset 0 0 0 1.5px var(--accent)" : undefined }}
    >
      <span className="absolute inset-0 rounded-full bg-[var(--selection)] transition-all duration-300" style={{ opacity: selected ? 1 : 0, transform: selected ? "none" : "scale(0.92)", transitionTimingFunction: "var(--ease-smooth)" }} />
      {dot && <span className="relative h-2 w-2 rounded-full" style={{ background: dot }} />}
      <span className="relative">{title}</span>
    </button>
  );
}

/** The category chips, shared by Meetings and Sources: a filter row with edit, delete and reorder. */
export function CategoryChips({ count, selected, onSelect }: { count: (f: CategoryFilter) => number; selected: CategoryFilter; onSelect: (f: CategoryFilter) => void }) {
  const m = useModel();
  const [creating, setCreating] = useState<HTMLElement | null>(null);
  const [editing, setEditing] = useState<{ category: MeetingCategory; el: HTMLElement } | null>(null);
  const [deleting, setDeleting] = useState<MeetingCategory | null>(null);
  const [menu, setMenu] = useState<{ category: MeetingCategory; x: number; y: number; el: HTMLElement } | null>(null);
  const sorted = [...m.categories].sort((a, b) => a.sortOrder - b.sortOrder);
  return (
    <div className="chip-strip flex items-center gap-2">
      <Chip title={trf("全部 %d", count({ kind: "all" }))} dot={null} selected={sameFilter(selected, { kind: "all" })} onClick={() => onSelect({ kind: "all" })} />
      {sorted.map((c) => (
        <CategoryChip
          key={c.id}
          category={c}
          title={`${c.name} ${count({ kind: "category", id: c.id })}`}
          selected={sameFilter(selected, { kind: "category", id: c.id })}
          onClick={() => onSelect({ kind: "category", id: c.id })}
          onContextMenu={(e) => {
            e.preventDefault();
            setMenu({ category: c, x: e.clientX, y: e.clientY, el: e.currentTarget as HTMLElement });
          }}
        />
      ))}
      <Chip title={trf("未分类 %d", count({ kind: "uncategorized" }))} dot={CategoryPalette.ink(CategoryPalette.uncategorizedIndex)} selected={sameFilter(selected, { kind: "uncategorized" })} onClick={() => onSelect({ kind: "uncategorized" })} />
      <button onClick={(e) => setCreating(e.currentTarget)} className="press font-secondary h-8 shrink-0 rounded-full border border-dashed border-[var(--outline)] px-3 font-medium whitespace-nowrap text-[var(--text-2)]">
        {tr("＋ 新建分类")}
      </button>
      {creating && (
        <Popover anchor={creating} onClose={() => setCreating(null)}>
          <div className="menu">
            <CategoryEditor
              title={tr("新建分类")}
              initial={newDraft(m.categories.length)}
              onSubmit={(d) => {
                m.addCategory(d.name, d.colorIndex, d.symbol);
                setCreating(null);
              }}
            />
          </div>
        </Popover>
      )}
      {menu && (
        <Menu
          anchor={pointAnchor(menu.x, menu.y)}
          onClose={() => setMenu(null)}
          items={[
            { kind: "item", title: tr("编辑"), onSelect: () => setEditing({ category: menu.category, el: menu.el }) },
            { kind: "item", title: tr("删除"), destructive: true, onSelect: () => setDeleting(menu.category) },
          ]}
        />
      )}
      {editing && (
        <Popover anchor={editing.el} onClose={() => setEditing(null)}>
          <div className="menu">
            <CategoryEditor
              title={tr("编辑分类")}
              initial={{ name: editing.category.name, colorIndex: editing.category.colorIndex, symbol: editing.category.symbol }}
              onSubmit={(d) => {
                m.updateCategory(editing.category.id, d.name, d.colorIndex, d.symbol);
                setEditing(null);
              }}
            />
          </div>
        </Popover>
      )}
      {deleting && (
        <Alert
          title={trf("删除分类「%@」？", deleting.name)}
          message={tr("这个分类下的会议和资料会变成未分类。")}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setDeleting(null) },
            {
              title: tr("删除分类"),
              role: "destructive",
              onClick: () => {
                m.deleteCategory(deleting.id);
                setDeleting(null);
              },
            },
          ]}
        />
      )}
    </div>
  );
}

function CategoryChip({ category, title, selected, onClick, onContextMenu }: { category: MeetingCategory; title: string; selected: boolean; onClick: () => void; onContextMenu: (e: React.MouseEvent) => void }) {
  const m = useModel();
  const { props, targeted } = useCategoryDrag(category.id, (a, b) => m.placeCategory(a, b));
  return (
    <span title={tr("拖动调整顺序")} className="flex shrink-0">
      <Chip title={title} dot={CategoryPalette.ink(category.colorIndex)} selected={selected} onClick={onClick} onContextMenu={onContextMenu} drag={props} targeted={targeted} />
    </span>
  );
}

/** "Move to category" menu items, then "New category". */
export function categoryMoveItems(categories: MeetingCategory[], move: (id: string | null) => void, create: () => void): MenuEntry[] {
  return [
    { kind: "item", title: tr("未分类"), onSelect: () => move(null) },
    ...[...categories].sort((a, b) => a.sortOrder - b.sortOrder).map((c): MenuEntry => ({ kind: "item", title: c.name, onSelect: () => move(c.id) })),
    { kind: "divider" },
    { kind: "item", title: tr("新建分类"), icon: "plus", onSelect: create },
  ];
}

export function MeetingListView() {
  const m = useModel();
  const search = useRef<HTMLInputElement>(null);
  const [managing, setManaging] = useState(false);
  const [selectedIDs, setSelected] = useState<Set<string>>(new Set());
  const [renaming, setRenaming] = useState<Meeting | null>(null);
  const [resettingTime, setResetting] = useState<Meeting | null>(null);
  const [deletingMeeting, setDeletingMeeting] = useState<Meeting | null>(null);
  const [bulkDelete, setBulkDelete] = useState(false);
  const [creatingForMove, setCreatingForMove] = useState<Set<string> | null>(null);
  const [cardMenu, setCardMenu] = useState<{ meeting: Meeting; x: number; y: number } | null>(null);

  useEffect(() => {
    if (m.searchRequest) search.current?.focus();
  }, [m.searchRequest]);

  const visible = m.visibleMeetings;
  const move = (ids: Set<string>, categoryID: string | null) => ids.size && m.assign(ids, categoryID);
  const remove = (ids: Set<string>, leave = false) => {
    m.deleteMeetings(ids);
    setSelected((s) => new Set([...s].filter((id) => !ids.has(id))));
    if (leave)
      setTimeout(() => {
        setManaging(false);
        setSelected(new Set());
      }, 320);
  };
  const toggle = (meeting: Meeting) => {
    if (managing) {
      if (meeting.isLive) return;
      setSelected((s) => {
        const next = new Set(s);
        if (next.has(meeting.id)) next.delete(meeting.id);
        else next.add(meeting.id);
        return next;
      });
    } else m.openMeeting(meeting.id);
  };
  const moveTargets = (meeting: Meeting) => (managing && selectedIDs.has(meeting.id) ? selectedIDs : new Set([meeting.id]));

  const sections = (): Section[] => {
    if (m.grouping === "time") {
      const today = visible.filter(isToday).sort(sortMeetings);
      const earlier = visible.filter((x) => !isToday(x)).sort((a, b) => b.startedAt - a.startedAt);
      const searching = m.appliedQuery.trim().length > 0;
      const out: Section[] = [];
      if (today.length) out.push({ id: "today", title: tr("今天"), colorIndex: null, meetings: today, showsNow: !searching });
      if (earlier.length) out.push({ id: "earlier", title: tr("更早"), colorIndex: null, meetings: earlier, showsNow: false });
      return out;
    }
    const out: Section[] = [];
    for (const c of [...m.categories].sort((a, b) => a.sortOrder - b.sortOrder)) {
      const items = visible.filter((x) => x.categoryID === c.id).sort(sortMeetings);
      if (items.length) out.push({ id: c.id, title: c.name, colorIndex: c.colorIndex, meetings: items, showsNow: false });
    }
    const loose = visible.filter((x) => !x.categoryID).sort(sortMeetings);
    if (loose.length) out.push({ id: "none", title: tr("未分类"), colorIndex: CategoryPalette.uncategorizedIndex, meetings: loose, showsNow: false });
    return out;
  };

  const cardItems = (meeting: Meeting): MenuEntry[] => [
    { kind: "item", title: tr("打开"), onSelect: () => m.openMeeting(meeting.id) },
    { kind: "item", title: tr("重命名"), onSelect: () => setRenaming(meeting) },
    { kind: "item", title: tr("重设时间"), onSelect: () => setResetting(meeting) },
    { kind: "submenu", title: tr("移到分类"), items: categoryMoveItems(m.categories, (id) => move(moveTargets(meeting), id), () => setCreatingForMove(moveTargets(meeting))) },
    { kind: "item", title: tr("导出"), onSelect: () => void m.export([meeting]) },
    ...(meeting.isLive ? [] : [{ kind: "item", title: tr("删除"), destructive: true, onSelect: () => setDeletingMeeting(meeting) } as MenuEntry]),
  ];

  const none = selectedIDs.size === 0;
  return (
    <Scroll className="h-full">
      <div className="mx-auto flex max-w-[1200px] flex-col gap-6 pt-7 pr-8 pb-12 pl-12">
        <div className="flex h-9 items-center gap-3">
          <h1 className="font-page-title">{tr("会议")}</h1>
          <div className="flex-1" />
          <TrailingBarSwap
            managing={managing}
            idle={
              <>
                <PillButton
                  title={tr("管理")}
                  onClick={() => {
                    setSelected(new Set());
                    setManaging(true);
                  }}
                />
                <CapsuleToggle value={m.grouping} onChange={(g) => (m.grouping = g)} options={[{ value: "time", title: tr("时间") }, { value: "category", title: tr("分类") }]} />
              </>
            }
            manage={
              <>
                <span className="font-secondary font-medium text-[var(--text-2)]">{trf("已选 %d", selectedIDs.size)}</span>
                <PillButton title={tr("全选")} onClick={() => setSelected(new Set(m.visibleMeetings.filter((x) => !x.isLive).map((x) => x.id)))} />
                <PillButton
                  title={tr("完成")}
                  onClick={() => {
                    setManaging(false);
                    setSelected(new Set());
                  }}
                />
                <span title={tr("把选中的会议存成 Markdown")}>
                  <PillButton title={tr("导出")} disabled={none} onClick={() => void m.export(m.meetings.filter((x) => selectedIDs.has(x.id)))} />
                </span>
                <PillMenu title={tr("移到分类")} enabled={!none} items={categoryMoveItems(m.categories, (id) => move(selectedIDs, id), () => setCreatingForMove(new Set(selectedIDs)))} />
                <PillButton title={tr("删除")} tint="var(--danger)" disabled={none} onClick={() => setBulkDelete(true)} />
              </>
            }
          />
        </div>
        <SearchField value={m.query} onChange={(q) => (m.query = q)} inputRef={search} />
        <CategoryChips count={(f) => m.count(f)} selected={m.activeFilter} onSelect={(f) => (m.filter = f)} />
        {m.meetings.length === 0 ? (
          <div className="surface flex flex-col items-center gap-3 py-12">
            <span className="flex h-16 w-16 items-center justify-center rounded-full bg-[var(--accent-soft)] text-[var(--accent)]">
              <Icon name="waveform" size={26} />
            </span>
            <div className="font-section-title">{tr("还没有会议")}</div>
            <div className="font-secondary text-center text-[var(--text-2)]">{tr("上课时点「开始转录」，录下的课堂和转写都会出现在这里。")}</div>
            <button onClick={() => m.prepareRecording()} disabled={!m.canStart} className="press font-secondary mt-2 inline-flex h-8 items-center gap-1.5 rounded-[8px] bg-[var(--accent)] px-3.5 font-medium text-[var(--on-accent)] disabled:opacity-40">
              <Icon name="waveform" size={14} />
              {tr("开始转录")}
            </button>
          </div>
        ) : visible.length === 0 ? (
          <div className="font-secondary pt-4 text-[var(--text-2)]">{tr("没有匹配的会议")}</div>
        ) : (
          <div className="flex flex-col gap-6">
            {sections().map((section) => (
              <div key={section.id} className="fade-in flex flex-col gap-3">
                <CategorySectionTitle title={section.title} count={section.meetings.length} colorIndex={section.colorIndex} />
                {section.showsNow && <NowDivider />}
                <div className="flex flex-col gap-3">
                  {section.meetings.map((meeting) => {
                    const c = m.category(meeting.categoryID);
                    return (
                      <div key={meeting.id} className="card-in">
                        <MeetingCard
                          meeting={meeting}
                          symbol={c?.symbol ?? CategoryPalette.uncategorizedSymbol}
                          colorIndex={c?.colorIndex ?? CategoryPalette.uncategorizedIndex}
                          selected={managing && !meeting.isLive ? selectedIDs.has(meeting.id) : null}
                          onClick={() => toggle(meeting)}
                          onContextMenu={(e) => {
                            e.preventDefault();
                            setCardMenu({ meeting, x: e.clientX, y: e.clientY });
                          }}
                        />
                      </div>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
      {cardMenu && <Menu anchor={pointAnchor(cardMenu.x, cardMenu.y)} items={cardItems(cardMenu.meeting)} onClose={() => setCardMenu(null)} />}
      {resettingTime && <StartTimeEditor date={m.startDate(m.meetings.find((x) => x.id === resettingTime.id) ?? resettingTime)} onChange={(d) => m.setStartTime(resettingTime.id, d)} onDone={() => setResetting(null)} />}
      {renaming && (
        <PromptAlert
          title={tr("重命名")}
          value={renaming.title}
          placeholder={tr("名称")}
          onCancel={() => setRenaming(null)}
          onConfirm={(v) => {
            m.rename(renaming.id, v);
            setRenaming(null);
          }}
        />
      )}
      {deletingMeeting && (
        <Alert
          title={tr("删除这场会议？")}
          message={tr("转写会一起删掉。")}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setDeletingMeeting(null) },
            {
              title: tr("删除"),
              role: "destructive",
              onClick: () => {
                remove(new Set([deletingMeeting.id]));
                setDeletingMeeting(null);
              },
            },
          ]}
        />
      )}
      {bulkDelete && (
        <Alert
          title={trf("删除这 %d 场会议？", selectedIDs.size)}
          message={tr("转写和录音会一起删掉，删掉之后无法恢复。")}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setBulkDelete(false) },
            {
              title: tr("删除"),
              role: "destructive",
              onClick: () => {
                remove(new Set(selectedIDs), true);
                setBulkDelete(false);
              },
            },
          ]}
        />
      )}
      {creatingForMove && (
        <Sheet width={280} onClose={() => setCreatingForMove(null)}>
          <CategoryEditor
            title={tr("新建分类")}
            initial={newDraft(m.categories.length)}
            onSubmit={(d: CategoryDraft) => {
              const id = m.addCategory(d.name, d.colorIndex, d.symbol, false);
              if (id) move(creatingForMove, id);
              setCreatingForMove(null);
            }}
          />
        </Sheet>
      )}
    </Scroll>
  );
}
