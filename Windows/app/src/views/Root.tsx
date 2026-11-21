// Shell/AppShell.swift: the top bar and rail around the pages; the compact meeting window; the
// sheets, alerts, picture viewer and the teacher's-question pop-up over everything.
import { useEffect, useState } from "react";
import { tr } from "../i18n";
import { keptAlive, type AppPage } from "../app/model";
import { model, useModel } from "../app";
import { OnboardingPreference } from "../app/onboarding";
import { Appearance } from "../support/appearance";
import { app } from "../platform";
import { Alert } from "./ui/controls";
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

export function Root() {
  const m = useModel();
  const [ready, setReady] = useState(false);
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
      {m.exportError && <Alert title={tr("导出失败")} message={m.exportError} actions={[{ title: tr("好"), role: "cancel", onClick: () => m.set("exportError", null) }]} />}
      {m.storageError && <Alert title={tr("会议存储")} message={m.storageError} actions={[{ title: tr("好"), role: "cancel", onClick: () => m.set("storageError", null) }]} />}
    </div>
  );
}
