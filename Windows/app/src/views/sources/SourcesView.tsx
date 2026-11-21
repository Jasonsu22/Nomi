// Pages/SourcesView.swift: the library of course files, grouped by category, and the Add sheet.
import { useEffect, useRef, useState } from "react";
import { tr, trf } from "../../i18n";
import { formatRelativeTime, toDate } from "../../support/format";
import { CategoryPalette, sameFilter, type CategoryFilter } from "../../models/category";
import { matchingSources, type KnowledgeSource } from "../../models/knowledgeSource";
import { SourceText } from "../../models/sourceText";
import { SourceStore } from "../../app/stores";
import { useModel } from "../../app";
import { dialogs, fs, paths, shell } from "../../platform";
import { Icon } from "../ui/Icon";
import { Alert, CapsuleToggle, Menu, PillButton, PillMenu, Popover, PopUp, PromptAlert, Scroll, SearchField, SelectionMark, Sheet, TrailingBarSwap, pointAnchor, type MenuEntry } from "../ui/controls";
import { DropOutline, sourceFilters, useFileDrop } from "../ui/fileDrop";
import { CategoryEditor, CategorySectionTitle, newDraft } from "../meetings/Category";
import { CategoryChips, categoryMoveItems } from "../meetings/MeetingList";

type Sort = "name" | "imported";

function SourceIcon({ fileName }: { fileName: string }) {
  const ext = paths.ext(fileName);
  const symbol = ext === "pdf" ? "doc.richtext" : ["ppt", "pptx", "key"].includes(ext) ? "rectangle.on.rectangle" : ["png", "jpg", "jpeg", "heic"].includes(ext) ? "photo" : "doc";
  return (
    <span className="flex w-[22px] shrink-0 justify-center" style={{ color: ext === "pdf" ? "#db5247" : "var(--text-2)" }}>
      <Icon name={symbol} size={17} />
    </span>
  );
}

