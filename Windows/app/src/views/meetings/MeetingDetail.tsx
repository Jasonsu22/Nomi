// Meetings/MeetingDetailView.swift, Meetings/CompactMeetingView.swift and the MeetingsPage switch.
import { drawsOwnTitleBar, WindowControls } from "../shell/WindowControls";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { tr } from "../../i18n";
import { formatStartStamp, languageName, toDate } from "../../support/format";
import { LectureLanguages } from "../../support/languages";
import { prefs } from "../../support/prefs";
import { CategoryPalette } from "../../models/category";
import type { Meeting } from "../../models/meeting";
import { AudioInputs } from "../../engine/audioInputs";
import { useModel } from "../../app";
import { Icon } from "../ui/Icon";
import { Popover, PopUp } from "../ui/controls";
import { SessionControl } from "../shell/SessionControl";
import { CategoryEditor, CategoryIcon, newDraft } from "./Category";
import { compactTabs, DetailSidePanel } from "./DetailSidePanel";
import { MeetingListView, StartTimeEditor } from "./MeetingList";
import { QuestionPopupView } from "./QuestionPopup";
import { TranscriptCard } from "./TranscriptCard";

const sideWidthKey = "nomi.meetingSideWidth";

export function MeetingsPage() {
  const m = useModel();
  const open = m.openMeetingID;
  return (
    <div className="relative h-full">
      <div className="absolute inset-0 transition-opacity duration-200" style={{ opacity: open ? 0 : 1, pointerEvents: open ? "none" : "auto" }} aria-hidden={!!open}>
        <MeetingListView />
      </div>
      {open && (
        <div key={open} className="enter absolute inset-0">
          <MeetingDetailView meetingID={open} />
        </div>
      )}
    </div>
  );
}

function CircleButton({ icon, label, onClick, disabled, title, size = 32 }: { icon: string; label: string; onClick: () => void; disabled?: boolean; title?: string; size?: number }) {
  return (
    <button onClick={onClick} disabled={disabled} aria-label={label} title={title ?? label} className="press flex shrink-0 items-center justify-center rounded-full bg-[var(--surface)] text-[var(--text-2)] disabled:opacity-40" style={{ width: size, height: size }}>
      <Icon name={icon} size={14} />
    </button>
  );
}

function MetaChip({ text, symbol, onClick, disabled, title }: { text: string; symbol?: string; onClick: (e: React.MouseEvent<HTMLButtonElement>) => void; disabled?: boolean; title?: string }) {
  return (
    <button onClick={onClick} disabled={disabled} title={title} className="press inline-flex h-7 max-w-[260px] items-center gap-1 rounded-full bg-[var(--surface)] px-2.5 text-[13px] font-medium tabular-nums text-[var(--text-2)] disabled:opacity-50">
      {symbol && <Icon name={symbol} size={13} />}
      <span className="truncate">{text}</span>
    </button>
  );
}

function ChoiceList({ items, onPick }: { items: { title: string; value: string | null; checked: boolean }[]; onPick: (v: string | null) => void }) {
  return (
    <>
      {items.map((i) => (
        <button key={i.value ?? "__none"} onClick={() => onPick(i.value)} className="font-secondary flex w-full items-center gap-3 rounded-[6px] px-2 py-1.5 text-left hover:bg-[var(--surface-inset)]">
          <span className="flex-1 truncate">{i.title}</span>
          {i.checked && <Icon name="checkmark" size={12} weight={3} />}
        </button>
      ))}
    </>
  );
}

