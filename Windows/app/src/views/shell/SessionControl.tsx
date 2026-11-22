// DesignSystem/Components/RecordingCapsule.swift and DotWaveform.swift: the recording capsule in
// the top bar, in tinted Liquid Glass as on the Mac.
import { useEffect, useRef, useState } from "react";
import { tr } from "../../i18n";
import { formatClock } from "../../support/format";
import type { LevelMeter, SessionState } from "../../models/session";
import { Icon } from "../ui/Icon";

export function DotWaveform({ meter, paused }: { meter: LevelMeter; paused: boolean }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const el = canvas.current;
    const ctx = el?.getContext("2d");
    if (!el || !ctx) return;
    const scale = window.devicePixelRatio || 1;
    const width = 96, height = 16, count = 24, gap = 2;
    el.width = width * scale;
    el.height = height * scale;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    let frame = 0;
    const frozen = paused ? performance.now() / 1000 : null;
    const draw = () => {
      const time = frozen ?? performance.now() / 1000;
      ctx.setTransform(scale, 0, 0, scale, 0, 0);
      ctx.clearRect(0, 0, width, height);
      ctx.fillStyle = getComputedStyle(el).color;
      const d = (width - gap * (count - 1)) / count;
      for (let i = 0; i < count; i++) {
        const level = meter.columnLevel(i, count, time, reduce);
        const h = Math.max(d, height * level);
        const x = i * (d + gap), y = (height - h) / 2;
        ctx.beginPath();
        ctx.ellipse(x + d / 2, y + h / 2, d / 2, h / 2, 0, 0, Math.PI * 2);
        ctx.fill();
      }
      if (!paused) frame = requestAnimationFrame(draw);
    };
    draw();
    return () => cancelAnimationFrame(frame);
  }, [meter, paused]);
  return <canvas ref={canvas} style={{ width: 96, height: 16, opacity: paused ? 0.45 : 1 }} aria-hidden />;
}

function Clock({ session }: { session: SessionState }) {
  const [, tick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => tick((n) => n + 1), 500);
    return () => clearInterval(id);
  }, []);
  const elapsed = session.elapsed;
  return <span className="tabular-nums" style={{ fontSize: 13, fontWeight: 600, width: elapsed >= 3600 ? 64 : 48, display: "inline-block" }}>{formatClock(elapsed)}</span>;
}

export function SessionControl({ session, meter, canStart, startTitle, onStart, onStop, onTogglePause, onOpen }: {
  session: SessionState;
  meter: LevelMeter;
  canStart: boolean;
  startTitle: string;
  onStart: () => void;
  onStop: () => void;
  onTogglePause: () => void;
  onOpen?: () => void;
}) {
  const listening = session.phase === "listening" || session.phase === "stopping";
  const fill = listening ? "var(--selection)" : "var(--accent)";
  const ink = listening ? "var(--on-selection)" : "var(--on-accent)";
  const capsule = "glass inline-flex h-10 items-center rounded-full transition-[background-color,width] duration-[420ms]";
  const style = { background: `color-mix(in srgb, ${fill} 82%, transparent)`, color: ink, transitionTimingFunction: "var(--ease-bouncy)" };
  if (session.phase === "idle") {
    return (
      <button data-tutorial="record" onClick={onStart} disabled={!canStart} className={`${capsule} press gap-2 px-4 font-semibold disabled:opacity-40`} style={style}>
        <Icon name="waveform" size={16} />
        <span className="font-secondary font-semibold">{startTitle}</span>
      </button>
    );
  }
  if (session.phase === "preparing") {
    return (
      <span data-tutorial="record" className={`${capsule} gap-2 px-4`} style={style}>
        <Icon name="waveform" size={16} className="live-dot" />
        <span className="font-secondary font-semibold">{tr("准备中")}</span>
      </span>
    );
  }
  if (session.phase === "stopping") {
    return (
      <span data-tutorial="record" className={`${capsule} px-4`} style={style}>
        <span className="font-secondary font-semibold">{tr("正在保存")}</span>
      </span>
    );
  }
  return (
    <div data-tutorial="record" className={`${capsule} relative gap-1.5 pr-1 pl-3.5`} style={style}>
      {onOpen && <button className="absolute inset-0 rounded-full" onClick={onOpen} title={tr("回到正在录制的会议")} aria-label={tr("回到正在录制的会议")} />}
      <span className="pointer-events-none relative flex items-center gap-2.5">
        <DotWaveform meter={meter} paused={session.isPaused} />
        <Clock session={session} />
      </span>
      <span className="relative flex items-center gap-0.5">
        <button onClick={onTogglePause} aria-label={session.isPaused ? tr("继续") : tr("暂停")} className="press flex h-full items-center px-1">
          <span className="flex h-[22px] w-[22px] items-center justify-center rounded-full bg-[var(--surface)]" style={{ color: ink }}>
            <Icon name={session.isPaused ? "play.fill" : "pause.fill"} size={10} weight={3} />
          </span>
        </button>
        <button onClick={onStop} aria-label={tr("停止")} className="press flex h-full items-center px-1">
          <span className="flex h-[22px] w-[22px] items-center justify-center rounded-full bg-[#ff3b30] text-white">
            <Icon name="stop.fill" size={9} weight={3} />
          </span>
        </button>
      </span>
    </div>
  );
}
