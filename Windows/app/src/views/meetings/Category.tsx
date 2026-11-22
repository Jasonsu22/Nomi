// Categories/Category.swift and CategoryEditor.swift: the round icon, section titles, the editor.
import { useState } from "react";
import { tr, trf } from "../../i18n";
import { CategoryPalette, CategorySymbols } from "../../models/category";
import { Icon } from "../ui/Icon";

export type CategoryDraft = { name: string; colorIndex: number; symbol: string };
export const newDraft = (count: number): CategoryDraft => ({ name: "", colorIndex: count % CategoryPalette.swatches.length, symbol: CategorySymbols[0] });

export function CategoryIcon({ symbol, colorIndex, size = 32 }: { symbol: string; colorIndex: number; size?: number }) {
  return (
    <span className="flex shrink-0 items-center justify-center rounded-full" style={{ width: size, height: size, background: CategoryPalette.fill(colorIndex), color: CategoryPalette.ink(colorIndex) }} aria-hidden>
      <Icon name={symbol} size={size * 0.46} weight={2.2} />
    </span>
  );
}

export function CategorySectionTitle({ title, count, colorIndex }: { title: string; count: number; colorIndex?: number | null }) {
  return (
    <div className="flex items-center gap-2">
      {colorIndex != null && <span className="h-2 w-2 rounded-full" style={{ background: CategoryPalette.ink(colorIndex) }} />}
      <span className="font-section-title">{title}</span>
      <span className="font-caption text-[var(--text-2)]">{count}</span>
    </div>
  );
}

export function CategoryEditor({ title, initial, onSubmit }: { title: string; initial: CategoryDraft; onSubmit: (d: CategoryDraft) => void }) {
  const [draft, setDraft] = useState(initial);
  const canSubmit = draft.name.trim().length > 0;
  const submit = () => canSubmit && onSubmit(draft);
  return (
    <div className="flex w-[280px] flex-col gap-3.5 p-4">
      <div className="font-section-title">{title}</div>
      <input autoFocus value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} onKeyDown={(e) => e.key === "Enter" && submit()} placeholder={tr("分类名称")} className="font-body h-7 rounded-[6px] border border-[var(--separator)] bg-[var(--surface)] px-2 outline-none focus:border-[var(--accent)]" />
      <div className="font-caption text-[var(--text-2)]">{tr("颜色")}</div>
      <div className="flex gap-2">
        {CategoryPalette.swatches.map((_, i) => (
          <button key={i} onClick={() => setDraft({ ...draft, colorIndex: i })} aria-label={trf("颜色 %d", i + 1)} className="press rounded-full p-[3px]" style={{ boxShadow: draft.colorIndex === i ? "inset 0 0 0 1.5px var(--text)" : "none" }}>
            <span className="block h-4 w-4 rounded-full" style={{ background: CategoryPalette.ink(i) }} />
          </button>
        ))}
      </div>
      <div className="font-caption text-[var(--text-2)]">{tr("图标")}</div>
      <div className="grid grid-cols-4 gap-2">
        {CategorySymbols.map((s) => (
          <button key={s} onClick={() => setDraft({ ...draft, symbol: s })} aria-label={s} className="press flex h-[34px] items-center justify-center rounded-[8px]" style={{ background: draft.symbol === s ? "var(--selection)" : "var(--surface-inset)", color: draft.symbol === s ? "var(--on-selection)" : "var(--text)" }}>
            <Icon name={s} size={16} />
          </button>
        ))}
      </div>
      <button onClick={submit} disabled={!canSubmit} className="press font-secondary h-8 rounded-full font-semibold text-[var(--on-accent)]" style={{ background: canSubmit ? "var(--accent)" : "var(--outline)" }}>
        {tr("完成")}
      </button>
    </div>
  );
}

/** Category chips reorder by dragging one onto another. */
export function useCategoryDrag(id: string, move: (dragged: string, target: string) => void) {
  const [targeted, setTargeted] = useState(false);
  return {
    targeted,
    props: {
      draggable: true,
      onDragStart: (e: React.DragEvent) => e.dataTransfer.setData("text/nomi-category", id),
      onDragOver: (e: React.DragEvent) => {
        if (!e.dataTransfer.types.includes("text/nomi-category")) return;
        e.preventDefault();
        setTargeted(true);
      },
      onDragLeave: () => setTargeted(false),
      onDrop: (e: React.DragEvent) => {
        setTargeted(false);
        const dragged = e.dataTransfer.getData("text/nomi-category");
        if (dragged && dragged !== id) move(dragged, id);
      },
    },
  };
}
