// Meetings/MeetingAssistantPanel.swift: the summary tab (and the older per-meeting questions).
import { useEffect, useState } from "react";
import { tr } from "../../i18n";
import { MeetingAssistantRecordOps, type Meeting } from "../../models/meeting";
import { useModel } from "../../app";
import { AnswerBody } from "../answer/AnswerBody";
import { DotLoader } from "../ui/DotLoader";
import { LinkButton, PushButton, Scroll } from "../ui/controls";

export function MeetingAssistantPanel({ meeting, summary = false }: { meeting: Meeting; summary?: boolean }) {
  const m = useModel();
  const [question, setQuestion] = useState("");
  const state = m.assistantStates[meeting.id];
  const record = meeting.assistant;
  const shownSummary = state?.summary ?? record?.summary ?? null;
  const shownSummaryModel = state && state.summary != null ? state.summaryModelName : (record?.summaryModelName ?? "");
  const answers = state ? state.answers : (record?.answers ?? []);
  const stale = !state?.isGenerating && !!record && (state?.summary == null || state.summary === record.summary) && MeetingAssistantRecordOps.summaryIsStale(record, Math.max(0, ...meeting.paragraphs.map((p) => p.openedAt)));
  useEffect(() => {
    if (state?.answers.at(-1)?.question === question.trim()) setQuestion("");
  }, [state?.answers.length]);
  const result = (text: string, modelName: string, streaming = false) => (
    <div className="flex flex-col gap-2">
      <AnswerBody source={text} streaming={streaming} />
      {modelName && <div className="font-caption text-[var(--text-2)]">{modelName}</div>}
    </div>
  );
  return (
    <div className="flex h-full min-h-0 flex-col gap-3 p-4">
      <div className="font-caption text-[var(--text-2)]">{m.assistantModelName}</div>
      <Scroll className="min-h-0 flex-1">
        <div className="flex flex-col gap-4">
          {summary ? (
            state?.isGenerating && state.draft ? (
              result(state.draft, state.summaryModelName, true)
            ) : shownSummary ? (
              <>
                {result(shownSummary, shownSummaryModel)}
                {stale && <div className="font-caption text-[var(--text-2)]">{tr("转写有更新，可以重新生成摘要。")}</div>}
              </>
            ) : (
              <div className="font-secondary text-[var(--text-2)]">{tr("生成这场会议的要点、术语和结论。")}</div>
            )
          ) : (
            <>
              {!answers.length && !state?.draft && <div className="font-secondary text-[var(--text-2)]">{tr("根据这场会议的转写提问，回答会引用相关时间。")}</div>}
              {answers.map((a) => (
                <div key={a.id} className="flex flex-col gap-2">
                  <div className="font-body font-medium">{a.question}</div>
                  {result(a.answer, a.modelName)}
                </div>
              ))}
              {state?.isGenerating && state.draft && result(state.draft, "", true)}
            </>
          )}
        </div>
      </Scroll>
      {state?.error && <div className="font-caption selectable text-[var(--danger)]">{state.error}</div>}
      {!summary && <textarea value={question} onChange={(e) => setQuestion(e.target.value)} aria-label={tr("输入问题")} className="font-secondary h-[72px] resize-none rounded-[var(--r-field)] bg-[var(--surface-inset)] p-2 outline-none" />}
      <div className="flex items-center gap-2">
        {state?.isGenerating && (
          <>
            <DotLoader style="breeze" />
            <span className="font-caption shimmer">{tr("正在生成…")}</span>
          </>
        )}
        <div className="flex-1" />
        <PushButton
          prominent
          title={summary ? (shownSummary == null ? tr("生成摘要") : tr("重新生成")) : tr("发送")}
          disabled={!m.canGenerateAssistant || (!summary && !question.trim())}
          onClick={() => m.generateAssistant(meeting.id, summary ? null : question.trim())}
        />
      </div>
      {m.llmConfiguration.mode === "api" && <div className="font-caption text-[var(--text-2)]">{tr("使用 API 会将这场会议的文字发送到所选服务。")}</div>}
      {!m.canGenerateAssistant && !m.assistantIsBusy && (m.engine.session.phase !== "idle" ? <div className="font-caption text-[var(--text-2)]">{tr("录制结束后可生成回答和摘要。")}</div> : <LinkButton title={tr("配置大模型")} onClick={() => m.select("settings")} />)}
    </div>
  );
}
