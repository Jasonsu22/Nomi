// Meetings/MeetingQAPanel.swift: the teacher's questions, answered one at a time.
import { useLayoutEffect, useRef, useState } from "react";
import { tr, trf } from "../../i18n";
import { formatClock } from "../../support/format";
import { QuestionFinder, type MeetingQA, type MeetingQuestion } from "../../models/meetingQA";
import type { ChatCitation } from "../../models/chatSession";
import type { Meeting } from "../../models/meeting";
import { useModel } from "../../app";
import { AnswerBody } from "../answer/AnswerBody";
import { DotLoader } from "../ui/DotLoader";
import { Icon } from "../ui/Icon";
import { Menu, PushButton, Scroll, Switch } from "../ui/controls";

export function MeetingQAPanel({ meeting, onContinueInChat }: { meeting: Meeting; onContinueInChat: () => void }) {
  const m = useModel();
  const qa = m.qa(meeting.id);
  const shown = [...qa.questions].reverse();
  return (
    <div className="flex h-full min-h-0 flex-col">
      <Header qa={qa} meetingID={meeting.id} />
      {qa.questions.length === 0 ? (
        <Empty qa={qa} meeting={meeting} />
      ) : (
        <Scroll className="min-h-0 flex-1">
          <div className="flex flex-col gap-3 px-4 pb-4">
            {shown.map((q, i) => (
              <div key={q.id} className="card-in">
                <QuestionCard
                  question={q}
                  isFirst={i === 0}
                  isLast={i === shown.length - 1}
                  meetingID={meeting.id}
                  onContinueInChat={() => {
                    m.continueQuestionInChat(q.id, meeting.id);
                    onContinueInChat();
                  }}
                />
              </div>
            ))}
          </div>
        </Scroll>
      )}
    </div>
  );
}

function Header({ qa, meetingID }: { qa: MeetingQA; meetingID: string }) {
  const m = useModel();
  return (
    <div className="font-caption flex items-center gap-3 px-4 pb-3">
      <label className="flex items-center gap-2">
        <Switch on={qa.autoAnswer} onChange={(on) => m.setAutoAnswer(on, meetingID)} label={tr("自动回答")} />
        {tr("自动回答")}
      </label>
      <div className="flex-1" />
      {qa.questions.length > 0 && <span className="truncate text-[var(--text-2)]">{trf("%d 个问题 · 已回答 %d", qa.questions.length, qa.answeredCount)}</span>}
      {!qa.autoAnswer && qa.questions.some((q) => q.status === "waiting" || q.status === "failed") && (
        <button onClick={() => m.askAllQuestions(meetingID)} className="text-[var(--accent)]">
          {tr("全部回答")}
        </button>
      )}
      <button onClick={() => void m.findQuestions(meetingID)} disabled={qa.scanning || !m.canRunBackgroundWork} title={tr("从转写里找老师提出的问题")} aria-label={tr("找问题")} className="flex h-[18px] w-[18px] items-center justify-center text-[var(--text-2)] disabled:opacity-40">
        {qa.scanning ? <DotLoader style="circle" height={18} width={18} /> : <Icon name="text.magnifyingglass" size={15} />}
      </button>
    </div>
  );
}

function Empty({ qa, meeting }: { qa: MeetingQA; meeting: Meeting }) {
  const m = useModel();
  const text = qa.scanning ? tr("正在从转写里找老师提出的问题…") : meeting.isLive ? tr("录音时，老师提出的问题会出现在这里。") : qa.scannedThrough >= 0 ? tr("这节课里没有找到老师提出的问题。") : tr("找出老师在课上提出的问题，并自动回答。");
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-3 p-6 text-center">
      <span className="flex h-12 w-12 items-center justify-center rounded-full bg-[var(--accent-soft)] text-[var(--accent)]">
        <Icon name="questionmark.bubble" size={22} />
      </span>
      <div className="font-secondary text-[var(--text-2)]">{text}</div>
      {qa.scanError && <div className="font-caption text-[var(--danger)]">{qa.scanError}</div>}
      {!meeting.isLive && !qa.scanning && <PushButton prominent title={qa.scannedThrough < 0 ? tr("找问题") : tr("再找一次")} disabled={!m.canRunBackgroundWork || m.transcriptLines(meeting.id).length === 0} onClick={() => void m.findQuestions(meeting.id, qa.scannedThrough >= 0)} />}
    </div>
  );
}