export function SourcesView() {
  const m = useModel();
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<CategoryFilter>({ kind: "all" });
  const [sort, setSort] = useState<Sort>("imported");
  const [grouped, setGrouped] = useState(true);
  const [managing, setManaging] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [adding, setAdding] = useState(false);
  const [staged, setStaged] = useState<KnowledgeSource[]>([]);
  const [renaming, setRenaming] = useState<KnowledgeSource | null>(null);
  const [deleting, setDeleting] = useState<KnowledgeSource | null>(null);
  const [bulkDelete, setBulkDelete] = useState(false);
  const [creatingForMove, setCreatingForMove] = useState<Set<string> | null>(null);
  const [rowMenu, setRowMenu] = useState<{ source: KnowledgeSource; x: number; y: number } | null>(null);
  const [tagMenu, setTagMenu] = useState<{ source: KnowledgeSource; el: HTMLElement } | null>(null);

  const active: CategoryFilter = filter.kind === "category" && !m.category(filter.id) ? { kind: "all" } : filter;
  const matched = matchingSources(m.sources, query, active);
  const visible = sort === "name" ? [...matched].sort((a, b) => a.title.localeCompare(b.title, undefined, { numeric: true })) : [...matched].sort((a, b) => b.importedAt - a.importedAt);
  const defaultCategory = active.kind === "category" ? active.id : null;

  const stage = async (files: string[]) => {
    const added: KnowledgeSource[] = [];
    let rejected: string | null = null;
    for (const file of files) {
      if (SourceStore.sourceID(file)) continue;
      if (!SourceStore.accepts(file)) {
        rejected ??= file;
        continue;
      }
      try {
        added.push(await SourceStore.stage(file, defaultCategory));
      } catch (e) {
        m.noteError("sourceError", e);
      }
    }
    if (rejected) m.set("sourceError", SourceText.refusal(rejected));
    if (!added.length) return;
    setStaged((s) => [...s, ...added]);
    setAdding(true);
  };
  const { ref: dropRef, targeted } = useFileDrop((p) => void stage(p), !adding);
  const move = (ids: Set<string>, id: string | null) => ids.size && m.assignSources(ids, id);
  const targets = (s: KnowledgeSource) => (managing && selected.has(s.id) ? selected : new Set([s.id]));
  const remove = (ids: Set<string>, leave = false) => {
    m.deleteSources(ids);
    setSelected((s) => new Set([...s].filter((x) => !ids.has(x))));
    if (leave)
      setTimeout(() => {
        setManaging(false);
        setSelected(new Set());
      }, 320);
  };
  const download = async (s: KnowledgeSource) => {
    const destination = await dialogs.save(s.fileName);
    const file = SourceStore.fileURL(s);
    if (!destination || destination.toLowerCase() === file.toLowerCase()) return;
    try {
      await fs.copy(file, destination);
    } catch (e) {
      m.noteError("sourceError", e);
    }
  };
  const rowItems = (s: KnowledgeSource): MenuEntry[] => [
    { kind: "item", title: tr("重命名"), onSelect: () => setRenaming(s) },
    { kind: "submenu", title: tr("移到分类"), items: categoryMoveItems(m.categories, (id) => move(targets(s), id), () => setCreatingForMove(targets(s))) },
    { kind: "item", title: tr("在资源管理器中显示"), onSelect: () => void shell.reveal(SourceStore.fileURL(s)) },
    { kind: "item", title: tr("下载"), onSelect: () => void download(s) },
    { kind: "item", title: tr("删除"), destructive: true, onSelect: () => setDeleting(s) },
  ];
  const count = (f: CategoryFilter) => matchingSources(m.sources, "", f).length;
  const summary = active.kind === "all" ? trf("%d 份资料", visible.length) : active.kind === "uncategorized" ? trf("%d 份资料 · 未分类会议 %d 场", visible.length, m.count(active)) : trf("%d 份资料 · 这个分类里有 %d 场会议", visible.length, m.count(active));

  const sections = () => {
    const out: { id: string; title: string; colorIndex: number; sources: KnowledgeSource[] }[] = [];
    for (const c of [...m.categories].sort((a, b) => a.sortOrder - b.sortOrder)) {
      const items = visible.filter((s) => s.categoryID === c.id);
      if (items.length) out.push({ id: c.id, title: c.name, colorIndex: c.colorIndex, sources: items });
    }
    const loose = visible.filter((s) => !s.categoryID);
    if (loose.length) out.push({ id: "none", title: tr("未分类"), colorIndex: CategoryPalette.uncategorizedIndex, sources: loose });
    return out;
  };
  const card = (sources: KnowledgeSource[]) => (
    <div className="surface overflow-hidden">
      {sources.map((s, i) => (
        <div key={s.id}>
          {i > 0 && <div className="h-px bg-[var(--separator)]" />}
          <div
            className="font-caption flex items-center gap-3 px-4 py-3.5 text-[var(--text-2)] hover:bg-[var(--surface-inset)]"
            draggable={false}
            onContextMenu={(e) => {
              e.preventDefault();
              setRowMenu({ source: s, x: e.clientX, y: e.clientY });
            }}
          >
            <button
              onClick={() => {
                if (!managing) return void shell.openPath(SourceStore.fileURL(s));
                setSelected((cur) => {
                  const next = new Set(cur);
                  if (next.has(s.id)) next.delete(s.id);
                  else next.add(s.id);
                  return next;
                });
              }}
              className="flex min-w-0 flex-1 items-center text-left"
            >
              <SelectionMark selected={managing ? selected.has(s.id) : null} />
              <span className="flex min-w-0 flex-1 items-center gap-3">
                <SourceIcon fileName={s.fileName} />
                <span className="font-secondary min-w-0 flex-1 truncate font-semibold text-[var(--text)]">{s.title}</span>
                <span className="w-[110px] shrink-0">{formatRelativeTime(toDate(s.importedAt))}</span>
              </span>
            </button>
            {!managing && (
              <span className="flex items-center gap-2">
                <button onClick={(e) => setTagMenu({ source: s, el: e.currentTarget })} title={tr("移到分类")} className="flex h-5 w-5 items-center justify-center">
                  <Icon name="tag" size={14} />
                </button>
                <button onClick={() => setDeleting(s)} title={tr("删除")} className="text-[var(--danger)]">
                  <Icon name="trash" size={14} />
                </button>
              </span>
            )}
          </div>
        </div>
      ))}
    </div>
  );
  const none = selected.size === 0;
  return (
    <div ref={dropRef} className="relative h-full">
      <Scroll className="h-full">
        <div className="mx-auto flex max-w-[1200px] flex-col gap-6 pt-7 pr-8 pb-12 pl-12">
          <div className="flex h-9 items-center gap-3">
            <h1 className="font-page-title">{tr("资料")}</h1>
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
                  <CapsuleToggle value={sort} onChange={setSort} options={[{ value: "name", title: tr("名称") }, { value: "imported", title: tr("时间") }]} />
                  <button onClick={() => setGrouped(!grouped)} title={tr("按分类分组")} className="rounded-full bg-[var(--surface)] p-[3px]">
                    <span className="press font-secondary flex h-[30px] items-center rounded-full px-3 font-medium" style={{ background: grouped ? "var(--selection)" : "transparent", color: grouped ? "var(--on-selection)" : "var(--text-2)" }}>
                      {tr("分类")}
                    </span>
                  </button>
                </>
              }
              manage={
                <>
                  <span className="font-secondary font-medium text-[var(--text-2)]">{trf("已选 %d", selected.size)}</span>
                  <PillButton title={tr("全选")} onClick={() => setSelected(new Set(visible.map((s) => s.id)))} />
                  <PillButton
                    title={tr("完成")}
                    onClick={() => {
                      setManaging(false);
                      setSelected(new Set());
                    }}
                  />
                  <span title={tr("把选中的资料按分类复制出去。")}>
                    <PillButton title={tr("下载")} disabled={none} onClick={() => void m.downloadSourcesByCategory(selected)} />
                  </span>
                  <PillMenu title={tr("移到分类")} enabled={!none} items={categoryMoveItems(m.categories, (id) => move(selected, id), () => setCreatingForMove(new Set(selected)))} />
                  <PillButton title={tr("删除")} tint="var(--danger)" disabled={none} onClick={() => setBulkDelete(true)} />
                </>
              }
            />
          </div>
          <div className="flex items-center gap-3">
            <div className="flex-1">
              <SearchField value={query} onChange={setQuery} prompt={tr("搜索资料")} />
            </div>
            <button
              onClick={() => {
                setStaged([]);
                setAdding(true);
              }}
              className="press font-secondary inline-flex h-10 items-center gap-1.5 rounded-full bg-[var(--accent)] px-4 font-semibold text-[var(--on-accent)]"
            >
              <Icon name="plus" size={14} weight={2.6} />
              {tr("添加资料")}
            </button>
          </div>
          <CategoryChips count={count} selected={active} onSelect={setFilter} />
          <div className="font-secondary flex items-center gap-3 text-[var(--text-2)]">
            {summary}
            {!sameFilter(active, { kind: "all" }) && (
              <button
                onClick={() => {
                  m.filter = active;
                  m.openMeetingID = null;
                  m.select("meetings");
                }}
                className="font-medium text-[var(--accent)]"
              >
                {tr("查看会议")}
              </button>
            )}
          </div>
          {visible.length === 0 ? (
            <div className="surface flex flex-col gap-2 p-6">
              <div className="font-section-title">{m.sources.length === 0 ? tr("还没有资料") : tr("没有匹配的资料")}</div>
              <div className="font-secondary text-[var(--text-2)]">{tr("把课件加到课程分类里。分类和会议是同一套，一份资料就对应这个课的转录。")}</div>
            </div>
          ) : grouped ? (
            <div className="flex flex-col gap-6">
              {sections().map((s) => (
                <div key={s.id} className="fade-in flex flex-col gap-3">
                  <CategorySectionTitle title={s.title} count={s.sources.length} colorIndex={s.colorIndex} />
                  {card(s.sources)}
                </div>
              ))}
            </div>
          ) : (
            card(visible)
          )}
        </div>
      </Scroll>
      <DropOutline shown={targeted} inset={16} />
      {rowMenu && <Menu anchor={pointAnchor(rowMenu.x, rowMenu.y)} items={rowItems(rowMenu.source)} onClose={() => setRowMenu(null)} />}
      {tagMenu && <Menu anchor={tagMenu.el} align="end" items={categoryMoveItems(m.categories, (id) => move(new Set([tagMenu.source.id]), id), () => setCreatingForMove(new Set([tagMenu.source.id])))} onClose={() => setTagMenu(null)} />}
      {adding && (
        <AddSourceSheet
          staged={staged}
          setStaged={setStaged}
          onStage={(p) => void stage(p)}
          onCancel={() => {
            m.discardSources(staged);
            setStaged([]);
            setAdding(false);
          }}
          onCommit={() => {
            m.commitSources(staged);
            setStaged([]);
            setAdding(false);
          }}
        />
      )}
      {renaming && (
        <PromptAlert
          title={tr("重命名")}
          value={renaming.title}
          placeholder={tr("名称")}
          onCancel={() => setRenaming(null)}
          onConfirm={(v) => {
            m.renameSource(renaming.id, v);
            setRenaming(null);
          }}
        />
      )}
      {deleting && (
        <Alert
          title={tr("删除这份资料？")}
          message={tr("资料库里的副本会被删掉，原来的文件还在。")}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setDeleting(null) },
            {
              title: tr("删除"),
              role: "destructive",
              onClick: () => {
                remove(new Set([deleting.id]));
                setDeleting(null);
              },
            },
          ]}
        />
      )}
      {bulkDelete && (
        <Alert
          title={trf("删除这 %d 份资料？", selected.size)}
          message={tr("资料库里的副本会被删掉，原来的文件还在。")}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setBulkDelete(false) },
            {
              title: tr("删除"),
              role: "destructive",
              onClick: () => {
                remove(new Set(selected), true);
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
            onSubmit={(d) => {
              const id = m.addCategory(d.name, d.colorIndex, d.symbol, false);
              if (id) move(creatingForMove, id);
              setCreatingForMove(null);
            }}
          />
        </Sheet>
      )}
      {m.sourceError && <Alert title={tr("资料")} message={m.sourceError} actions={[{ title: tr("好"), role: "cancel", onClick: () => m.set("sourceError", null) }]} />}
    </div>
  );
}

