import { jsx as _jsx } from "react/jsx-runtime";
// Nomi's loader: three green dots, ported from DotLoader.swift with the same paths and periods.
// Drawn on a canvas at the display's frame rate; a still frame with reduced motion.
import { useEffect, useRef } from "react";
const PERIOD = { hop: 1.2, gather: 3.0, infinity: 4.2, circle: 3.0, breeze: 2.8 };
const COUNT = 3;
const wrap = (v) => {
    const r = v % 1;
    return r < 0 ? r + 1 : r;
};
const edge = (s) => Math.min(1, s / 0.14, (1 - s) / 0.14);
// The 8 on its side, walked at an even speed.
const SQUASH = 0.9;
const raw = (t) => ({ x: Math.cos(t), y: SQUASH * Math.sin(t) * Math.cos(t) });
const TABLE = (() => {
    const steps = 1200;
    const angles = [0];
    const lengths = [0];
    let previous = raw(0);
    let total = 0;
    for (let step = 1; step <= steps; step++) {
        const t = (2 * Math.PI * step) / steps;
        const p = raw(t);
        total += Math.hypot(p.x - previous.x, p.y - previous.y);
        angles.push(t);
        lengths.push(total);
        previous = p;
    }
    return { angles, lengths: lengths.map((l) => l / total) };
})();
function lemniscate(s) {
    const { angles, lengths } = TABLE;
    let low = 0;
    let high = lengths.length - 1;
    while (high - low > 1) {
        const middle = (low + high) >> 1;
        if (lengths[middle] < s)
            low = middle;
        else
            high = middle;
    }
    const span = lengths[high] - lengths[low];
    const f = span > 0 ? (s - lengths[low]) / span : 0;
    return raw(angles[low] + (angles[high] - angles[low]) * f);
}
export function dots(style, phase) {
    const n = COUNT;
    const gap = 1 / n;
    return Array.from({ length: n }, (_, i) => {
        switch (style) {
            case "hop": {
                const s = wrap(phase - i * gap * 0.42);
                const up = s < 0.4 ? Math.sin((Math.PI * s) / 0.4) : 0;
                return { x: (i - (n - 1) / 2) * 0.44, y: 0.08 - 0.2 * up, radius: 0.17 * 0.44, opacity: 1 };
            }
            case "gather": {
                const s = wrap(phase + i * gap);
                const r = 0.42 * (1 - s);
                const angle = 2 * Math.PI * 1.2 * s + (2 * Math.PI * i) / n;
                return { x: Math.cos(angle) * r * 1.6, y: Math.sin(angle) * r * 0.8, radius: 0.17 * 0.5 * (0.55 + 0.45 * s), opacity: Math.min(1, s / 0.1, (1 - s) / 0.06) };
            }
            case "infinity": {
                const p = lemniscate(wrap(phase + i * gap));
                return { x: p.x * 0.6, y: p.y * 0.6, radius: 0.17 * 0.52, opacity: 1 };
            }
            case "circle": {
                const angle = 2 * Math.PI * wrap(phase + i * gap) - Math.PI / 2;
                return { x: Math.cos(angle) * 0.3, y: Math.sin(angle) * 0.3, radius: 0.17 * 0.5, opacity: 1 };
            }
            case "breeze": {
                const s = wrap(phase + i * gap);
                return { x: -0.85 + 1.7 * s, y: 0.16 * Math.sin(2 * Math.PI * 1.25 * s + 1), radius: 0.17 * 0.46, opacity: edge(s) };
            }
        }
    });
}
export function DotLoader({ style = "circle", height = 16, width }) {
    const canvas = useRef(null);
    const w = width ?? height * 2;
    useEffect(() => {
        const element = canvas.current;
        const context = element?.getContext("2d");
        if (!element || !context)
            return;
        const scale = window.devicePixelRatio || 1;
        element.width = w * scale;
        element.height = height * scale;
        const color = getComputedStyle(document.documentElement).getPropertyValue("--leaf").trim() || "#20b68a";
        const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
        let frame = 0;
        const draw = (now) => {
            const phase = reduce ? 0.08 : (now / 1000 / PERIOD[style]) % 1;
            context.setTransform(scale, 0, 0, scale, 0, 0);
            context.clearRect(0, 0, w, height);
            context.fillStyle = color;
            for (const dot of dots(style, phase)) {
                if (dot.opacity <= 0.01 || dot.radius <= 0.001)
                    continue;
                context.globalAlpha = dot.opacity;
                context.beginPath();
                context.arc(w / 2 + dot.x * height, height / 2 + dot.y * height, dot.radius * height, 0, Math.PI * 2);
                context.fill();
            }
            if (!reduce)
                frame = requestAnimationFrame(draw);
        };
        frame = requestAnimationFrame(draw);
        return () => cancelAnimationFrame(frame);
    }, [style, height, w]);
    return _jsx("canvas", { ref: canvas, style: { width: w, height }, "aria-hidden": true });
}
