// The Mac's shared controls: pills, menus, settings rows and switches, status chip, search field,
// sheets and alerts, the fading scroll area, the jump pill. Styled after macOS, with Windows type.
import { createPortal } from "react-dom";
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { tr } from "../../i18n";
import { Icon } from "./Icon";

// MARK: Pills

export function PillButton({ title, onClick, tint, disabled, className = "", icon }: { title: string; onClick?: () => void; tint?: string; disabled?: boolean; className?: string; icon?: string }) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`press font-secondary inline-flex shrink-0 items-center gap-1.5 rounded-full bg-[var(--surface)] px-3.5 py-2 font-medium whitespace-nowrap hover:bg-[var(--surface-inset)] disabled:opacity-40 ${className}`}
      style={{ color: tint ?? "var(--text)" }}
    >
      {icon && <Icon name={icon} size={14} />}
      {title}
    </button>
  );
}

export type MenuEntry =
  | { kind: "item"; title: string; onSelect: () => void; checked?: boolean; destructive?: boolean; disabled?: boolean; icon?: string }
  | { kind: "divider" }
  | { kind: "header"; title: string }
  | { kind: "submenu"; title: string; items: MenuEntry[] };

export function PillMenu({ title, items, enabled = true, className = "" }: { title: string; items: MenuEntry[]; enabled?: boolean; className?: string }) {
  const [open, setOpen] = useState(false);
  const anchor = useRef<HTMLButtonElement>(null);
  return (
    <>
      <button
        ref={anchor}
        disabled={!enabled}
        onClick={() => setOpen(!open)}
        className={`press font-secondary inline-flex shrink-0 items-center rounded-full bg-[var(--surface)] px-3.5 py-2 font-medium whitespace-nowrap hover:bg-[var(--surface-inset)] disabled:opacity-40 ${className}`}
      >
        {title}
      </button>
      {open && <Menu anchor={anchor.current} items={items} onClose={() => setOpen(false)} />}
    </>
  );
}

/** A pop-up menu anchored under (or above) an element, like a native menu. */
export function Menu({ anchor, items, onClose, align = "start", width }: { anchor: HTMLElement | null; items: MenuEntry[]; onClose: () => void; align?: "start" | "end"; width?: number }) {
  return (
    <Popover anchor={anchor} onClose={onClose} align={align}>
      <div className="menu py-1.5" style={{ minWidth: width ?? 200 }}>
        <MenuList items={items} onClose={onClose} />
      </div>
    </Popover>
  );
}

function MenuList({ items, onClose }: { items: MenuEntry[]; onClose: () => void }) {
  const [sub, setSub] = useState<{ index: number; el: HTMLElement } | null>(null);
  return (
    <>
      {items.map((item, index) => {
        if (item.kind === "divider") return <div key={index} className="mx-2.5 my-1 h-px bg-[var(--separator)]" />;
        if (item.kind === "header") return <div key={index} className="font-caption px-3 pt-1.5 pb-1 text-[var(--text-2)]">{item.title}</div>;
        if (item.kind === "submenu")
          return (
            <div key={index} onMouseEnter={(e) => setSub({ index, el: e.currentTarget })}>
              <button className="font-body flex w-full items-center gap-2 rounded-[6px] px-3 py-1 text-left hover:bg-[var(--accent)] hover:text-[var(--on-accent)]" style={{ width: "calc(100% - 10px)", margin: "0 5px" }}>
                <span className="flex-1 truncate">{item.title}</span>
                <Icon name="chevron.right" size={12} />
              </button>
              {sub?.index === index && (
                <Popover anchor={sub.el} onClose={onClose} side="right">
                  <div className="menu py-1.5" style={{ minWidth: 180 }}>
                    <MenuList items={item.items} onClose={onClose} />
                  </div>
                </Popover>
              )}
            </div>
          );
        return (
          <button
            key={index}
            disabled={item.disabled}
            onMouseEnter={() => setSub(null)}
            onClick={() => {
              item.onSelect();
              onClose();
            }}
            className={`font-body flex items-center gap-2 rounded-[6px] px-2 py-1 text-left hover:bg-[var(--accent)] hover:text-[var(--on-accent)] disabled:opacity-40 disabled:hover:bg-transparent ${item.destructive ? "text-[var(--danger)]" : ""}`}
            style={{ width: "calc(100% - 10px)", margin: "0 5px" }}
          >
            <span className="w-4 shrink-0">{item.checked && <Icon name="checkmark" size={13} weight={2.5} />}</span>
            {item.icon && <Icon name={item.icon} size={14} />}
            <span className="flex-1 truncate">{item.title}</span>
          </button>
        );
      })}
    </>
  );
}

