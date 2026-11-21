// Meetings/TranscriptCard.swift and DesignSystem/Components/ParagraphRow.swift.
import { memo, useEffect, useLayoutEffect, useRef, useState } from "react";
import { tr, trf } from "../../i18n";
import { formatClock } from "../../support/format";
import { prefs } from "../../support/prefs";
import { renderedSource, renderedTranslation, TranscriptText, type Commit, type Paragraph } from "../../models/transcript";
import { shownParagraphs, type Meeting } from "../../models/meeting";
import { VoiceLabels, Voices, type MeetingVoices } from "../../models/meetingVoices";
import { useModel } from "../../app";
import type { TranscriptJump } from "../../app/model";
import { Icon } from "../ui/Icon";
import { JumpToLatestPill, Menu, PromptAlert, Scroll, pointAnchor, type MenuEntry } from "../ui/controls";

const fontKey = "lecturenote.transcriptFontSize";
const speakersKey = "lecturenote.showSpeakers";
// macOS system colours: teal, orange, pink, purple, green, brown, indigo, mint, red, yellow.
const speakerPalette = ["#30b0c7", "#ff9500", "#ff2d55", "#af52de", "#34c759", "#a2845e", "#5856d6", "#00c7be", "#ff3b30", "#d4a600"];

export function speakerColor(speaker: string, voices: MeetingVoices) {
  if (speaker === voices.me) return "var(--accent)";
  return speakerPalette[(Voices.number(voices, speaker) - 1) % speakerPalette.length];
}

export const talkTime = (seconds: number) => (seconds >= 60 ? trf("%d 分钟", Math.round(seconds / 60)) : trf("%d 秒", Math.round(seconds)));

function SpeakerText({ paragraph, voices, field, size, base, sourceLanguage, targetLanguage }: { paragraph: Paragraph; voices: MeetingVoices; field: "source" | "translation"; size: number; base: string; sourceLanguage: string; targetLanguage: string }) {
  const language = field === "source" ? (paragraph.sourceLanguage ?? sourceLanguage) : (paragraph.targetLanguage ?? targetLanguage);
  const runs: { speaker: string | null; parts: string[] }[] = [];
  for (const commit of paragraph.commits as Commit[]) {
    const text = commit[field];
    if (commit.speaker && commit.speaker !== (runs.at(-1)?.speaker ?? null)) runs.push({ speaker: commit.speaker, parts: [text] });
    else if (!runs.length) runs.push({ speaker: null, parts: [text] });
    else runs[runs.length - 1].parts.push(text);
  }
  const many = new Set(runs.map((r) => r.speaker).filter(Boolean)).size > 1;
  const out: React.ReactNode[] = [];
  runs.forEach((run, i) => {
    const body = TranscriptText.join(run.parts, language);
    if (!body) return;
    if (i > 0 && TranscriptText.usesSpaces(language)) out.push(" ");
    if (run.speaker && (field === "source" || many))
      out.push(
        <span key={`n${i}`} style={{ fontSize: size - 3, fontWeight: 600, color: speakerColor(run.speaker, voices) }}>
          {Voices.name(voices, run.speaker) + " "}
        </span>,
      );
    out.push(<span key={`b${i}`} style={{ color: base }}>{body}</span>);
  });
  return <>{out}</>;
}

type RowProps = { paragraph: Paragraph; sourceLanguage: string; targetLanguage: string; compare: boolean; fontSize: number; highlighted: boolean; voices: MeetingVoices | null; showSpeakers: boolean; onContextMenu?: (e: React.MouseEvent) => void };

