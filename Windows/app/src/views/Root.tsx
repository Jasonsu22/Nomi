// Shell/AppShell.swift: the top bar and rail around the pages; the compact meeting window; the
// sheets, alerts, picture viewer and the teacher's-question pop-up over everything.
import { useEffect, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { tr } from "../i18n";
import { keptAlive, type AppPage } from "../app/model";
import { model, useModel } from "../app";
import { OnboardingPreference } from "../app/onboarding";
import { Appearance } from "../support/appearance";
import { app, closeActionKey, type CloseAction } from "../platform";
import { flushPrefs, prefs } from "../support/prefs";
import { Alert, PushButton, Sheet } from "./ui/controls";
import { TopBar } from "./shell/TopBar";
import { Rail } from "./shell/Rail";
import { TutorialOverlay } from "./shell/Tutorial";
import { RecordingSetupView } from "./shell/RecordingSetup";
import { OnboardingView } from "./shell/Onboarding";
import { CompactMeetingView, MeetingsPage } from "./meetings/MeetingDetail";
import { QuestionPopupView } from "./meetings/QuestionPopup";
import { AskView } from "./ask/AskView";
import { ChatImageLightbox } from "./ask/ChatImages";
import { SourcesView } from "./sources/SourcesView";
import { SettingsView } from "./settings/SettingsView";
import { HelpView } from "./settings/HelpView";
import { PDFViewerSheet } from "./answer/Pdf";

function page(p: AppPage) {
  switch (p) {
    case "meetings":
      return <MeetingsPage />;
    case "ask":
      return <AskView />;
    case "sources":
      return <SourcesView />;
    case "help":
      return <HelpView />;
    case "settings":
      return <SettingsView />;
  }
}

/** The primary pages stay built after their first visit; returning to one only fades it in. */
function Pages() {
  const m = useModel();
  const [visited, setVisited] = useState<Set<AppPage>>(new Set([m.page]));
  useEffect(() => {
    if (keptAlive.includes(m.page) && !visited.has(m.page)) setVisited(new Set([...visited, m.page]));
    (document.activeElement as HTMLElement | null)?.blur?.();
  }, [m.page]);
  return (
    <div className="relative min-w-0 flex-1 overflow-hidden">
      {keptAlive.map((p) =>
        visited.has(p) || m.page === p ? (
          <div key={p} className="page absolute inset-0" data-active={m.page === p} aria-hidden={m.page !== p}>
            {page(p)}
          </div>
        ) : null,
      )}
      {!keptAlive.includes(m.page) && (
        <div key={m.page} className="enter absolute inset-0 z-[2]">
          {page(m.page)}
        </div>
      )}
    </div>
  );
}

/** The first press of the close button: quit, or keep Nomi running on the taskbar. Remembered. */
function CloseChoiceSheet({ onClose }: { onClose: () => void }) {
  const choose = async (choice: CloseAction) => {
    prefs.set(closeActionKey, choice);
    await flushPrefs();
    onClose();
    await app.closeChoice(choice).catch(() => {});
  };
  return (
    <Sheet width={400} onClose={onClose}>
      <div className="flex flex-col gap-2 p-6">
        <div className="font-section-title">{tr("关闭窗口时")}</div>
        <div className="font-secondary text-[var(--text-2)]">{tr("最小化后 Nomi 留在任务栏上继续运行，录音不会中断。之后可以在 设置 › 通用 中更改。")}</div>
        <div className="mt-4 flex items-center gap-2">
          <PushButton title={tr("取消")} onClick={onClose} />
          <div className="flex-1" />
          <PushButton title={tr("退出 Nomi")} onClick={() => void choose("quit")} />
          <PushButton prominent title={tr("最小化")} onClick={() => void choose("minimize")} />
        </div>
      </div>
    </Sheet>
  );
}

export function Root() {
  const m = useModel();
  const [ready, setReady] = useState(false);
  const [askClose, setAskClose] = useState(false);
  useEffect(() => {
    const off = listen("nomi://close-asked", () => setAskClose(true));
    return () => void off.then((f) => f());
  }, []);
  const compact = m.meetingCompact && m.openMeetingID !== null;
  useEffect(() => {
    Appearance.apply();
    void model.load().then(() => {
      setReady(true);
      if (!OnboardingPreference.done) model.set("onboardingPresented", true);
      void model.updater.start();
    });
  }, []);
  useEffect(() => {
    void app.setCompact(compact).catch(() => {});
  }, [compact]);
  useEffect(() => {
    const key = (e: KeyboardEvent) => {
      const ctrl = e.ctrlKey || e.metaKey;
      if (!ctrl) return;
      if (e.key === "q") {
        e.preventDefault();
        void flushPrefs().then(() => app.quit());
        return;
      }
      if (e.key === "f" && m.page === "meetings") {
        e.preventDefault();
        m.requestSearch();
      } else if (e.key === "," ) {
        e.preventDefault();
        m.select("settings");
      } else if (e.key === "n" && m.page === "ask") {
        e.preventDefault();
        m.beginNewChat(null);
      } else if (e.key >= "1" && e.key <= "3") {
        e.preventDefault();
        m.select((["meetings", "sources", "ask"] as AppPage[])[Number(e.key) - 1]);
      }
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  });
  const popup = m.questionPopup;
  return (
    <div className="h-full bg-[var(--canvas)] text-[var(--text)]">
      {!ready ? (
        <div className="h-full" data-tauri-drag-region />
      ) : compact && m.openMeetingID ? (
        <div className="fade-in h-full">
          <CompactMeetingView meetingID={m.openMeetingID} />
        </div>
      ) : (
        <div className="fade-in flex h-full flex-col">
          <TopBar />
          <div className="flex min-h-0 flex-1">
            <Rail />
            <Pages />
          </div>
          <TutorialOverlay />
        </div>
      )}
      {!compact && popup && m.engine.session.phase !== "idle" && (
        <div key={popup.questionID} className="rise-in fixed right-6 bottom-6 z-[700]">
          <QuestionPopupView popup={popup} />
        </div>
      )}
      <ChatImageLightbox />
      {m.onboardingPresented && <OnboardingView />}
      {m.recordingSetupPresented && <RecordingSetupView />}
      <PDFViewerSheet />
      {askClose && <CloseChoiceSheet onClose={() => setAskClose(false)} />}
      {m.exportError && <Alert title={tr("导出失败")} message={m.exportError} actions={[{ title: tr("好"), role: "cancel", onClick: () => m.set("exportError", null) }]} />}
      {m.storageError && <Alert title={tr("会议存储")} message={m.storageError} actions={[{ title: tr("好"), role: "cancel", onClick: () => m.set("storageError", null) }]} />}
    </div>
  );
}
