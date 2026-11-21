// Nomi's small controls, in glass. Only opacity and transform animate, so they stay smooth.
import { useRef, type ButtonHTMLAttributes, type ReactNode } from "react";

/** Moves the button's highlight to follow the pointer, like light on glass. */
function follow(event: React.PointerEvent<HTMLElement>) {
  const rect = event.currentTarget.getBoundingClientRect();
  event.currentTarget.style.setProperty("--mx", `${event.clientX - rect.left}px`);
  event.currentTarget.style.setProperty("--my", `${event.clientY - rect.top}px`);
}

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & { tone?: "primary" | "glass" | "quiet" | "danger"; size?: "sm" | "md" | "lg" };

export function Button({ tone = "glass", size = "md", className = "", children, ...rest }: ButtonProps) {
  const sizes = { sm: "h-8 px-3 text-[13px] rounded-[10px]", md: "h-9 px-4 text-sm rounded-[12px]", lg: "h-12 px-6 text-[15px] rounded-[16px]" };
  const tones = {
    primary: "bg-[var(--accent)] text-[var(--on-accent)] shadow-[inset_0_1px_0_rgba(255,255,255,0.25),0_4px_14px_color-mix(in_srgb,var(--accent)_35%,transparent)] hover:brightness-110",
    glass: "glass hover:bg-[var(--glass-strong)]",
    quiet: "hover:bg-[color-mix(in_srgb,var(--text)_7%,transparent)]",
    danger: "bg-[var(--danger)] text-white hover:brightness-110",
  };
  return (
    <button
      {...rest}
      onPointerMove={follow}
      className={`sheen press inline-flex items-center justify-center gap-2 font-medium whitespace-nowrap disabled:opacity-45 disabled:pointer-events-none ${sizes[size]} ${tones[tone]} ${className}`}
    >
      {children}
    </button>
  );
}

export function Card({ children, className = "", strong = false }: { children: ReactNode; className?: string; strong?: boolean }) {
  return <div className={`${strong ? "glass-strong" : "glass"} rounded-[16px] ${className}`}>{children}</div>;
}

export function Label({ children }: { children: ReactNode }) {
  return <div className="mb-1.5 text-[12px] font-medium text-[var(--text-2)]">{children}</div>;
}

export function Select({ value, onChange, options, className = "", disabled }: {
  value: string;
  onChange: (value: string) => void;
  options: { value: string; label: string }[];
  className?: string;
  disabled?: boolean;
}) {
  return (
    <select
      value={value}
      disabled={disabled}
      onChange={(e) => onChange(e.target.value)}
      className={`glass h-9 rounded-[12px] px-3 pr-8 text-sm outline-none transition-colors hover:bg-[var(--glass-strong)] disabled:opacity-50 ${className}`}
    >
      {options.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label}
        </option>
      ))}
    </select>
  );
}

/** A row of choices with a glass thumb that slides to the chosen one. */
export function Segmented<T extends string>({ value, onChange, options }: { value: T; onChange: (v: T) => void; options: { value: T; label: string }[] }) {
  const index = Math.max(0, options.findIndex((o) => o.value === value));
  return (
    <div className="relative inline-grid rounded-[12px] bg-[color-mix(in_srgb,var(--text)_6%,transparent)] p-[3px]" style={{ gridTemplateColumns: `repeat(${options.length}, minmax(0, 1fr))` }}>
      <div
        className="glass-strong absolute top-[3px] bottom-[3px] rounded-[9px] transition-transform duration-[var(--t-layout)] ease-[var(--ease-spring)]"
        style={{ width: `calc((100% - 6px) / ${options.length})`, transform: `translateX(${index * 100}%)`, left: 3 }}
      />
      {options.map((o) => (
        <button
          key={o.value}
          onClick={() => onChange(o.value)}
          className={`relative z-10 h-8 px-3 text-[13px] font-medium transition-colors duration-[var(--t-tap)] ${o.value === value ? "text-[var(--text)]" : "text-[var(--text-2)] hover:text-[var(--text)]"}`}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

export function Toggle({ on, onChange, label }: { on: boolean; onChange: (on: boolean) => void; label?: string }) {
  return (
    <button
      role="switch"
      aria-checked={on}
      aria-label={label}
      onClick={() => onChange(!on)}
      className={`relative h-[26px] w-[44px] shrink-0 rounded-full transition-colors duration-[var(--t-layout)] ${on ? "bg-[var(--leaf)]" : "bg-[color-mix(in_srgb,var(--text)_18%,transparent)]"}`}
    >
      <span
        className="absolute top-[3px] left-[3px] h-5 w-5 rounded-full bg-white shadow-[0_1px_3px_rgba(0,0,0,0.25)] transition-transform duration-[var(--t-layout)] ease-[var(--ease-spring)]"
        style={{ transform: on ? "translateX(18px)" : "none" }}
      />
    </button>
  );
}

export function Progress({ value }: { value: number }) {
  return (
    <div className="h-1.5 w-full overflow-hidden rounded-full bg-[color-mix(in_srgb,var(--text)_10%,transparent)]">
      <div
        className="h-full w-full origin-left rounded-full bg-[var(--leaf)] transition-transform duration-300 ease-out"
        style={{ transform: `scaleX(${Math.max(0, Math.min(1, value))})` }}
      />
    </div>
  );
}

/** A scroll area whose scroll bar shows while scrolling and fades after (as on the Mac, 0.10). */
export function Scroll({ children, className = "", onScroll, innerRef }: {
  children: ReactNode;
  className?: string;
  onScroll?: (el: HTMLDivElement) => void;
  innerRef?: React.RefObject<HTMLDivElement | null>;
}) {
  const own = useRef<HTMLDivElement>(null);
  const ref = innerRef ?? own;
  const timer = useRef(0);
  return (
    <div
      ref={ref}
      className={`scroll ${className}`}
      onScroll={(e) => {
        const el = e.currentTarget;
        el.classList.add("scrolling");
        window.clearTimeout(timer.current);
        timer.current = window.setTimeout(() => el.classList.remove("scrolling"), 900);
        onScroll?.(el);
      }}
    >
      {children}
    </div>
  );
}