export const ParagraphRow = memo(function ParagraphRow({ paragraph, sourceLanguage, targetLanguage, compare, fontSize, highlighted, voices, showSpeakers, onContextMenu }: RowProps) {
  const source = renderedSource(paragraph, sourceLanguage);
  const translation = renderedTranslation(paragraph, targetLanguage);
  const labelled = showSpeakers && !!voices && paragraph.commits.some((c) => c.speaker);
  const pending = paragraph.tail.trim();
  const spoken = labelled ? (
    <SpeakerText paragraph={paragraph} voices={voices!} field="source" size={fontSize} base="var(--text)" sourceLanguage={sourceLanguage} targetLanguage={targetLanguage} />
  ) : (
    <>
      <span>{source}</span>
      {pending && (
        <span className="text-[var(--text-2)]">
          {TranscriptText.needsSeparator(source, pending, sourceLanguage) ? " " : ""}
          {pending}
        </span>
      )}
    </>
  );
  const translated = labelled ? <SpeakerText paragraph={paragraph} voices={voices!} field="translation" size={fontSize - 1} base="var(--text-2)" sourceLanguage={sourceLanguage} targetLanguage={targetLanguage} /> : translation;
  return (
    <div
      data-paragraph={paragraph.id}
      onContextMenu={onContextMenu}
      className="selectable flex items-baseline gap-3 rounded-[var(--r-tag)] px-2 py-2.5 transition-colors"
      style={{ background: highlighted ? "var(--selection)" : !paragraph.closed ? "var(--accent-soft)" : "transparent", transitionDuration: highlighted ? "250ms" : "600ms" }}
    >
      <span className="font-caption w-14 shrink-0 tabular-nums text-[var(--text-2)]">{formatClock(paragraph.openedAt)}</span>
      {compare ? (
        <>
          <div className="min-w-0 flex-1" style={{ fontSize, lineHeight: `${fontSize + 8}px` }}>{spoken}</div>
          <div className="min-w-0 flex-1 text-[var(--text-2)]" style={{ fontSize: fontSize - 1, lineHeight: `${fontSize + 6}px` }}>{translated || " "}</div>
        </>
      ) : (
        <div className="flex min-w-0 flex-1 flex-col gap-1.5">
          <div style={{ fontSize, lineHeight: `${fontSize + 8}px` }}>{spoken}</div>
          {translation && <div className="text-[var(--text-2)]" style={{ fontSize: fontSize - 1, lineHeight: `${fontSize + 6}px` }}>{translated}</div>}
        </div>
      )}
    </div>
  );
});

function SmallButton({ title, onClick, children, label }: { title?: string; onClick: (e: React.MouseEvent<HTMLButtonElement>) => void; children: React.ReactNode; label?: string }) {
  return (
    <button onClick={onClick} title={title} aria-label={label ?? title} className="press font-caption inline-flex h-6 items-center gap-1 rounded-[6px] px-1.5 text-[var(--text-2)] hover:bg-[var(--surface-inset)]">
      {children}
    </button>
  );
}

