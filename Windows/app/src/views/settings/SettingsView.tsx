// Pages/SettingsView.swift: the narrow column of sections, like System Settings.
import { useEffect, useRef, useState } from "react";
import { interfaceLanguageKey, tr } from "../../i18n";
import { prefs } from "../../support/prefs";
import { Appearance, microphonePromptKey, type InterfaceAppearance } from "../../support/appearance";
import { ClassroomMicPreference } from "../../engine/audioInputs";
import { useModel } from "../../app";
import { Scroll, PopUp, SettingsRow, Switch } from "../ui/controls";
import { EngineSection, LocalModelsSection, SpeakerModelsSection } from "./LocalModels";
import { LLMSettingsSection } from "./LLMSettings";
import { MemorySettingsSection, PromptSettingsSection, SearchSettingsSection } from "./OtherSettings";

export function NarrowPage({ title, children, scrollRef }: { title: string; children: React.ReactNode; scrollRef?: React.RefObject<HTMLDivElement | null> }) {
  return (
    <Scroll innerRef={scrollRef} className="h-full">
      <div className="mx-auto flex max-w-[760px] flex-col pr-8 pb-12 pl-12">
        <h1 className="font-page-title pt-7 pb-6">{title}</h1>
        {children}
      </div>
    </Scroll>
  );
}

export function SettingsView() {
  const m = useModel();
  const [language, setLanguage] = useState(prefs.string(interfaceLanguageKey) ?? "system");
  const [appearance, setAppearance] = useState<InterfaceAppearance>(Appearance.choice);
  const [micPrompt, setMicPrompt] = useState(prefs.string(microphonePromptKey) ?? "ask");
  const [classroom, setClassroom] = useState(ClassroomMicPreference.isOn);
  const scroller = useRef<HTMLDivElement>(null);
  const reveal = (id: string) => {
    requestAnimationFrame(() => {
      const el = document.getElementById(id);
      const box = scroller.current;
      if (el && box) box.scrollTo({ top: el.offsetTop - 16, behavior: "smooth" });
    });
  };
  useEffect(() => {
    if (!m.revealSearchSettings) return;
    reveal("search-settings");
    m.revealSearchSettings = false;
  }, [m.revealSearchSettings]);
  useEffect(() => {
    if (!m.revealMemorySettings) return;
    reveal("memory-settings");
    m.revealMemorySettings = false;
  }, [m.revealMemorySettings]);
  useEffect(() => {
    m.localModels.refreshInBackground();
  }, []);
  return (
    <NarrowPage title={tr("设置")} scrollRef={scroller}>
      <div className="flex flex-col gap-8">
        <section className="flex flex-col gap-2">
          <h3 className="font-section-title pb-0.5">{tr("通用")}</h3>
          <div className="surface overflow-hidden">
            <SettingsRow title={tr("界面语言")}>
              <PopUp
                value={language}
                onChange={(v) => {
                  setLanguage(v);
                  prefs.set(interfaceLanguageKey, v);
                  window.location.reload();
                }}
                options={[
                  { value: "system", title: tr("跟随系统") },
                  { value: "zh-Hans", title: "简体中文" },
                  { value: "en", title: "English" },
                ]}
              />
            </SettingsRow>
            <div className="ml-4 h-px bg-[var(--separator)]" />
            <SettingsRow title={tr("外观")}>
              <PopUp
                value={appearance}
                onChange={(v) => {
                  Appearance.choice = v;
                  setAppearance(v);
                }}
                options={[
                  { value: "system", title: tr("跟随系统") },
                  { value: "light", title: tr("白色") },
                  { value: "dark", title: tr("黑色") },
                ]}
              />
            </SettingsRow>
          </div>
        </section>
        <LocalModelsSection>
          <SettingsRow title={tr("麦克风权限")}>
            <PopUp
              value={micPrompt}
              onChange={(v) => {
                setMicPrompt(v);
                prefs.set(microphonePromptKey, v);
                if (v === "allow") void m.audioInputs.refresh();
              }}
              options={[
                { value: "ask", title: tr("开始时询问") },
                { value: "allow", title: tr("全部允许") },
              ]}
            />
          </SettingsRow>
          <SettingsRow title={tr("课堂麦克风（实验）")} detail={tr("用 Mac 自带麦克风录音时，降低教室噪音并自动调整音量。如果老师离得远、声音反而变小，就关掉。下一次开始录音时生效。").replace("用 Mac 自带麦克风", "用电脑自带麦克风").replace("the Mac's built-in", "the computer's built-in")}>
            <Switch
              label={tr("课堂麦克风（实验）")}
              on={classroom}
              onChange={(v) => {
                prefs.set(ClassroomMicPreference.key, v);
                setClassroom(v);
              }}
            />
          </SettingsRow>
        </LocalModelsSection>
        <EngineSection />
        <SpeakerModelsSection />
        <LLMSettingsSection />
        <SearchSettingsSection id="search-settings" />
        <PromptSettingsSection />
        <MemorySettingsSection id="memory-settings" />
      </div>
    </NarrowPage>
  );
}
