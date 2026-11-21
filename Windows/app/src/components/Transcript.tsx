// The transcript: one block per paragraph, with its time, its speakers, the original and the
// translation. A live transcript follows the newest line unless you scroll up; then a
// "Jump to latest" pill appears (as on the Mac).
import { ArrowDown } from "lucide-react";
import { memo, useEffect, useLayoutEffect, useRef, useState } from "react";
import type { Commit, Paragraph, VoiceName } from "../lib/api";
import { clock, join, voiceColor, voiceLabel } from "../lib/format";
import { useT } from "../lib/i18n";
import { Scroll } from "./ui";

type Group = { speaker?: string; commits: Commit[] };

/** Consecutive lines by the same voice, so a speaker chip shows once per turn. */
function groups(commits: Commit[]): Group[] {
  const out: Group[] = [];
  for (const commit of commits) {
    const last = out.at(-1);
    if (last && last.speaker === commit.speaker) last.commits.push(commit);
    else out.push({ speaker: commit.speaker, commits: [commit] });
  }
  return out;
}

export function SpeakerChip({ name, speaker }: { name?: VoiceName; speaker?: string }) {
  const t = useT();
  if (!speaker || !name) return null;
  const color = voiceColor(name);
  return (
    <span
      className="fade-in mr-2 inline-flex h-[20px] items-center gap-1.5 rounded-full px-2 align-[2px] text-[11px] font-semibold"
      style={{ color, background: `color-mix(in srgb, ${color} 13%, transparent)` }}
    >
      <span className="h-1.5 w-1.5 rounded-full" style={{ background: color }} />
      {voiceLabel(name, t)}
    </span>
  );
}

const ParagraphBlock = memo(function ParagraphBlock({ paragraph, sourceLanguage, targetLanguage, names, hidden, live, onSpeaker }: {
  paragraph: Paragraph;
  sourceLanguage: string;
  targetLanguage: string;
  names: Record<string, VoiceName>;
  hidden: Set<string>;
  live: boolean;
  onSpeaker?: (speaker: string, paragraph: Paragraph) => void;
}) {
  const shown = paragraph.commits.filter((c) => !(c.speaker && hidden.has(c.speaker)));
  if (shown.length === 0 && !paragraph.tail) return null;
  const language = paragraph.sourceLanguage ?? sourceLanguage;
  const translate = targetLanguage !== "none";
  return (
    <div className={`grid grid-cols-[64px_1fr] gap-x-3 py-3 ${live ? "enter" : ""}`}>
      <div className="pt-[3px] text-[12px] tabular-nums text-[var(--text-2)]">{clock(paragraph.openedAt)}</div>
      <div className="min-w-0 space-y-1.5">
        {groups(shown).map((group, index) => (
          <div key={index} className="selectable">
            <p className="text-[15.5px] leading-[1.7]">
              {group.speaker && (
                <button className="press" onClick={() => onSpeaker?.(group.speaker!, paragraph)} disabled={!onSpeaker}>
                  <SpeakerChip name={names[group.speaker]} speaker={group.speaker} />
                </button>
              )}
              {join(group.commits.map((c) => c.source), language)}
            </p>
            {translate && (
              <p className="text-[14.5px] leading-[1.65] text-[var(--text-2)]">{join(group.commits.map((c) => c.translation), targetLanguage)}</p>
            )}
          </div>
        ))}
        {paragraph.tail && <p className="text-[15.5px] leading-[1.7] text-[var(--text-2)] opacity-70 transition-opacity">{paragraph.tail}</p>}
      </div>
    </div>
  );
});

export function Transcript({ paragraphs, sourceLanguage, targetLanguage, names, hidden = [], live = false, onSpeaker, empty }: {
  paragraphs: Paragraph[];
  sourceLanguage: string;
  targetLanguage: string;
  names: Record<string, VoiceName>;
  hidden?: string[];
  live?: boolean;
  onSpeaker?: (speaker: string, paragraph: Paragraph) => void;
  empty?: React.ReactNode;
}) {
  const t = useT();
  const ref = useRef<HTMLDivElement>(null);
  const [following, setFollowing] = useState(true);
  const hiddenSet = new Set(hidden);

  // Follow the newest line while the reader is at the bottom.
  useLayoutEffect(() => {
    if (live && following && ref.current) ref.current.scrollTop = ref.current.scrollHeight;
  });
  useEffect(() => setFollowing(true), [live]);

  const jump = () => {
    setFollowing(true);
    ref.current?.scrollTo({ top: ref.current.scrollHeight, behavior: "smooth" });
  };

  return (
    <div className="relative min-h-0 flex-1">
      <Scroll
        innerRef={ref}
        className="h-full px-6"
        onScroll={(el) => {
          const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
          if (atBottom !== following) setFollowing(atBottom);
        }}
      >
        {paragraphs.length === 0 && empty}
        <div className="divide-y divide-[var(--glass-line)] pb-16">
          {paragraphs.map((p) => (
            <ParagraphBlock
              key={p.id}
              paragraph={p}
              sourceLanguage={sourceLanguage}
              targetLanguage={targetLanguage}
              names={names}
              hidden={hiddenSet}
              live={live}
              onSpeaker={onSpeaker}
            />
          ))}
        </div>
      </Scroll>
      <button
        onClick={jump}
        className={`glass-strong press absolute bottom-4 left-1/2 flex h-9 -translate-x-1/2 items-center gap-1.5 rounded-full px-4 text-[13px] font-medium transition-all duration-[var(--t-page)] ${
          live && !following ? "opacity-100" : "pointer-events-none translate-y-2 opacity-0"
        }`}
      >
        <ArrowDown size={15} />
        {t("跳到最新")}
      </button>
    </div>
  );
}