/** Floating content anchored to an element; closes on a click outside or Escape. */
export function Popover({ anchor, onClose, children, align = "start", side = "below", offset = 6 }: {
  anchor: HTMLElement | null;
  onClose: () => void;
  children: ReactNode;
  align?: "start" | "end" | "center";
  side?: "below" | "above" | "right";
  offset?: number;
}) {
  const box = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ left: number; top: number } | null>(null);
  useLayoutEffect(() => {
    if (!anchor || !box.current) return;
    const a = anchor.getBoundingClientRect();
    const b = box.current.getBoundingClientRect();
    let left = align === "end" ? a.right - b.width : align === "center" ? a.left + a.width / 2 - b.width / 2 : a.left;
    let top = a.bottom + offset;
    if (side === "right") {
      left = a.right + 2;
      top = a.top - 6;
    } else if (side === "above" || top + b.height > window.innerHeight - 8) top = a.top - b.height - offset;
    left = Math.max(8, Math.min(left, window.innerWidth - b.width - 8));
    top = Math.max(8, Math.min(top, window.innerHeight - b.height - 8));
    setPos({ left, top });
  }, [anchor, align, side, offset]);
  useEffect(() => {
    const down = (e: MouseEvent) => {
      const target = e.target as Node;
      if (box.current?.contains(target) || anchor?.contains(target)) return;
      if ((target as HTMLElement).closest?.("[data-popover]")) return;
      onClose();
    };
    const key = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("mousedown", down, true);
    window.addEventListener("keydown", key);
    return () => {
      window.removeEventListener("mousedown", down, true);
      window.removeEventListener("keydown", key);
    };
  }, [anchor, onClose]);
  return createPortal(
    <div ref={box} data-popover className="pop-in fixed z-[1000]" style={{ left: pos?.left ?? -9999, top: pos?.top ?? -9999, visibility: pos ? "visible" : "hidden" }}>
      {children}
    </div>,
    document.body,
  );
}

// MARK: Settings rows (SettingsSection.swift)

export function SettingsSection({ title, children, footer, id }: { title: string; children: ReactNode; footer?: ReactNode; id?: string }) {
  const rows = (Array.isArray(children) ? children : [children]).flat().filter(Boolean);
  return (
    <section id={id} className="flex flex-col gap-2">
      <h3 className="font-section-title pb-0.5">{title}</h3>
      <div className="surface overflow-hidden">
        {rows.map((row, i) => (
          <div key={i}>
            {i > 0 && <SettingsDivider />}
            {row}
          </div>
        ))}
      </div>
      {footer && <div className="font-caption px-4 text-[var(--text-2)]">{footer}</div>}
    </section>
  );
}

export function SettingsRow({ title, detail, children }: { title: ReactNode; detail?: ReactNode; children?: ReactNode }) {
  return (
    <div className="flex min-h-[50px] items-center gap-3 px-4 py-2.5">
      <div className="flex min-w-0 flex-1 flex-col gap-[3px]">
        <div className="font-body">{title}</div>
        {detail && <div className="font-caption text-[var(--text-2)]">{detail}</div>}
      </div>
      {children}
    </div>
  );
}

export function SettingsAddRow({ title, onClick }: { title: string; onClick: () => void }) {
  return (
    <button onClick={onClick} className="font-body flex min-h-[50px] w-full items-center gap-2 px-4 py-2.5 text-left text-[var(--accent)] hover:bg-[var(--surface-inset)]">
      <Icon name="plus" size={15} />
      {title}
    </button>
  );
}

export function SettingsDivider() {
  return <div className="ml-4 h-px bg-[var(--separator)]" />;
}

/** The on/off switch at the System Settings size. */
export function Switch({ on, onChange, label, disabled }: { on: boolean; onChange: (on: boolean) => void; label?: string; disabled?: boolean }) {
  return (
    <button
      role="switch"
      aria-checked={on}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!on)}
      className="relative h-[20px] w-[34px] shrink-0 rounded-full transition-colors duration-200 disabled:opacity-40"
      style={{ background: on ? "var(--accent-green)" : "color-mix(in srgb, var(--text) 20%, transparent)" }}
    >
      <span
        className="absolute top-[2px] left-[2px] h-4 w-4 rounded-full bg-white shadow-[0_1px_2px_rgba(0,0,0,0.3)] transition-transform duration-200"
        style={{ transform: on ? "translateX(14px)" : "none", transitionTimingFunction: "var(--ease-bouncy)" }}
      />
    </button>
  );
}

