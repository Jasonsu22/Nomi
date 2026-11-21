// Meetings/DetailSidePanel.swift: the tabs beside the transcript (and the compact window's tabs).
import { useEffect, useState } from "react";
import { tr } from "../../i18n";
import { formatClock, formatDuration } from "../../support/format";
import { characterCount, type Meeting } from "../../models/meeting";
import type { DetailTab } from "../../app/model";
import { useModel } from "../../app";
import { dialogs, shell } from "../../platform";
import { SourceStore } from "../../app/stores";
import { Icon } from "../ui/Icon";
import { Alert, Menu, Popover, Scroll } from "../ui/controls";
import { DropOutline, sourceFilters, useFileDrop } from "../ui/fileDrop";
import { AskView } from "../ask/AskView";
import { MeetingAssistantPanel } from "./AssistantPanel";
import { MeetingQAPanel } from "./QAPanel";
import { TranscriptCard } from "./TranscriptCard";

export const tabTitles: Record<DetailTab, string> = { transcript: "转写", ask: "提问", qa: "问答", summary: "摘要", sources: "资料", info: "信息" };
export const sideTabs: DetailTab[] = ["ask", "qa", "summary", "sources", "info"];
export const compactTabs: DetailTab[] = ["transcript", "ask", "qa", "summary", "sources", "info"];

export function DetailSidePanel({ meeting, onClose, tabs = sideTabs, initialTab = "ask", showsClose = true, onPreferredWidth }: { meeting: Meeting; onClose?: () => void; tabs?: DetailTab[]; initialTab?: DetailTab; showsClose?: boolean; onPreferredWidth?: (w: number) => void }) {
  const m = useModel();
  const [tab, setTab] = useState<DetailTab>(initialTab);
  useEffect(() => {
    if (tab === "ask") onPreferredWidth?.(480);
  }, [tab]);
  useEffect(() => {
    const r = m.detailTabRequest;
    if (!r || r.meetingID !== meeting.id || !tabs.includes(r.tab)) return;
    setTab(r.tab);
    m.detailTabRequest = null;
  }, [m.detailTabRequest?.token]);
  useEffect(() => {
    if (m.transcriptJump?.meetingID === meeting.id && tabs.includes("transcript")) setTab("transcript");
  }, [m.transcriptJump?.token]);

  let body: React.ReactNode;
  switch (tab) {
    case "transcript":
      body = <TranscriptCard meeting={meeting} canCompare={false} embedded jump={m.transcriptJump?.meetingID === meeting.id ? m.transcriptJump : null} />;
      break;
    case "info":
      body = <Info meeting={meeting} />;
      break;
    case "ask":
      body = <AskView anchorMeetingID={meeting.id} />;
      break;
    case "qa":
      body = <MeetingQAPanel meeting={meeting} onContinueInChat={() => setTab("ask")} />;
      break;
    case "summary":
      body = <MeetingAssistantPanel meeting={meeting} summary />;
      break;
    case "sources":
      body = <Sources meeting={meeting} />;
      break;
  }
  return (
    <div className="surface flex h-full min-h-0 flex-col overflow-hidden">
      <div className="flex items-center gap-2 px-4 pt-4 pb-3">
        {tabs.map((t) => (
          <button key={t} onClick={() => setTab(t)} aria-selected={tab === t} className="press font-caption relative h-[26px] rounded-full px-2 font-medium" style={{ color: tab === t ? "var(--on-selection)" : "var(--text-2)" }}>
            <span className="absolute inset-0 rounded-full bg-[var(--selection)] transition-all duration-300" style={{ opacity: tab === t ? 1 : 0, transform: tab === t ? "none" : "scale(0.9)" }} />
            <span className="relative">{tr(tabTitles[t])}</span>
          </button>
        ))}
        <div className="flex-1" />
        {showsClose && (
          <button onClick={onClose} aria-label={tr("关闭侧栏")} className="flex h-6 w-6 items-center justify-center text-[var(--text-2)]">
            <Icon name="xmark" size={12} weight={2.6} />
          </button>
        )}
      </div>
      <div key={tab} className="enter flex min-h-0 flex-1 flex-col">
        {body}
      </div>
    </div>
  );
}

function Row({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center px-4 py-3">
      <span className="font-body">{title}</span>
      <div className="flex-1" />
      <span className="font-secondary text-[var(--text-2)]">{children}</span>
    </div>
  );
}

function LiveClock() {
  const m = useModel();
  const [, tick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => tick((n) => n + 1), 500);
    return () => clearInterval(id);
  }, []);
  return <>{formatClock(m.engine.session.elapsed)}</>;
}

