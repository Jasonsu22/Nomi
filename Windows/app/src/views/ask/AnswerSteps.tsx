// Pages/AnswerStepsView.swift: what Nomi is doing for an answer, and the folded line afterwards.
import { useEffect, useState } from "react";
import { trf } from "../../i18n";
import { nowReference } from "../../support/format";
import { AnswerStepSummary, isRunning, stepSeconds, type AnswerStep } from "../../models/answerSteps";
import { DotLoader, dotStyle } from "../ui/DotLoader";
import { Icon } from "../ui/Icon";

function Seconds({ step }: { step: AnswerStep }) {
  const [, tick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => tick((n) => n + 1), 1000);
    return () => clearInterval(id);
  }, []);
  return <span className="text-[11px] tabular-nums text-[var(--text-2)] opacity-80">{trf("%d 秒", stepSeconds(step, nowReference()))}</span>;
}

export function AnswerStepsView({ steps, thinking }: { steps: AnswerStep[]; thinking: string }) {
  const [open, setOpen] = useState<string | null>(null);
  const shown = steps.filter((s) => isRunning(s) || s.detail);
  if (!shown.length) return null;
  return (
    <div className="flex flex-col gap-1.5 border-l-2 border-[var(--separator)] pl-3">
      {shown.map((step) =>
        isRunning(step) ? (
          <div key={step.id} className="fade-in flex flex-col gap-1.5">
            <div className="flex items-center gap-2">
              <DotLoader style={dotStyle(step.kind)} />
              <span className="font-secondary shimmer truncate">{step.title}</span>
              <Seconds step={step} />
            </div>
            {step.kind === "thinking" && thinking.trim() && (
              <div className="selectable ml-6 line-clamp-4 rounded-[10px] bg-[var(--surface-inset)] px-2.5 py-2 text-[12px] text-[var(--text-2)]" style={{ display: "-webkit-box", WebkitBoxOrient: "vertical", WebkitLineClamp: 4, overflow: "hidden", direction: "ltr" }}>
                {thinking.trim().slice(-600)}
              </div>
            )}
          </div>
        ) : (
          <div key={step.id} className="flex flex-col gap-1.5">
            <div className="flex items-center gap-2">
              <span className="flex w-8 justify-center text-[var(--accent-green)]">
                <Icon name="checkmark" size={11} weight={3.2} />
              </span>
              {step.thought ? (
                <button onClick={() => setOpen(open === step.id ? null : step.id)} className="font-secondary flex items-center gap-1 text-[var(--text-2)]">
                  {step.detail}
                  <Icon name={open === step.id ? "chevron.down" : "chevron.right"} size={10} weight={2.6} />
                </button>
              ) : (
                <span className="font-secondary truncate text-[var(--text-2)]">{step.detail}</span>
              )}
            </div>
            {open === step.id && <div className="selectable ml-6 rounded-[10px] bg-[var(--surface-inset)] px-2.5 py-2 text-[12px] whitespace-pre-wrap text-[var(--text-2)]">{step.thought}</div>}
          </div>
        ),
      )}
    </div>
  );
}

export function AnswerStepsFold({ steps, seconds }: { steps: AnswerStep[]; seconds: number | null | undefined }) {
  const [open, setOpen] = useState(false);
  const line = AnswerStepSummary.line(steps, seconds, nowReference());
  if (!line) return null;
  return (
    <div className="flex flex-col gap-1.5">
      <button onClick={() => setOpen(!open)} disabled={!steps.length} className="flex items-center gap-1 self-start text-[12px] text-[var(--text-2)]">
        {line}
        {steps.length > 0 && <Icon name={open ? "chevron.down" : "chevron.right"} size={10} weight={2.6} />}
      </button>
      {open && <AnswerStepsView steps={steps} thinking="" />}
    </div>
  );
}