function QuestionCard({ question, isFirst, isLast, meetingID, onContinueInChat }: { question: MeetingQuestion; isFirst: boolean; isLast: boolean; meetingID: string; onContinueInChat: () => void }) {
  const m = useModel();
  const [expanded, setExpanded] = useState(false);
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState("");
  const [menu, setMenu] = useState<HTMLElement | null>(null);
  const answerBox = useRef<HTMLDivElement>(null);
  const [answerHeight, setAnswerHeight] = useState(0);
  useLayoutEffect(() => {
    const el = answerBox.current?.firstElementChild as HTMLElement | null;
    if (!el) return;
    const ro = new ResizeObserver(() => setAnswerHeight(el.offsetHeight));
    ro.observe(el);
    return () => ro.disconnect();
  }, [!!question.answer]);
  const folded = 150;
  const overflows = answerHeight > folded + 8;
  const isFolded = question.status === "answered" && !expanded && overflows;
  const save = () => {
    m.editQuestion(question.id, meetingID, draft);
    setEditing(false);
  };
  const open = (c: ChatCitation) => {
    const time = c.meetingID === meetingID ? QuestionFinder.seconds(c.detail) : null;
    if (time != null) m.jumpTranscript(meetingID, time);
    else m.openCitation(c);
  };
  const status = {
    waiting: <span className="font-caption text-[var(--text-2)]">{tr("等待提问")}</span>,
    queued: <span className="font-caption text-[var(--text-2)]">{tr("排队中")}</span>,
    answering: (
      <span className="font-caption flex items-center gap-1 text-[var(--text-2)]">
        <DotLoader style="breeze" height={13} />
        <span className="shimmer">{tr("正在回答…")}</span>
      </span>
    ),
    answered: null,
    failed: <span className="font-caption text-[var(--danger)]">{tr("回答失败")}</span>,
  }[question.status];
  return (
    <div className="flex flex-col gap-2 rounded-[var(--r-card)] bg-[var(--surface-inset)] p-3">
      <div className="flex items-center gap-2">
        <button onClick={() => m.jumpTranscript(meetingID, question.at)} title={tr("在转写里查看这一刻")} className="press font-caption inline-flex items-center gap-1 rounded-full bg-[var(--accent-soft)] px-2 py-[3px] tabular-nums text-[var(--accent)]">
          <Icon name="clock" size={11} />
          {formatClock(question.at)}
        </button>
        {status}
        <div className="flex-1" />
        <button onClick={(e) => setMenu(e.currentTarget)} className="flex h-[18px] w-[22px] items-center justify-center text-[var(--text-2)]">
          <Icon name="ellipsis" size={15} />
        </button>
      </div>
      {editing ? (
        <>
          <textarea autoFocus value={draft} onChange={(e) => setDraft(e.target.value)} onKeyDown={(e) => e.key === "Enter" && !e.shiftKey && (e.preventDefault(), save())} placeholder={tr("问题")} className="font-body resize-none bg-transparent font-semibold outline-none" rows={2} />
          <div className="flex gap-2">
            <PushButton small title={tr("取消")} onClick={() => setEditing(false)} />
            <PushButton small prominent title={tr("保存")} onClick={save} />
          </div>
        </>
      ) : (
        <div className="font-body selectable font-semibold">{question.text}</div>
      )}
      {question.quote && <div className="font-caption line-clamp-2 text-[var(--text-2)]">“{question.quote}”</div>}
      {question.answer && (
        <div ref={answerBox} className="overflow-hidden transition-[max-height] duration-300" style={{ maxHeight: isFolded ? folded : answerHeight || undefined, maskImage: isFolded ? "linear-gradient(black 70%, transparent)" : undefined, WebkitMaskImage: isFolded ? "linear-gradient(black 70%, transparent)" : undefined }}>
          <div>
            <AnswerBody source={question.answer} streaming={question.status === "answering"} citations={question.citations} onOpenCitation={open} />
          </div>
        </div>
      )}
      {question.error && question.status === "failed" && <div className="font-caption selectable text-[var(--danger)]">{question.error}</div>}
      <div className="font-caption flex items-center gap-3">
        {(question.status === "waiting" || question.status === "failed") && <PushButton small prominent title={question.status === "failed" ? tr("重试") : tr("回答")} onClick={() => m.askQuestion(question.id, meetingID)} />}
        {question.status === "answered" && (
          <>
            {overflows && (
              <button onClick={() => setExpanded(!expanded)} className="text-[var(--accent)]">
                {expanded ? tr("收起") : tr("展开")}
              </button>
            )}
            <button onClick={onContinueInChat} className="text-[var(--accent)]">
              {tr("在提问中继续")}
            </button>
          </>
        )}
      </div>
      {menu && (
        <Menu
          anchor={menu}
          align="end"
          onClose={() => setMenu(null)}
          items={[
            {
              kind: "item",
              title: tr("编辑问题"),
              disabled: question.status === "answering",
              onSelect: () => {
                setDraft(question.text);
                setEditing(true);
              },
            },
            ...(question.status === "answered" ? [{ kind: "item" as const, title: tr("重新回答"), onSelect: () => m.askQuestion(question.id, meetingID) }] : []),
            { kind: "divider" },
            { kind: "item", title: tr("上移"), disabled: isFirst, onSelect: () => m.moveQuestion(question.id, meetingID, 1) },
            { kind: "item", title: tr("下移"), disabled: isLast, onSelect: () => m.moveQuestion(question.id, meetingID, -1) },
            { kind: "divider" },
            { kind: "item", title: tr("删除"), destructive: true, disabled: question.status === "answering", onSelect: () => m.deleteQuestion(question.id, meetingID) },
          ]}
        />
      )}
    </div>
  );
}