export function TranscriptCard({ meeting, canCompare, embedded = false, jump }: { meeting: Meeting; canCompare: boolean; embedded?: boolean; jump: TranscriptJump | null }) {
  const m = useModel();
  const [fontSize, setFontSize] = useState(() => prefs.number(fontKey) ?? 15);
  const [showSpeakers, setShowSpeakers] = useState(() => prefs.bool(speakersKey) ?? true);
  const [compare, setCompare] = useState(false);
  const [copied, setCopied] = useState(false);
  const [follows, setFollows] = useState(meeting.isLive);
  const [highlighted, setHighlighted] = useState<number | null>(null);
  const [renaming, setRenaming] = useState<string | null>(null);
  const [speakerMenu, setSpeakerMenu] = useState<HTMLElement | null>(null);
  const [rowMenu, setRowMenu] = useState<{ paragraph: Paragraph; x: number; y: number } | null>(null);
  const scroller = useRef<HTMLDivElement>(null);
  const followRef = useRef(follows);
  followRef.current = follows;
  const highlightTimer = useRef(0);

  const live = meeting.isLive ? m.liveVoices(meeting) : null;
  const paragraphs = !meeting.isLive ? meeting.paragraphs : m.liveSpeakerSpans.length ? VoiceLabels.apply(m.liveSpeakerSpans, m.engine.transcript.paragraphs) : m.engine.transcript.paragraphs;
  const voices = live?.voices ?? meeting.voices ?? null;
  const shown = shownParagraphs(meeting, paragraphs);
  const checking = m.checkingVoices.has(meeting.id);
  const voiceError = m.voiceError[meeting.id];
  const sideBySide = compare && canCompare;

  const setFont = (n: number) => {
    setFontSize(n);
    prefs.set(fontKey, n);
  };
  const toBottom = () => {
    const el = scroller.current;
    if (el) el.scrollTop = el.scrollHeight;
  };
  const last = paragraphs.at(-1);
  const bottomToken = `${paragraphs.length}-${last?.commits.length ?? 0}-${last ? renderedSource(last, meeting.sourceLanguage).length : 0}-${last?.tail.length ?? 0}`;
  useLayoutEffect(() => {
    if (meeting.isLive && followRef.current) toBottom();
  }, [bottomToken, meeting.isLive]);
  useLayoutEffect(() => {
    if (meeting.isLive) toBottom();
  }, []);
  useEffect(() => {
    if (!jump || Date.now() - jump.createdAt > 5000) return;
    const target = [...paragraphs].reverse().find((p) => p.openedAt <= jump.time + 1.5) ?? paragraphs[0];
    if (!target) return;
    setFollows(false);
    const row = scroller.current?.querySelector(`[data-paragraph="${target.id}"]`) as HTMLElement | null;
    row?.scrollIntoView({ behavior: "smooth", block: "start" });
    setHighlighted(target.id);
    clearTimeout(highlightTimer.current);
    highlightTimer.current = window.setTimeout(() => setHighlighted(null), 1600);
  }, [jump?.token]);

  const onScroll = (el: HTMLDivElement) => {
    const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 72;
    if (atBottom !== followRef.current) setFollows(atBottom);
  };

  const speakers = voices ? Object.keys(voices.seconds).filter((s) => (voices.seconds[s] ?? 0) >= 1).sort((a, b) => Voices.number(voices, a) - Voices.number(voices, b)) : [];
  const hidden = new Set(meeting.hiddenSpeakers ?? []);
  const speakerItems = (): MenuEntry[] => {
    const items: MenuEntry[] = [
      {
        kind: "item",
        title: tr("显示说话人标签"),
        checked: showSpeakers,
        onSelect: () => {
          setShowSpeakers(!showSpeakers);
          prefs.set(speakersKey, !showSpeakers);
        },
      },
      { kind: "divider" },
      { kind: "header", title: tr("只显示勾选的说话人") },
      ...speakers.map((s): MenuEntry => ({ kind: "item", title: `${Voices.name(voices!, s)} · ${talkTime(voices!.seconds[s] ?? 0)}`, checked: !hidden.has(s), onSelect: () => m.showSpeaker(meeting.id, s, hidden.has(s)) })),
    ];
    if (hidden.size) items.push({ kind: "divider" }, { kind: "item", title: tr("显示所有说话人"), onSelect: () => hidden.forEach((s) => m.showSpeaker(meeting.id, s, true)) });
    return items;
  };
  const rowItems = (paragraph: Paragraph): MenuEntry[] => {
    const v = meeting.voices;
    if (meeting.isLive || !v) return [];
    const items: MenuEntry[] = [];
    const other = VoiceLabels.voiceToPromote(paragraph, v);
    if (other && other !== v.me) items.push({ kind: "item", title: tr("这是我的声音"), onSelect: () => m.markMe(meeting.id, paragraph.id) });
    if (v.me && paragraph.commits.some((c) => Voices.side(v, c) === "me")) items.push({ kind: "item", title: tr("这不是我的声音"), onSelect: () => m.clearMe(meeting.id) });
    const present = [...new Set(paragraph.commits.map((c) => c.speaker).filter((s): s is string => !!s))];
    if (present.length && items.length) items.push({ kind: "divider" });
    for (const s of present) items.push({ kind: "item", title: trf("重命名“%@”…", Voices.name(v, s)), onSelect: () => setRenaming(s) });
    return items;
  };

  let voiceControl: React.ReactNode = null;
  if (voices && !checking) {
    voiceControl = (
      <span title={tr("显示或隐藏说话人标签，只看某些人说的话。右键一段可以给说话人改名，或标出你自己")}>
        <button onClick={(e) => setSpeakerMenu(e.currentTarget)} className="press font-caption inline-flex h-6 items-center gap-1 rounded-[6px] px-1.5 hover:bg-[var(--surface-inset)]" style={{ color: showSpeakers || hidden.size ? "var(--accent)" : "var(--text-2)" }}>
          <Icon name={showSpeakers ? "person.2.fill" : "person.2"} size={13} />
          {hidden.size ? trf("说话人（隐藏 %d）", hidden.size) : tr("说话人")}
        </button>
      </span>
    );
  } else if (checking) {
    voiceControl = (
      <span className="font-caption flex items-center gap-1.5 text-[var(--text-2)]">
        <span className="spinner" />
        {tr("正在识别声音…")}
      </span>
    );
  } else if (!meeting.isLive && (meeting.audioFiles ?? []).length) {
    voiceControl = (
      <SmallButton title={voiceError ?? tr("从这场录音里分出每个人的声音，在每段话前标出说话人")} label={tr("识别说话人")} onClick={() => m.checkVoices(meeting.id)}>
        <Icon name="person.2.wave.2" size={13} />
        {tr("识别说话人")}
      </SmallButton>
    );
  }

  return (
    <div className={`flex h-full min-h-0 flex-col ${embedded ? "" : "surface overflow-hidden"}`}>
      <div className="flex items-center gap-2 px-4 pt-4 pb-3">
        {!embedded && <span className="font-section-title">{tr("转写")}</span>}
        <div className="flex-1" />
        {voiceControl}
        <SmallButton onClick={() => setFont(Math.max(13, fontSize - 1))} label="A−">
          <span className="w-4 text-center">A−</span>
        </SmallButton>
        <SmallButton onClick={() => setFont(Math.min(20, fontSize + 1))} label="A+">
          <span className="w-4 text-center">A+</span>
        </SmallButton>
        {canCompare && <SmallButton onClick={() => setCompare(!compare)}>{compare ? tr("对照") : tr("段内")}</SmallButton>}
        <SmallButton
          onClick={() => {
            void m.copyTranscript(meeting.isLive ? { ...meeting, paragraphs: m.engine.transcript.paragraphs } : meeting);
            setCopied(true);
            setTimeout(() => setCopied(false), 1200);
          }}
        >
          {copied ? tr("已复制") : tr("复制全文")}
        </SmallButton>
      </div>
      <div className="relative min-h-0 flex-1">
        <Scroll innerRef={scroller} className="h-full" onScroll={onScroll}>
          <div className="mx-auto flex max-w-[640px] flex-col gap-0.5 px-3 pb-4">
            {paragraphs.length === 0 ? (
              <div className="font-body p-6 text-[var(--text-2)]">{meeting.isLive ? tr("正在听…") : tr("这场还没有转写。")}</div>
            ) : (
              shown.map((p) => (
                <ParagraphRow
                  key={p.id}
                  paragraph={p}
                  sourceLanguage={meeting.sourceLanguage}
                  targetLanguage={meeting.targetLanguage}
                  compare={sideBySide}
                  fontSize={fontSize}
                  highlighted={highlighted === p.id}
                  voices={voices}
                  showSpeakers={showSpeakers}
                  onContextMenu={
                    !meeting.isLive && meeting.voices
                      ? (e) => {
                          if (window.getSelection()?.toString()) return;
                          e.preventDefault();
                          setRowMenu({ paragraph: p, x: e.clientX, y: e.clientY });
                        }
                      : undefined
                  }
                />
              ))
            )}
          </div>
        </Scroll>
        {meeting.isLive && !follows && paragraphs.length > 0 && (
          <div className="pop-in absolute right-5 bottom-4">
            <JumpToLatestPill
              onClick={() => {
                setFollows(true);
                toBottom();
              }}
            />
          </div>
        )}
      </div>
      {speakerMenu && <Menu anchor={speakerMenu} items={speakerItems()} onClose={() => setSpeakerMenu(null)} align="end" width={240} />}
      {rowMenu && rowItems(rowMenu.paragraph).length > 0 && <Menu anchor={pointAnchor(rowMenu.x, rowMenu.y)} items={rowItems(rowMenu.paragraph)} onClose={() => setRowMenu(null)} />}
      {renaming && voices && (
        <PromptAlert
          title={tr("给说话人起个名字")}
          message={tr("这场录音里这个声音说的话都会用这个名字。留空就恢复原来的名字。")}
          value={voices.names?.[renaming] ?? ""}
          placeholder={tr("名字，例如 Jenny")}
          confirm={tr("保存")}
          onCancel={() => setRenaming(null)}
          onConfirm={(name) => {
            m.renameSpeaker(meeting.id, renaming, name);
            setRenaming(null);
          }}
        />
      )}
    </div>
  );
}