/** The System Settings pop-up: the value and a chevron in a small round well; a menu opens over it. */
export function PopUp<T extends string>({ value, options, onChange, disabled, fontSize = 13 }: { value: T; options: { value: T; title: string }[]; onChange: (v: T) => void; disabled?: boolean; fontSize?: number }) {
  const [open, setOpen] = useState(false);
  const anchor = useRef<HTMLButtonElement>(null);
  const current = options.find((o) => o.value === value)?.title ?? "";
  return (
    <>
      <button
        ref={anchor}
        disabled={disabled}
        onClick={() => setOpen(!open)}
        className="group inline-flex h-[26px] shrink-0 items-center gap-1.5 rounded-[7px] pr-[3px] pl-2 hover:bg-[var(--surface-inset)] disabled:opacity-40"
        style={{ fontSize }}
      >
        <span className="whitespace-nowrap">{current}</span>
        <span className="flex h-5 w-5 items-center justify-center rounded-[5px] bg-[var(--surface-inset)] group-hover:bg-[color-mix(in_srgb,var(--text)_10%,transparent)]">
          <Icon name="chevron.up.chevron.down" size={11} weight={2.4} />
        </span>
      </button>
      {open && <Menu anchor={anchor.current} onClose={() => setOpen(false)} align="end" items={options.map((o) => ({ kind: "item", title: o.title, checked: o.value === value, onSelect: () => onChange(o.value) }))} />}
    </>
  );
}

export function Segmented<T extends string>({ value, options, onChange }: { value: T; options: { value: T; title: string }[]; onChange: (v: T) => void }) {
  const index = Math.max(0, options.findIndex((o) => o.value === value));
  return (
    <div className="relative inline-grid rounded-[8px] bg-[var(--surface-inset)] p-[2px]" style={{ gridTemplateColumns: `repeat(${options.length}, minmax(0, 1fr))` }}>
      <div
        className="absolute top-[2px] bottom-[2px] rounded-[6px] bg-[var(--surface)] shadow-[0_1px_2px_rgba(0,0,0,0.12)] transition-transform duration-300"
        style={{ left: 2, width: `calc((100% - 4px) / ${options.length})`, transform: `translateX(${index * 100}%)`, transitionTimingFunction: "var(--ease-bouncy)" }}
      />
      {options.map((o) => (
        <button key={o.value} onClick={() => onChange(o.value)} className="font-secondary relative z-10 h-6 px-3 font-medium whitespace-nowrap">
          {o.title}
        </button>
      ))}
    </div>
  );
}

// MARK: Status chip, search field

export function StatusChip({ title, live, isError }: { title: string; live: boolean; isError?: boolean }) {
  return (
    <span className="font-caption inline-flex items-center gap-1.5 rounded-full bg-[var(--surface-inset)] px-2.5 py-[5px]" style={{ color: isError ? "var(--danger)" : "var(--text-2)" }}>
      <span className="h-1.5 w-1.5 rounded-full" style={{ background: isError ? "var(--danger)" : live ? "var(--accent)" : "var(--text-2)" }} />
      {title}
    </span>
  );
}

export function SearchField({ value, onChange, prompt = tr("搜索会议、内容或分类"), inputRef, onFocusChange }: { value: string; onChange: (v: string) => void; prompt?: string; inputRef?: React.Ref<HTMLInputElement>; onFocusChange?: (f: boolean) => void }) {
  return (
    <div className="flex h-10 items-center gap-2 rounded-full bg-[var(--surface)] px-3.5">
      <Icon name="magnifyingglass" size={15} className="text-[var(--text-2)]" />
      <input ref={inputRef} value={value} onChange={(e) => onChange(e.target.value)} onFocus={() => onFocusChange?.(true)} onBlur={() => onFocusChange?.(false)} placeholder={prompt} className="font-body min-w-0 flex-1 bg-transparent outline-none" />
      {value && (
        <button onClick={() => onChange("")} aria-label={tr("清除搜索")} className="text-[var(--text-2)]">
          <Icon name="xmark.circle.fill" size={15} />
        </button>
      )}
    </div>
  );
}

// MARK: Sheet and alert (SwiftUI .sheet / .alert)