function Info({ meeting }: { meeting: Meeting }) {
  const m = useModel();
  const [confirming, setConfirming] = useState(false);
  const [menu, setMenu] = useState<HTMLElement | null>(null);
  const hairline = <div className="ml-4 h-px bg-[var(--separator)]" />;
  return (
    <Scroll className="min-h-0 flex-1">
      <div className="flex flex-col gap-4 p-4">
        <div className="overflow-hidden rounded-[var(--r-field)] bg-[var(--surface-inset)]">
          <Row title={tr("分类")}>
            <button onClick={(e) => setMenu(e.currentTarget)} className="text-[var(--text-2)]">
              {m.categoryName(meeting) ?? tr("未分类")}
            </button>
          </Row>
          {hairline}
          <Row title={tr("时长")}>{meeting.isLive ? <LiveClock /> : formatDuration(meeting.duration)}</Row>
          {hairline}
          <Row title={tr("字数")}>{characterCount(meeting)}</Row>
        </div>
        <button onClick={() => void m.export([meeting])} className="press font-secondary h-[34px] rounded-full bg-[var(--surface-inset)] font-medium">
          {tr("导出 Markdown")}
        </button>
        {!meeting.isLive && (
          <button onClick={() => setConfirming(true)} disabled={m.assistantStates[meeting.id]?.isGenerating} className="font-secondary h-[34px] font-medium text-[var(--danger)] disabled:opacity-40">
            {tr("删除会议")}
          </button>
        )}
      </div>
      {menu && (
        <Menu
          anchor={menu}
          align="end"
          onClose={() => setMenu(null)}
          items={[
            { kind: "item", title: tr("未分类"), checked: !meeting.categoryID, onSelect: () => m.assign(new Set([meeting.id]), null) },
            ...m.categories.map((c) => ({ kind: "item" as const, title: c.name, checked: meeting.categoryID === c.id, onSelect: () => m.assign(new Set([meeting.id]), c.id) })),
          ]}
        />
      )}
      {confirming && (
        <Alert
          title={tr("删除这场会议？")}
          message={tr("转写会一起删掉。")}
          actions={[
            { title: tr("取消"), role: "cancel", onClick: () => setConfirming(false) },
            {
              title: tr("删除"),
              role: "destructive",
              onClick: () => {
                setConfirming(false);
                m.deleteMeeting(meeting.id);
              },
            },
          ]}
        />
      )}
    </Scroll>
  );
}

function Sources({ meeting }: { meeting: Meeting }) {
  const m = useModel();
  const linked = m.linkedSources(meeting.id);
  const { ref, targeted } = useFileDrop((paths) => void m.importLinkedSources(paths, meeting.id));
  const [linking, setLinking] = useState<HTMLElement | null>(null);
  const candidates = m.sources.filter((s) => s.categoryID === meeting.categoryID || !s.categoryID);
  return (
    <div ref={ref} className="relative flex min-h-0 flex-1 flex-col">
      <Scroll className="min-h-0 flex-1">
        <div className="flex flex-col gap-2 p-4">
          <div className="flex items-center">
            <span className="font-body">{tr("资料")}</span>
            <div className="flex-1" />
            <button onClick={(e) => setLinking(e.currentTarget)} title={tr("关联已有资料")} className="flex h-6 w-6 items-center justify-center text-[var(--text-2)]">
              <Icon name="link" size={14} />
            </button>
          </div>
          {linked.length === 0 ? (
            <div className="font-caption text-[var(--text-2)]">{tr("导入 PDF 或文档，提问时会一并阅读，并放进这个分类的资料库。")}</div>
          ) : (
            <div className="overflow-hidden rounded-[var(--r-field)] bg-[var(--surface-inset)]">
              {linked.map((s) => (
                <div key={s.id} className="flex items-center gap-2 px-3 py-2">
                  <button onClick={() => void shell.openPath(SourceStore.fileURL(s))} title={tr("打开")} className="flex min-w-0 flex-1 items-center gap-2 text-left">
                    <span className="text-[var(--text-2)]">
                      <Icon name={s.fileName.toLowerCase().endsWith("pdf") ? "doc.richtext" : "doc"} size={14} />
                    </span>
                    <span className="font-secondary truncate">{s.title}</span>
                  </button>
                  <button onClick={() => m.unlinkSource(s.id, meeting.id)} title={tr("取消关联")} className="text-[var(--text-2)]">
                    <Icon name="xmark" size={10} weight={3} />
                  </button>
                </div>
              ))}
            </div>
          )}
          <button
            onClick={async () => {
              const files = await dialogs.openFiles(sourceFilters());
              if (files.length) void m.importLinkedSources(files, meeting.id);
            }}
            className="press font-secondary h-[34px] rounded-full bg-[var(--surface-inset)] font-medium"
          >
            {tr("添加资料")}
          </button>
        </div>
      </Scroll>
      <DropOutline shown={targeted} />
      {linking && (
        <Popover anchor={linking} onClose={() => setLinking(null)} align="end">
          <div className="menu w-[280px] p-3">
            {candidates.length === 0 ? (
              <div className="font-secondary text-[var(--text-2)]">{tr("这个分类里还没有可以关联的资料。")}</div>
            ) : (
              <div className="scroll flex max-h-[280px] flex-col gap-0.5">
                {candidates.map((s) => (
                  <button key={s.id} onClick={() => m.linkSource(s.id, meeting.id)} className="font-secondary flex items-center gap-2 rounded-[6px] px-2 py-1.5 text-left hover:bg-[var(--surface-inset)]">
                    <span className="flex-1 truncate">{s.title}</span>
                    {linked.some((l) => l.id === s.id) && (
                      <span className="text-[var(--accent)]">
                        <Icon name="checkmark" size={12} weight={3} />
                      </span>
                    )}
                  </button>
                ))}
              </div>
            )}
          </div>
        </Popover>
      )}
    </div>
  );
}