function Header({ meeting, width, showSide, onShowSide }: { meeting: Meeting; width: number; showSide: boolean; onShowSide: () => void }) {
  const m = useModel();
  const [title, setTitle] = useState(meeting.title);
  const [pop, setPop] = useState<{ kind: "time" | "category" | "languages" | "input"; el: HTMLElement } | null>(null);
  const [creating, setCreating] = useState(false);
  const category = m.category(meeting.categoryID);
  const close = () => {
    setPop(null);
    setCreating(false);
  };
  const idle = m.engine.session.phase === "idle";
  return (
    <div className="flex flex-col gap-3 px-6 py-4">
      <div className="flex items-center gap-3">
        <button onClick={() => m.closeMeeting()} aria-label={tr("返回会议列表")} className="press flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[var(--surface)]">
          <Icon name="chevron.left" size={14} weight={2.6} />
        </button>
        <CategoryIcon symbol={category?.symbol ?? CategoryPalette.uncategorizedSymbol} colorIndex={category?.colorIndex ?? CategoryPalette.uncategorizedIndex} />
        <input
          value={title}
          placeholder={tr("未命名会议")}
          onChange={(e) => {
            setTitle(e.target.value);
            m.rename(meeting.id, e.target.value);
          }}
          onKeyDown={(e) => e.key === "Enter" && e.currentTarget.blur()}
          className="font-detail-title min-w-0 flex-1 bg-transparent outline-none"
        />
        <CircleButton icon="square.on.square" label={tr("缩小窗口")} onClick={() => m.set("meetingCompact", true)} />
        {!showSide && <CircleButton icon="sidebar.trailing" label={tr("打开侧栏")} title={width < 760 ? tr("窗口再宽一点才能打开侧栏") : tr("打开侧栏")} disabled={width < 760} onClick={onShowSide} />}
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <MetaChip text={formatStartStamp(toDate(meeting.startedAt))} title={tr("重设时间")} onClick={(e) => setPop({ kind: "time", el: e.currentTarget })} />
        <MetaChip text={m.categoryName(meeting) ?? tr("未分类")} onClick={(e) => setPop({ kind: "category", el: e.currentTarget })} />
        <MetaChip text={`${languageName(m.recordingSourceLanguage)} → ${languageName(m.recordingTargetLanguage)}`} onClick={(e) => setPop({ kind: "languages", el: e.currentTarget })} />
        <MetaChip text={m.audioInputs.selectionTitle} symbol="mic" title={m.audioInputs.selectionTitle} disabled={!idle} onClick={(e) => setPop({ kind: "input", el: e.currentTarget })} />
      </div>
      {pop?.kind === "time" && <StartTimeEditor date={m.startDate(meeting)} onChange={(d) => m.setStartTime(meeting.id, d)} onDone={close} />}
      {pop && pop.kind !== "time" && (
        <Popover anchor={pop.el} onClose={close}>
          <div className="menu min-w-[180px] p-2">
            {pop.kind === "category" &&
              (creating ? (
                <CategoryEditor
                  title={tr("新建分类")}
                  initial={newDraft(m.categories.length)}
                  onSubmit={(d) => {
                    const id = m.addCategory(d.name, d.colorIndex, d.symbol);
                    if (id) m.assign(new Set([meeting.id]), id);
                    close();
                  }}
                />
              ) : (
                <>
                  <ChoiceList
                    items={[{ title: tr("未分类"), value: null, checked: !meeting.categoryID }, ...m.categories.map((c) => ({ title: c.name, value: c.id, checked: meeting.categoryID === c.id }))]}
                    onPick={(v) => {
                      m.assign(new Set([meeting.id]), v);
                      close();
                    }}
                  />
                  <div className="my-1 h-px bg-[var(--separator)]" />
                  <button onClick={() => setCreating(true)} className="font-secondary flex w-full items-center gap-1.5 rounded-[6px] px-2 py-1.5 text-left hover:bg-[var(--surface-inset)]">
                    <Icon name="plus" size={13} />
                    {tr("新建分类")}
                  </button>
                </>
              ))}
            {pop.kind === "languages" && (
              <div className="font-secondary flex w-[284px] flex-col gap-3 p-2">
                <div className="flex items-center">
                  <span className="flex-1">{tr("输入语言")}</span>
                  <PopUp value={m.recordingSourceLanguage} disabled={!idle} onChange={(v) => (m.recordingSourceLanguage = v)} options={["auto", ...LectureLanguages.supported].map((c) => ({ value: c, title: languageName(c) }))} />
                </div>
                <div className="flex items-center">
                  <span className="flex-1">{tr("目标翻译语言")}</span>
                  <PopUp value={m.recordingTargetLanguage} disabled={!idle} onChange={(v) => (m.recordingTargetLanguage = v)} options={[{ value: "none", title: tr("不翻译") }, ...LectureLanguages.supported.map((c) => ({ value: c, title: languageName(c) }))]} />
                </div>
              </div>
            )}
            {pop.kind === "input" && (
              <ChoiceList
                items={[
                  { title: tr("系统默认"), value: AudioInputs.systemDefault, checked: m.audioInputs.selectedUID === AudioInputs.systemDefault },
                  ...m.audioInputs.devices.map((d) => ({ title: d.name, value: d.id, checked: m.audioInputs.selectedUID === d.id })),
                  ...(m.audioInputs.selectedUID !== AudioInputs.systemDefault && !m.audioInputs.selectedDevice ? [{ title: tr("设备已断开"), value: m.audioInputs.selectedUID, checked: true }] : []),
                ]}
                onPick={(v) => {
                  if (v) m.audioInputs.selectedUID = v;
                  close();
                }}
              />
            )}
          </div>
        </Popover>
      )}
    </div>
  );
}