export function Sheet({ children, onClose, width = 520 }: { children: ReactNode; onClose?: () => void; width?: number }) {
  useEffect(() => {
    const key = (e: KeyboardEvent) => e.key === "Escape" && onClose?.();
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [onClose]);
  return createPortal(
    <div className="fade-in fixed inset-0 z-[900] flex items-center justify-center bg-black/25 p-6" onMouseDown={(e) => e.target === e.currentTarget && onClose?.()}>
      <div className="pop-in surface max-h-full overflow-hidden shadow-[0_24px_60px_rgba(0,0,0,0.3)]" style={{ width: `min(${width}px, 100%)` }}>
        {children}
      </div>
    </div>,
    document.body,
  );
}

export function Alert({ title, message, actions }: { title: string; message?: string; actions: { title: string; role?: "cancel" | "destructive" | "default"; onClick: () => void }[] }) {
  return (
    <Sheet width={340} onClose={actions.find((a) => a.role === "cancel")?.onClick}>
      <div className="flex flex-col items-center gap-2 p-5 text-center">
        <div className="font-section-title">{title}</div>
        {message && <div className="font-secondary text-[var(--text-2)] selectable">{message}</div>}
        <div className="mt-3 flex w-full gap-2">
          {actions.map((a) => (
            <button
              key={a.title}
              onClick={a.onClick}
              className={`press font-secondary h-8 flex-1 rounded-[8px] font-medium ${a.role === "destructive" ? "bg-[var(--danger)] text-white" : a.role === "cancel" ? "bg-[var(--surface-inset)]" : "bg-[var(--accent)] text-[var(--on-accent)]"}`}
            >
              {a.title}
            </button>
          ))}
        </div>
      </div>
    </Sheet>
  );
}

// MARK: Scroll area with the fading bar

export function Scroll({ children, className = "", style, innerRef, onScroll }: { children: ReactNode; className?: string; style?: React.CSSProperties; innerRef?: React.RefObject<HTMLDivElement | null>; onScroll?: (el: HTMLDivElement) => void }) {
  const own = useRef<HTMLDivElement>(null);
  const ref = innerRef ?? own;
  const timer = useRef(0);
  return (
    <div
      ref={ref}
      className={`scroll ${className}`}
      style={style}
      onScroll={(e) => {
        const el = e.currentTarget;
        el.classList.add("scrolling");
        window.clearTimeout(timer.current);
        timer.current = window.setTimeout(() => el.classList.remove("scrolling"), 1200);
        onScroll?.(el);
      }}
    >
      {children}
    </div>
  );
}

export function JumpToLatestPill({ onClick }: { onClick: () => void }) {
  return (
    <button onClick={onClick} className="glass press font-caption inline-flex items-center gap-1.5 rounded-full px-3 py-2 text-[var(--text)]" aria-label={tr("回到最新")}>
      <Icon name="arrow.down" size={13} />
      {tr("回到最新")}
    </button>
  );
}

export function NowDivider() {
  const [now, setNow] = useState(new Date());
  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 30_000);
    return () => clearInterval(id);
  }, []);
  const two = (n: number) => String(n).padStart(2, "0");
  return (
    <div className="flex items-center gap-3">
      <div className="h-px flex-1 bg-[var(--separator)]" />
      <span className="font-caption rounded-full bg-[var(--accent-soft)] px-2.5 py-1 tabular-nums text-[var(--accent)]">{tr("现在 · %@").replace("%@", `${two(now.getHours())}:${two(now.getMinutes())}`)}</span>
      <div className="h-px flex-1 bg-[var(--separator)]" />
    </div>
  );
}

/** A plain text button in the accent color. */
export function LinkButton({ title, onClick, disabled, danger }: { title: string; onClick: () => void; disabled?: boolean; danger?: boolean }) {
  return (
    <button onClick={onClick} disabled={disabled} className="font-secondary font-medium disabled:opacity-40" style={{ color: danger ? "var(--danger)" : "var(--accent)" }}>
      {title}
    </button>
  );
}

/** The bordered push button macOS uses in dialogs and rows. */
export function PushButton({ title, onClick, disabled, prominent, destructive, small, icon }: { title: string; onClick: () => void; disabled?: boolean; prominent?: boolean; destructive?: boolean; small?: boolean; icon?: string }) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`press inline-flex shrink-0 items-center justify-center gap-1.5 rounded-[7px] font-medium whitespace-nowrap disabled:opacity-40 ${small ? "h-[24px] px-2.5 text-[12px]" : "h-[28px] px-3 text-[13px]"}`}
      style={{
        background: prominent ? "var(--accent)" : destructive ? "var(--danger)" : "var(--surface-inset)",
        color: prominent ? "var(--on-accent)" : destructive ? "#fff" : "var(--text)",
      }}
    >
      {icon && <Icon name={icon} size={13} />}
      {title}
    </button>
  );
}

