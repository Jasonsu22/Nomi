import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// Nomi's small controls, in glass. Only opacity and transform animate, so they stay smooth.
import { useRef } from "react";
/** Moves the button's highlight to follow the pointer, like light on glass. */
function follow(event) {
    const rect = event.currentTarget.getBoundingClientRect();
    event.currentTarget.style.setProperty("--mx", `${event.clientX - rect.left}px`);
    event.currentTarget.style.setProperty("--my", `${event.clientY - rect.top}px`);
}
export function Button({ tone = "glass", size = "md", className = "", children, ...rest }) {
    const sizes = { sm: "h-8 px-3 text-[13px] rounded-[10px]", md: "h-9 px-4 text-sm rounded-[12px]", lg: "h-12 px-6 text-[15px] rounded-[16px]" };
    const tones = {
        primary: "bg-[var(--accent)] text-[var(--on-accent)] shadow-[inset_0_1px_0_rgba(255,255,255,0.25),0_4px_14px_color-mix(in_srgb,var(--accent)_35%,transparent)] hover:brightness-110",
        glass: "glass hover:bg-[var(--glass-strong)]",
        quiet: "hover:bg-[color-mix(in_srgb,var(--text)_7%,transparent)]",
        danger: "bg-[var(--danger)] text-white hover:brightness-110",
    };
    return (_jsx("button", { ...rest, onPointerMove: follow, className: `sheen press inline-flex items-center justify-center gap-2 font-medium whitespace-nowrap disabled:opacity-45 disabled:pointer-events-none ${sizes[size]} ${tones[tone]} ${className}`, children: children }));
}
export function Card({ children, className = "", strong = false }) {
    return _jsx("div", { className: `${strong ? "glass-strong" : "glass"} rounded-[16px] ${className}`, children: children });
}
export function Label({ children }) {
    return _jsx("div", { className: "mb-1.5 text-[12px] font-medium text-[var(--text-2)]", children: children });
}
export function Select({ value, onChange, options, className = "", disabled }) {
    return (_jsx("select", { value: value, disabled: disabled, onChange: (e) => onChange(e.target.value), className: `glass h-9 rounded-[12px] px-3 pr-8 text-sm outline-none transition-colors hover:bg-[var(--glass-strong)] disabled:opacity-50 ${className}`, children: options.map((o) => (_jsx("option", { value: o.value, children: o.label }, o.value))) }));
}
/** A row of choices with a glass thumb that slides to the chosen one. */
export function Segmented({ value, onChange, options }) {
    const index = Math.max(0, options.findIndex((o) => o.value === value));
    return (_jsxs("div", { className: "relative inline-grid rounded-[12px] bg-[color-mix(in_srgb,var(--text)_6%,transparent)] p-[3px]", style: { gridTemplateColumns: `repeat(${options.length}, minmax(0, 1fr))` }, children: [_jsx("div", { className: "glass-strong absolute top-[3px] bottom-[3px] rounded-[9px] transition-transform duration-[var(--t-layout)] ease-[var(--ease-spring)]", style: { width: `calc((100% - 6px) / ${options.length})`, transform: `translateX(${index * 100}%)`, left: 3 } }), options.map((o) => (_jsx("button", { onClick: () => onChange(o.value), className: `relative z-10 h-8 px-3 text-[13px] font-medium transition-colors duration-[var(--t-tap)] ${o.value === value ? "text-[var(--text)]" : "text-[var(--text-2)] hover:text-[var(--text)]"}`, children: o.label }, o.value)))] }));
}
export function Toggle({ on, onChange, label }) {
    return (_jsx("button", { role: "switch", "aria-checked": on, "aria-label": label, onClick: () => onChange(!on), className: `relative h-[26px] w-[44px] shrink-0 rounded-full transition-colors duration-[var(--t-layout)] ${on ? "bg-[var(--leaf)]" : "bg-[color-mix(in_srgb,var(--text)_18%,transparent)]"}`, children: _jsx("span", { className: "absolute top-[3px] left-[3px] h-5 w-5 rounded-full bg-white shadow-[0_1px_3px_rgba(0,0,0,0.25)] transition-transform duration-[var(--t-layout)] ease-[var(--ease-spring)]", style: { transform: on ? "translateX(18px)" : "none" } }) }));
}
export function Progress({ value }) {
    return (_jsx("div", { className: "h-1.5 w-full overflow-hidden rounded-full bg-[color-mix(in_srgb,var(--text)_10%,transparent)]", children: _jsx("div", { className: "h-full w-full origin-left rounded-full bg-[var(--leaf)] transition-transform duration-300 ease-out", style: { transform: `scaleX(${Math.max(0, Math.min(1, value))})` } }) }));
}
/** A scroll area whose scroll bar shows while scrolling and fades after (as on the Mac, 0.10). */
export function Scroll({ children, className = "", onScroll, innerRef }) {
    const own = useRef(null);
    const ref = innerRef ?? own;
    const timer = useRef(0);
    return (_jsx("div", { ref: ref, className: `scroll ${className}`, onScroll: (e) => {
            const el = e.currentTarget;
            el.classList.add("scrolling");
            window.clearTimeout(timer.current);
            timer.current = window.setTimeout(() => el.classList.remove("scrolling"), 900);
            onScroll?.(el);
        }, children: children }));
}
