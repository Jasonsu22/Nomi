// Shell/Tutorial.swift: dims the window, cuts out the current button, and shows its tip beside it.
import { useEffect, useLayoutEffect, useState } from "react";
import { tr, trf } from "../../i18n";
import { useModel } from "../../app";
import { tutorialStops, type TutorialStop } from "../../app/model";

const titles: Record<TutorialStop, string> = { meetings: "会议", record: "开始转录", sources: "资料", chat: "提问", settings: "设置" };
const bodies: Record<TutorialStop, string> = {
  meetings: "录过的会议和转写都在这里。打开一场会议可以看原文、译文和摘要。",
  record: "点这里选择输入设备和语言，然后开始录音。识别和翻译都在这台 Mac 上进行。",
  sources: "导入课件和文档，提问时可以让 Nomi 参考它们。",
  chat: "针对会议和资料提问。打开「联网」后，Nomi 也会上网查资料。",
  settings: "在这里选择模型、填写 API 和搜索密钥。",
};

export function TutorialOverlay() {
  const m = useModel();
  const stop = m.tutorialStep;
  const [rect, setRect] = useState<DOMRect | null>(null);
  const [size, setSize] = useState({ w: window.innerWidth, h: window.innerHeight });
  useLayoutEffect(() => {
    if (!stop) return;
    const el = document.querySelector(`[data-tutorial="${stop}"]`);
    setRect(el ? el.getBoundingClientRect() : null);
  }, [stop, m.version]);
  useEffect(() => {
    const resize = () => setSize({ w: window.innerWidth, h: window.innerHeight });
    window.addEventListener("resize", resize);
    return () => window.removeEventListener("resize", resize);
  }, []);
  useEffect(() => {
    const key = (e: KeyboardEvent) => {
      if (!stop) return;
      if (e.key === "Escape") m.set("tutorialStep", null);
      if (e.key === "Enter") move(1);
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  });
  if (!stop) return null;
  const index = tutorialStops.indexOf(stop);
  const isLast = index === tutorialStops.length - 1;
  const move = (step: number) => {
    const next = tutorialStops[index + step];
    if (next) m.set("tutorialStep", next);
    else m.set("tutorialStep", null);
  };
  const hole = rect ? { x: rect.left - 6, y: rect.top - 6, w: rect.width + 12, h: rect.height + 12 } : null;
  const bubbleWidth = 300, estimated = 190;
  let x: number, y: number;
  if (!hole) {
    x = (size.w - bubbleWidth) / 2;
    y = (size.h - estimated) / 2;
  } else if (hole.x + hole.w / 2 < size.w / 3) {
    x = hole.x + hole.w + 12;
    y = hole.y;
  } else {
    x = hole.x + hole.w - bubbleWidth;
    y = hole.y + hole.h + 12;
  }
  x = Math.min(Math.max(12, x), size.w - bubbleWidth - 12);
  y = Math.min(Math.max(12, y), size.h - estimated - 12);
  return (
    <div className="fade-in fixed inset-0 z-[800]">
      <svg className="absolute inset-0" width={size.w} height={size.h} onClick={(e) => e.stopPropagation()}>
        <path
          fill="rgba(0,0,0,0.45)"
          fillRule="evenodd"
          style={{ transition: "d 320ms var(--ease-smooth)" }}
          d={`M0 0H${size.w}V${size.h}H0Z` + (hole ? ` M${hole.x + 12} ${hole.y}H${hole.x + hole.w - 12}Q${hole.x + hole.w} ${hole.y} ${hole.x + hole.w} ${hole.y + 12}V${hole.y + hole.h - 12}Q${hole.x + hole.w} ${hole.y + hole.h} ${hole.x + hole.w - 12} ${hole.y + hole.h}H${hole.x + 12}Q${hole.x} ${hole.y + hole.h} ${hole.x} ${hole.y + hole.h - 12}V${hole.y + 12}Q${hole.x} ${hole.y} ${hole.x + 12} ${hole.y}Z` : "")}
        />
      </svg>
      <div key={stop} className="surface absolute flex flex-col gap-2 p-4 shadow-[0_6px_32px_rgba(0,0,0,0.18)]" style={{ left: x, top: y, width: bubbleWidth, animation: "pop 180ms ease-out 120ms backwards" }}>
        <div className="font-caption text-[var(--text-2)]">{trf("第 %d 步，共 %d 步", index + 1, tutorialStops.length)}</div>
        <div className="font-section-title">{tr(titles[stop])}</div>
        <div className="font-secondary">{tr(bodies[stop]).replace("这台 Mac", "这台电脑").replace("this Mac", "this PC")}</div>
        <div className="font-secondary flex items-center gap-2 pt-1">
          <button onClick={() => m.set("tutorialStep", null)} className="text-[var(--text-2)]">{tr("跳过")}</button>
          <div className="flex-1" />
          {index > 0 && <button onClick={() => move(-1)} className="press h-7 rounded-[7px] bg-[var(--surface-inset)] px-3 font-medium">{tr("上一步")}</button>}
          <button onClick={() => move(1)} className="press h-7 rounded-[7px] bg-[var(--accent)] px-3 font-medium text-[var(--on-accent)]">{isLast ? tr("完成") : tr("下一步")}</button>
        </div>
      </div>
    </div>
  );
}