export function TextField({ value, onChange, placeholder, className = "", onEnter, autoFocus, secure, onBlur }: { value: string; onChange: (v: string) => void; placeholder?: string; className?: string; onEnter?: () => void; autoFocus?: boolean; secure?: boolean; onBlur?: () => void }) {
  return (
    <input
      type={secure ? "password" : "text"}
      value={value}
      autoFocus={autoFocus}
      onChange={(e) => onChange(e.target.value)}
      onKeyDown={(e) => e.key === "Enter" && onEnter?.()}
      onBlur={onBlur}
      placeholder={placeholder}
      className={`font-body h-8 rounded-[8px] border border-[var(--separator)] bg-[var(--surface)] px-2.5 outline-none focus:border-[var(--accent)] ${className}`}
    />
  );
}

// MARK: Context menus (SwiftUI .contextMenu)

/** An anchor at a point, for menus opened with a right-click. */
export function pointAnchor(x: number, y: number): HTMLElement {
  return { getBoundingClientRect: () => new DOMRect(x, y, 0, 0), contains: () => false } as unknown as HTMLElement;
}

/** Right-click opens `items()` at the pointer. Returns the handler and the menu to render. */
export function useContextMenu(items: () => MenuEntry[]) {
  const [at, setAt] = useState<{ x: number; y: number } | null>(null);
  const onContextMenu = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setAt({ x: e.clientX, y: e.clientY });
  };
  const menu = at ? <Menu anchor={pointAnchor(at.x, at.y)} items={items()} onClose={() => setAt(null)} /> : null;
  return { onContextMenu, menu };
}

/** An alert with one text field, as SwiftUI's `.alert` with a TextField. */
export function PromptAlert({ title, message, value, placeholder, confirm = tr("确定"), onConfirm, onCancel }: { title: string; message?: string; value: string; placeholder?: string; confirm?: string; onConfirm: (v: string) => void; onCancel: () => void }) {
  const [text, setText] = useState(value);
  return (
    <Sheet width={320} onClose={onCancel}>
      <div className="flex flex-col gap-3 p-5">
        <div className="font-section-title text-center">{title}</div>
        {message && <div className="font-secondary text-center text-[var(--text-2)]">{message}</div>}
        <TextField autoFocus value={text} onChange={setText} placeholder={placeholder} onEnter={() => onConfirm(text)} />
        <div className="flex gap-2">
          <button onClick={onCancel} className="press font-secondary h-8 flex-1 rounded-[8px] bg-[var(--surface-inset)] font-medium">{tr("取消")}</button>
          <button onClick={() => onConfirm(text)} className="press font-secondary h-8 flex-1 rounded-[8px] bg-[var(--accent)] font-medium text-[var(--on-accent)]">{confirm}</button>
        </div>
      </div>
    </Sheet>
  );
}

/** PillButton.swift's TrailingBarSwap: fades between the idle and the manage toolbar. */
export function TrailingBarSwap({ managing, idle, manage }: { managing: boolean; idle: ReactNode; manage: ReactNode }) {
  return (
    <div className="relative flex items-center justify-end">
      <div key={managing ? "manage" : "idle"} className="flex items-center gap-3" style={{ animation: "slide-in var(--t-layout) var(--ease-smooth) backwards" }}>
        {managing ? manage : idle}
      </div>
    </div>
  );
}

/** The time | category capsule (MeetingListView.groupingToggle). */
export function CapsuleToggle<T extends string>({ value, options, onChange }: { value: T; options: { value: T; title: string }[]; onChange: (v: T) => void }) {
  return (
    <div className="flex gap-0.5 rounded-full bg-[var(--surface)] p-[3px]">
      {options.map((o) => (
        <button key={o.value} onClick={() => onChange(o.value)} className="press font-secondary h-[30px] rounded-full px-3 font-medium" style={{ background: o.value === value ? "var(--selection)" : "transparent", color: o.value === value ? "var(--on-selection)" : "var(--text-2)" }}>
          {o.title}
        </button>
      ))}
    </div>
  );
}

/** MeetingCard.swift's SelectionMark: grows in from the left and pushes the title across. */
export function SelectionMark({ selected }: { selected: boolean | null }) {
  const shown = selected !== null;
  return (
    <span className="flex shrink-0 overflow-hidden transition-all" style={{ width: shown ? 34 : 0, opacity: shown ? 1 : 0, transitionDuration: "var(--t-layout)", transitionTimingFunction: "var(--ease-smooth)" }} aria-hidden={!shown}>
      <span style={{ color: selected ? "var(--accent)" : "var(--text-2)" }}>
        <Icon name={selected ? "checkmark.circle.fill" : "circle"} size={20} />
      </span>
    </span>
  );
}
