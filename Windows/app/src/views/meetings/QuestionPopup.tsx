// Meetings/QuestionPopupView.swift: the teacher's question floating over the window while recording.
import { useEffect, useRef, useState } from "react";
import { tr } from "../../i18n";
import { formatClock } from "../../support/format";
import type { QuestionPopup } from "../../app/model";
import type { MeetingQuestion } from "../../models/meetingQA";
import { useModel } from "../../app";
import { Icon } from "../ui/Icon";
import { PushButton } from "../ui/controls";

const askSeconds = 8;
const answeredSeconds = 10;
type Phase = "asking" | "answering" | "answered" | "failed";

function CountdownBar({ seconds, paused, onFinish }: { seconds: number; paused: boolean; onFinish: () => void }) {
  const bar = useRef<HTMLDivElement>(null);
  const elapsed = useRef(0);
  const resumed = useRef<number | null>(null);
  const finish = useRef(onFinish);
  finish.current = onFinish;
  useEffect(() => {
    if (paused) {
      if (resumed.current != null) elapsed.current += (performance.now() - resumed.current) / 1000;
      resumed.current = null;
      return;
    }
    resumed.current = performance.now();
    let frame = 0;
    const tick = () => {
      const total = elapsed.current + (performance.now() - resumed.current!) / 1000;
      const left = Math.max(0, 1 - total / seconds);
      if (bar.current) bar.current.style.transform = `scaleX(${left})`;
      if (left <= 0) finish.current();
      else frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [paused, seconds]);
  return (
    <div className="absolute right-[18px] bottom-[1px] left-[18px] h-[3px]">
      <div ref={bar} className="h-full origin-left rounded-full" style={{ background: "color-mix(in srgb, var(--accent) 35%, transparent)" }} />
    </div>
  );
}

export function QuestionPopupView({ popup, width = 380 }: { popup: QuestionPopup; width?: number | null }) {
  const m = useModel();
  const [hovering, setHovering] = useState(false);
  const question = m.questionFor(popup);
  useEffect(() => {
    if (!question) m.closeQuestionPopup();
  }, [!!question]);
  if (!question) return null;
  const phase: Phase = !popup.answering ? "asking" : question.status === "answered" ? "answered" : question.status === "failed" ? "failed" : "answering";
  const label = { asking: tr("老师提问"), answering: tr("正在回答"), answered: tr("已回答"), failed: tr("没能回答") }[phase];
  const dismiss = () => (phase === "asking" ? m.questionPopupTimedOut() : m.closeQuestionPopup());
  return (
    <div
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
      aria-label={tr("老师提问")}
      className="relative flex flex-col rounded-[18px] border border-[var(--separator)] bg-[var(--surface)] px-[18px] pt-4 pb-3.5 shadow-[0_14px_52px_rgba(0,0,0,0.18)]"
      style={{ width: width ?? "100%" }}
      onKeyDown={(e) => e.key === "Enter" && phase === "asking" && m.answerPopupQuestionNow()}
    >
      <div className="flex items-center gap-2">
        <span className={`h-2 w-2 rounded-full ${phase !== "answered" ? "live-dot" : ""}`} style={{ background: phase === "failed" ? "var(--danger)" : "var(--accent-green)" }} />
        <span className="font-caption font-bold text-[var(--accent)]">{`${label} · ${formatClock(question.at)}`}</span>
        <div className="flex-1" />
        <button onClick={dismiss} aria-label={tr("关闭")} className="flex h-[22px] w-[22px] items-center justify-center text-[var(--text-2)]">
          <Icon name="xmark" size={11} weight={3} />
        </button>
      </div>
      <div className="pt-2 text-[16px] leading-[22px] font-semibold">{question.text}</div>
      {question.quote && question.quote !== question.text && <div className="font-secondary line-clamp-2 pt-0.5 text-[var(--accent)]">{question.quote}</div>}
      {phase !== "asking" && <Answer question={question} phase={phase} />}
      <div className="flex items-center gap-2 pt-3">
        <button
          onClick={() => {
            m.page = "meetings";
            m.openMeetingID = popup.meetingID;
            m.jumpTranscript(popup.meetingID, question.at);
          }}
          title={tr("跳到这一刻")}
          className="font-caption rounded-[6px] bg-[var(--accent-soft)] px-2 py-0.5 font-bold tabular-nums text-[var(--accent)]"
        >
          {formatClock(question.at)}
        </button>
        <div className="flex-1" />
        {phase === "asking" ? (
          <>
            <PushButton title={tr("稍后")} onClick={() => m.answerPopupQuestionLater()} />
            <PushButton prominent title={tr("现在回答")} onClick={() => m.answerPopupQuestionNow()} />
          </>
        ) : (
          <button onClick={() => m.openPopupQuestionInQA()} className="font-secondary text-[var(--accent)]">
            {tr("在 Q&A 中查看")}
          </button>
        )}
      </div>
      {phase !== "answering" && <CountdownBar key={phase} seconds={phase === "asking" ? askSeconds : answeredSeconds} paused={hovering} onFinish={dismiss} />}
    </div>
  );
}

function Answer({ question, phase }: { question: MeetingQuestion; phase: Phase }) {
  return (
    <div className="font-secondary pt-2.5 leading-[20px]">
      {phase === "failed" ? (
        <span className="text-[var(--danger)]">{question.error ?? tr("没能回答")}</span>
      ) : !question.answer ? (
        <div className="flex flex-col gap-[7px] py-0.5">
          <div className="live-dot h-2.5 rounded-[5px] bg-[var(--surface-inset)]" />
          <div className="live-dot h-2.5 w-[220px] rounded-[5px] bg-[var(--surface-inset)]" />
        </div>
      ) : (
        <div className="line-clamp-5 text-[var(--text-2)]">{question.answer.replace(/\*\*|__|`|^#+\s*/gm, "")}</div>
      )}
    </div>
  );
}
