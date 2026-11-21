import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// The transcript: one block per paragraph, with its time, its speakers, the original and the
// translation. A live transcript follows the newest line unless you scroll up; then a
// "Jump to latest" pill appears (as on the Mac).
import { ArrowDown } from "lucide-react";
import { memo, useEffect, useLayoutEffect, useRef, useState } from "react";
import { clock, join, voiceColor, voiceLabel } from "../lib/format";
import { useT } from "../lib/i18n";
import { Scroll } from "./ui";
/** Consecutive lines by the same voice, so a speaker chip shows once per turn. */
function groups(commits) {
    const out = [];
    for (const commit of commits) {
        const last = out.at(-1);
        if (last && last.speaker === commit.speaker)
            last.commits.push(commit);
        else
            out.push({ speaker: commit.speaker, commits: [commit] });
    }
    return out;
}
export function SpeakerChip({ name, speaker }) {
    const t = useT();
    if (!speaker || !name)
        return null;
    const color = voiceColor(name);
    return (_jsxs("span", { className: "fade-in mr-2 inline-flex h-[20px] items-center gap-1.5 rounded-full px-2 align-[2px] text-[11px] font-semibold", style: { color, background: `color-mix(in srgb, ${color} 13%, transparent)` }, children: [_jsx("span", { className: "h-1.5 w-1.5 rounded-full", style: { background: color } }), voiceLabel(name, t)] }));
}
const ParagraphBlock = memo(function ParagraphBlock({ paragraph, sourceLanguage, targetLanguage, names, hidden, live, onSpeaker }) {
    const shown = paragraph.commits.filter((c) => !(c.speaker && hidden.has(c.speaker)));
    if (shown.length === 0 && !paragraph.tail)
        return null;
    const language = paragraph.sourceLanguage ?? sourceLanguage;
    const translate = targetLanguage !== "none";
    return (_jsxs("div", { className: `grid grid-cols-[64px_1fr] gap-x-3 py-3 ${live ? "enter" : ""}`, children: [_jsx("div", { className: "pt-[3px] text-[12px] tabular-nums text-[var(--text-2)]", children: clock(paragraph.openedAt) }), _jsxs("div", { className: "min-w-0 space-y-1.5", children: [groups(shown).map((group, index) => (_jsxs("div", { className: "selectable", children: [_jsxs("p", { className: "text-[15.5px] leading-[1.7]", children: [group.speaker && (_jsx("button", { className: "press", onClick: () => onSpeaker?.(group.speaker, paragraph), disabled: !onSpeaker, children: _jsx(SpeakerChip, { name: names[group.speaker], speaker: group.speaker }) })), join(group.commits.map((c) => c.source), language)] }), translate && (_jsx("p", { className: "text-[14.5px] leading-[1.65] text-[var(--text-2)]", children: join(group.commits.map((c) => c.translation), targetLanguage) }))] }, index))), paragraph.tail && _jsx("p", { className: "text-[15.5px] leading-[1.7] text-[var(--text-2)] opacity-70 transition-opacity", children: paragraph.tail })] })] }));
});
export function Transcript({ paragraphs, sourceLanguage, targetLanguage, names, hidden = [], live = false, onSpeaker, empty }) {
    const t = useT();
    const ref = useRef(null);
    const [following, setFollowing] = useState(true);
    const hiddenSet = new Set(hidden);
    // Follow the newest line while the reader is at the bottom.
    useLayoutEffect(() => {
        if (live && following && ref.current)
            ref.current.scrollTop = ref.current.scrollHeight;
    });
    useEffect(() => setFollowing(true), [live]);
    const jump = () => {
        setFollowing(true);
        ref.current?.scrollTo({ top: ref.current.scrollHeight, behavior: "smooth" });
    };
    return (_jsxs("div", { className: "relative min-h-0 flex-1", children: [_jsxs(Scroll, { innerRef: ref, className: "h-full px-6", onScroll: (el) => {
                    const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
                    if (atBottom !== following)
                        setFollowing(atBottom);
                }, children: [paragraphs.length === 0 && empty, _jsx("div", { className: "divide-y divide-[var(--glass-line)] pb-16", children: paragraphs.map((p) => (_jsx(ParagraphBlock, { paragraph: p, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, names: names, hidden: hiddenSet, live: live, onSpeaker: onSpeaker }, p.id))) })] }), _jsxs("button", { onClick: jump, className: `glass-strong press absolute bottom-4 left-1/2 flex h-9 -translate-x-1/2 items-center gap-1.5 rounded-full px-4 text-[13px] font-medium transition-all duration-[var(--t-page)] ${live && !following ? "opacity-100" : "pointer-events-none translate-y-2 opacity-0"}`, children: [_jsx(ArrowDown, { size: 15 }), t("跳到最新")] })] }));
}