/** The bar between the transcript and the side panel; drag to change the panel's width. */
function SplitHandle({ width, range, onChange, onEnd }: { width: number; range: [number, number]; onChange: (w: number) => void; onEnd: () => void }) {
  return (
    <div
      role="separator"
      aria-label={tr("调整侧栏宽度")}
      className="group flex w-4 shrink-0 cursor-col-resize items-center justify-center"
      onPointerDown={(e) => {
        const startX = e.clientX, start = width;
        e.currentTarget.setPointerCapture(e.pointerId);
        const move = (ev: PointerEvent) => onChange(Math.min(range[1], Math.max(range[0], start - (ev.clientX - startX))));
        const up = () => {
          window.removeEventListener("pointermove", move);
          window.removeEventListener("pointerup", up);
          onEnd();
        };
        window.addEventListener("pointermove", move);
        window.addEventListener("pointerup", up);
      }}
    >
      <span className="h-9 w-1 rounded-full bg-[color-mix(in_srgb,var(--text)_22%,transparent)] group-hover:bg-[color-mix(in_srgb,var(--text)_40%,transparent)]" />
    </div>
  );
}

function useWidth() {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(1200);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    setWidth(el.clientWidth);
    const ro = new ResizeObserver(() => setWidth(el.clientWidth));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  return { ref, width };
}

export function MeetingDetailView({ meetingID }: { meetingID: string }) {
  const m = useModel();
  const meeting = m.meetings.find((x) => x.id === meetingID);
  const { ref, width } = useWidth();
  const [preference, setPreference] = useState<boolean | null>(null);
  const [sideWidth, setSideWidth] = useState(() => {
    const stored = prefs.number(sideWidthKey) ?? 0;
    return stored > 0 ? stored : 340;
  });
  useEffect(() => {
    void m.audioInputs.refresh();
  }, [m.page === "meetings"]);
  useEffect(() => {
    const r = m.detailTabRequest;
    if (r && r.meetingID === m.openMeetingID) setPreference(true);
  }, [m.detailTabRequest?.token]);
  if (!meeting) return null;
  const showSide = (preference ?? width >= 1100) && width >= 760;
  const range: [number, number] = [300, Math.max(300, width - 64 - 340)];
  const shownWidth = Math.min(Math.max(sideWidth, range[0]), range[1]);
  const persist = () => prefs.set(sideWidthKey, sideWidth);
  return (
    <div ref={ref} className="flex h-full flex-col">
      <Header meeting={meeting} width={width} showSide={showSide} onShowSide={() => setPreference(true)} />
      <div className="flex min-h-0 flex-1 px-6 pb-5">
        <div className="min-w-0 flex-1">
          <TranscriptCard meeting={meeting} canCompare={width >= 1100} jump={m.transcriptJump?.meetingID === meeting.id ? m.transcriptJump : null} />
        </div>
        {showSide && (
          <>
            <SplitHandle width={shownWidth} range={range} onChange={setSideWidth} onEnd={persist} />
            <div className="slide-from-right shrink-0" style={{ width: shownWidth }}>
              <DetailSidePanel
                meeting={meeting}
                onClose={() => setPreference(false)}
                onPreferredWidth={(needed) => {
                  const resolved = Math.min(range[1], needed);
                  if (sideWidth < resolved - 0.5) {
                    setSideWidth(resolved);
                    prefs.set(sideWidthKey, resolved);
                  }
                }}
              />
            </div>
          </>
        )}
      </div>
    </div>
  );
}

export function CompactMeetingView({ meetingID }: { meetingID: string }) {
  const m = useModel();
  const meeting = m.meetings.find((x) => x.id === meetingID);
  if (!meeting) return null;
  const category = m.category(meeting.categoryID);
  const popup = m.questionPopup;
  return (
    <div className="relative flex h-full flex-col gap-3 bg-[var(--canvas)] p-4" data-tauri-drag-region>
      {drawsOwnTitleBar() && (
        <div className="absolute top-2 right-2 z-10">
          <WindowControls compact />
        </div>
      )}
      <div className="flex justify-center" data-tauri-drag-region>
        <SessionControl session={m.engine.session} meter={m.engine.level} canStart={m.canStart} startTitle={m.recordingActionTitle} onStart={() => m.performRecordingAction()} onStop={() => m.stopTranscription()} onTogglePause={() => m.togglePause()} />
      </div>
      <div className="flex items-center gap-2" data-tauri-drag-region>
        <CircleButton size={28} icon="chevron.left" label={tr("返回会议列表")} onClick={() => m.closeMeeting()} />
        <CategoryIcon symbol={category?.symbol ?? CategoryPalette.uncategorizedSymbol} colorIndex={category?.colorIndex ?? CategoryPalette.uncategorizedIndex} />
        <span className="font-section-title min-w-0 flex-1 truncate">{meeting.title || tr("未命名会议")}</span>
        <CircleButton size={28} icon="arrow.up.left.and.arrow.down.right" label={tr("恢复窗口")} onClick={() => m.set("meetingCompact", false)} />
      </div>
      <div className="relative min-h-0 flex-1">
        <DetailSidePanel meeting={meeting} tabs={compactTabs} initialTab="transcript" showsClose={false} />
        {popup && m.engine.session.phase !== "idle" && (
          <div key={popup.questionID} className="drop-in absolute inset-x-0 top-10">
            <QuestionPopupView popup={popup} width={null} />
          </div>
        )}
      </div>
    </div>
  );
}
