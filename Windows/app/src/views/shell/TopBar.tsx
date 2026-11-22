// Shell/TopBar.swift: the logo and name, the engine status, and the recording capsule.
import { useEffect, useState } from "react";
import { tr } from "../../i18n";
import { useModel } from "../../app";
import { BrandLogo } from "../ui/Logos";
import { StatusChip } from "../ui/controls";
import { Icon } from "../ui/Icon";
import { SessionControl } from "./SessionControl";

export const railWidth = 72;

/** Errors stay put. A ready engine fades in, shows for two seconds, then fades out. */
function HeaderStatus({ title, live, stays, isError }: { title: string; live: boolean; stays: boolean; isError: boolean }) {
  const [visible, setVisible] = useState(true);
  useEffect(() => {
    setVisible(true);
    if (stays) return;
    const id = setTimeout(() => setVisible(false), 2000);
    return () => clearTimeout(id);
  }, [title, stays]);
  return (
    <span className="transition-opacity" style={{ opacity: visible ? 1 : 0, transitionDuration: visible ? "300ms" : "450ms" }} aria-hidden={!visible}>
      <StatusChip title={title} live={live} isError={isError} />
    </span>
  );
}

export function TopBar() {
  const m = useModel();
  const e = m.engine;
  return (
    <div className="flex h-[52px] shrink-0 items-center pr-4" data-tauri-drag-region>
      <div className="flex items-center pr-3" data-tauri-drag-region>
        <div className="flex justify-center pl-2" style={{ width: railWidth - 16 + 8 }} data-tauri-drag-region>
          <BrandLogo side={32} />
        </div>
        <span className="text-[19px] font-semibold" data-tauri-drag-region>Nomi</span>
      </div>
      {e.readiness === "asrMissing" && e.session.phase === "idle" ? (
        <button onClick={() => m.set("onboardingPresented", true)} className="press font-secondary inline-flex items-center gap-1.5 rounded-full bg-[color-mix(in_srgb,var(--danger)_10%,transparent)] px-3 py-1.5 font-semibold text-[var(--danger)]" title={tr("打开设置向导，下载语音识别和翻译模型")}>
          <Icon name="arrow.down.circle.fill" size={14} />
          {tr("下载模型")}
        </button>
      ) : (
        <HeaderStatus title={m.statusTitle} live={m.statusIsLive} stays={m.statusStays} isError={m.statusIsError} />
      )}
      <div className="flex-1 self-stretch" data-tauri-drag-region />
      <SessionControl
        session={e.session}
        meter={e.level}
        canStart={m.canStart}
        startTitle={m.recordingActionTitle}
        onStart={() => m.performRecordingAction()}
        onStop={() => m.stopTranscription()}
        onTogglePause={() => m.togglePause()}
        onOpen={() => m.openLiveMeeting()}
      />
    </div>
  );
}