function AddSourceSheet({ staged, setStaged, onStage, onCancel, onCommit }: { staged: KnowledgeSource[]; setStaged: (f: (s: KnowledgeSource[]) => KnowledgeSource[]) => void; onStage: (paths: string[]) => void; onCancel: () => void; onCommit: () => void }) {
  const m = useModel();
  const { ref, targeted } = useFileDrop(onStage);
  const [creatingFor, setCreatingFor] = useState<{ id: string; el: HTMLElement } | null>(null);
  const pick = async () => onStage(await dialogs.openFiles(sourceFilters()));
  const update = (id: string, change: Partial<KnowledgeSource>) => setStaged((s) => s.map((x) => (x.id === id ? { ...x, ...change } : x)));
  const canAdd = staged.length > 0 && !staged.some((s) => !s.title.trim());
  const first = useRef(true);
  useEffect(() => {
    if (first.current && !staged.length) void pick();
    first.current = false;
  }, []);
  return (
    <Sheet width={520} onClose={onCancel}>
      <div ref={ref} className="flex flex-col gap-4 bg-[var(--canvas)] p-6">
        <div className="font-detail-title">{tr("添加资料")}</div>
        <div className="font-secondary text-[var(--text-2)]">{tr("文件会复制进资料库，原来的文件还在原处。分类和会议用的是同一套。")}</div>
        <button
          onClick={() => void pick()}
          aria-label={tr("把 PDF、幻灯片、文档或图片拖到这里，或点击选择")}
          className="flex flex-col items-center justify-center gap-2 rounded-[var(--r-card)] border-dashed px-4 transition-colors"
          style={{ height: staged.length ? 96 : 140, color: targeted ? "var(--accent)" : "var(--text-2)", background: targeted ? "color-mix(in srgb, var(--accent) 8%, transparent)" : "var(--surface-inset)", borderWidth: targeted ? 2 : 1, borderColor: targeted ? "var(--accent)" : "var(--outline)" }}
        >
          <Icon name="arrow.down.doc" size={22} />
          <span className="font-secondary text-center">{tr("把 PDF、幻灯片、文档或图片拖到这里，或点击选择")}</span>
        </button>
        {staged.length > 0 && (
          <div className="surface scroll max-h-[300px]">
            {staged.map((s) => (
              <div key={s.id} className="flex items-center gap-3 p-4">
                <div className="flex min-w-0 flex-1 flex-col gap-1.5">
                  <input value={s.title} onChange={(e) => update(s.id, { title: e.target.value })} placeholder={tr("名称")} className="font-secondary bg-transparent font-semibold outline-none" />
                  <div>
                    <PopUp value={s.categoryID ?? ""} onChange={(v) => update(s.id, { categoryID: v || null })} options={[{ value: "", title: tr("未分类") }, ...[...m.categories].sort((a, b) => a.sortOrder - b.sortOrder).map((c) => ({ value: c.id, title: c.name }))]} />
                  </div>
                </div>
                <button onClick={(e) => setCreatingFor({ id: s.id, el: e.currentTarget })} title={tr("新建分类")} className="text-[var(--text-2)]">
                  <Icon name="folder.badge.plus" size={16} />
                </button>
                <button
                  onClick={() => {
                    m.discardSources([s]);
                    setStaged((list) => list.filter((x) => x.id !== s.id));
                  }}
                  title={tr("删除")}
                  className="text-[var(--danger)]"
                >
                  <Icon name="trash" size={15} />
                </button>
              </div>
            ))}
          </div>
        )}
        <div className="flex justify-end gap-2">
          <button onClick={onCancel} className="press font-secondary h-7 rounded-[7px] bg-[var(--surface)] px-3 font-medium">
            {tr("取消")}
          </button>
          <button onClick={onCommit} disabled={!canAdd} className="press font-secondary h-7 rounded-[7px] bg-[var(--accent)] px-3 font-medium text-[var(--on-accent)] disabled:opacity-40">
            {tr("添加")}
          </button>
        </div>
      </div>
      {creatingFor && (
        <Popover anchor={creatingFor.el} onClose={() => setCreatingFor(null)} align="end">
          <div className="menu">
            <CategoryEditor
              title={tr("新建分类")}
              initial={newDraft(m.categories.length)}
              onSubmit={(d) => {
                const id = m.addCategory(d.name, d.colorIndex, d.symbol, false);
                if (id) update(creatingFor.id, { categoryID: id });
                setCreatingFor(null);
              }}
            />
          </div>
        </Popover>
      )}
    </Sheet>
  );
}
