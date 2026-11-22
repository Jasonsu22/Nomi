// Pages/HelpView.swift: app information, the tutorial, the setup guide, contact, and updates.
import { useState } from "react";
import { tr } from "../../i18n";
import { useModel } from "../../app";
import { app, shell } from "../../platform";
import { BrandLogo } from "../ui/Logos";
import { Icon } from "../ui/Icon";
import { PushButton, SettingsRow, SettingsSection, Switch } from "../ui/controls";
import { NarrowPage } from "./SettingsView";

const contactEmail = "jasonsu210@gmail.com";

async function mailBody() {
  const version = await app.version().catch(() => "?");
  const system = await app.diagnostics().catch(() => navigator.userAgent);
  return [tr("你好，"), "", tr("主题："), "", tr("发生了什么："), "", tr("复现步骤："), "1. ", "", "—", `Nomi for Windows ${version}`, system].join("\n");
}

function Row({ title, detail, onClick }: { title: string; detail: string; onClick: () => void }) {
  return (
    <button onClick={onClick} className="flex w-full items-center px-4 py-3.5 text-left hover:bg-[var(--surface-inset)]">
      <span className="flex flex-1 flex-col gap-1">
        <span className="font-body">{title}</span>
        <span className="font-secondary text-[var(--text-2)]">{detail}</span>
      </span>
      <span className="text-[var(--text-2)]">
        <Icon name="chevron.right" size={13} weight={2.6} />
      </span>
    </button>
  );
}

export function HelpView() {
  const m = useModel();
  const [auto, setAuto] = useState(m.updater.automaticallyChecks);
  const divider = <div className="mx-4 h-px bg-[var(--separator)]" />;
  const u = m.updater;
  return (
    <NarrowPage title={tr("帮助")}>
      <div className="flex flex-col gap-6">
        <div className="flex flex-col gap-4">
          <div className="flex items-center gap-3">
            <BrandLogo side={64} />
            <div className="flex flex-col gap-1">
              <span className="font-section-title">Nomi</span>
              <span className="font-secondary text-[var(--text-2)]">{tr("本机讲座笔记")}</span>
            </div>
          </div>
          <div className="font-secondary text-[var(--text-2)]">{tr("识别和翻译在本机运行。提问和摘要可选择本地模型或 API。")}</div>
        </div>
        <div className="surface overflow-hidden">
          <div className="font-section-title flex items-center gap-2 px-4 py-3.5">
            <Icon name="questionmark.circle" size={17} />
            {tr("帮助")}
          </div>
          {divider}
          <Row title={tr("开始快速教程")} detail={tr("用几步认识主要按钮。")} onClick={() => m.startTutorial()} />
          {divider}
          <Row title={tr("设置向导")} detail={tr("下载语音识别和翻译模型，允许麦克风，绑定大模型 API。")} onClick={() => m.set("onboardingPresented", true)} />
          {divider}
          <Row title={tr("联系我们")} detail={contactEmail} onClick={async () => void shell.mail(contactEmail, tr("Nomi 反馈"), await mailBody())} />
        </div>
        {u.isAvailable && (
          <SettingsSection title={tr("更新")}>
            <SettingsRow title={tr("当前版本")}>
              <span className="font-secondary tabular-nums text-[var(--text-2)]">{u.version}</span>
            </SettingsRow>
            <SettingsRow title={tr("自动检查更新")} detail={tr("每天检查一次，有新版本时会提示你安装。")}>
              <Switch
                label={tr("自动检查更新")}
                on={auto}
                onChange={(v) => {
                  u.automaticallyChecks = v;
                  setAuto(v);
                }}
              />
            </SettingsRow>
            <SettingsRow title={tr("检查更新")} detail={u.available ? `${tr("有新版本")} ${u.available.version}` : u.lastResult === "upToDate" ? tr("已是最新版本") : u.lastResult === "failed" ? tr("检查失败，请稍后再试。") : undefined}>
              {u.available ? <PushButton prominent title={tr("下载更新")} onClick={() => u.install()} /> : <PushButton title={tr("立即检查")} disabled={!u.canCheck} onClick={() => void u.checkForUpdates()} />}
            </SettingsRow>
          </SettingsSection>
        )}
      </div>
    </NarrowPage>
  );
}
