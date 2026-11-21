// Settings: models and where they run, live text, speakers, language, folders.
import { FolderOpen } from "lucide-react";
import { useEffect, useState } from "react";
import { DotLoader } from "../components/DotLoader";
import { ModelRow } from "../components/ModelRow";
import { Button, Card, Scroll, Segmented, Select, Toggle } from "../components/ui";
import { api, type DeviceReport, type Settings } from "../lib/api";
import { useT } from "../lib/i18n";
import { useApp } from "../store";

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="enter">
      <h2 className="mb-2 px-1 text-[13px] font-semibold text-[var(--text-2)]">{title}</h2>
      <Card className="space-y-1 p-2">{children}</Card>
    </section>
  );
}

function Row({ title, detail, children }: { title: string; detail?: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-4 px-3 py-2.5">
      <div className="min-w-0 flex-1">
        <div className="text-[14px] font-medium">{title}</div>
        {detail && <div className="text-[12px] leading-snug text-[var(--text-2)]">{detail}</div>}
      </div>
      {children}
    </div>
  );
}

export function SettingsPage() {
  const t = useT();
  const overview = useApp((s) => s.overview);
  const engine = useApp((s) => s.engine);
  const saveSettings = useApp((s) => s.saveSettings);
  const [device, setDevice] = useState<DeviceReport | null>(null);
  const [pending, setPending] = useState<Partial<Settings>>({});
  useEffect(() => {
    void api.deviceReport().then(setDevice);
  }, []);
  if (!overview) return null;
  const settings = { ...overview.settings, ...pending };
  const engineChange = (change: Partial<Settings>) => setPending({ ...pending, ...change });
  const dirty = Object.keys(pending).length > 0;
  const apply = async () => {
    await saveSettings(pending);
    setPending({});
    if (engine.state !== "ready") void api.startEngine();
  };

  const placement = [
    { value: "auto", label: t("自动（有显卡用显卡）") },
    { value: "cpu", label: t("处理器上") },
    ...(device?.gpus ?? []).map((g, i) => ({ value: `gpu:${i}`, label: `${t("显卡上")}: ${g.description}` })),
  ];
  const role = (r: string) => overview.models.filter((m) => m.role === r);

  return (
    <Scroll className="flex-1">
      <div className="mx-auto max-w-[760px] space-y-6 p-6">
        <h1 className="px-1 text-[22px] font-semibold">{t("设置")}</h1>

        <Section title={t("识别模型")}>
          {role("asr").map((m) => (
            <ModelRow key={m.id} model={m} chosen={settings.asrModel === m.id} onChoose={() => engineChange({ asrModel: m.id })} deletable={overview.settings.asrModel !== m.id} />
          ))}
          <Row title={t("运行位置")}>
            <Select value={settings.asrDevice} onChange={(v) => engineChange({ asrDevice: v })} options={placement} className="max-w-[300px]" />
          </Row>
        </Section>

        <Section title={t("翻译模型")}>
          {role("llm").map((m) => (
            <ModelRow key={m.id} model={m} chosen={settings.llmModel === m.id} onChoose={() => engineChange({ llmModel: m.id })} deletable={overview.settings.llmModel !== m.id} />
          ))}
          <Row title={t("运行位置")}>
            <Select value={settings.llmDevice} onChange={(v) => engineChange({ llmDevice: v })} options={placement} className="max-w-[300px]" />
          </Row>
        </Section>

        <Section title={t("实时字幕")}>
          <Row title={t("实时字幕")} detail={t("灰色的正在说的那句多久更新一次。电脑慢时选“忙时跳过”或“只显示整句”。")}>
            <Select
              value={settings.interim}
              onChange={(v) => engineChange({ interim: v as Settings["interim"] })}
              options={[
                { value: "skip-busy", label: t("忙时跳过（推荐）") },
                { value: "all", label: t("每次都更新") },
                { value: "off", label: t("只显示整句") },
              ]}
            />
          </Row>
          <Row title={t("处理器线程")} detail={t("0 表示自动")}>
            <input
              type="number"
              min={0}
              max={64}
              value={settings.threads}
              onChange={(e) => engineChange({ threads: Math.max(0, Number(e.target.value) || 0) })}
              className="glass h-9 w-20 rounded-[12px] px-3 text-sm outline-none"
            />
          </Row>
        </Section>

        <div
          className={`sticky bottom-3 z-20 flex items-center justify-end gap-3 transition-all duration-[var(--t-page)] ${dirty ? "opacity-100" : "pointer-events-none translate-y-3 opacity-0"}`}
        >
          <Card strong className="flex items-center gap-3 px-4 py-2">
            <span className="text-[13px] text-[var(--text-2)]">{t("更改模型后会重新加载")}</span>
            <Button size="sm" onClick={() => setPending({})}>{t("取消")}</Button>
            <Button size="sm" tone="primary" onClick={() => void apply()}>{t("应用")}</Button>
          </Card>
        </div>
        {engine.state === "starting" && (
          <div className="flex items-center gap-3 px-1 text-[13px] text-[var(--text-2)]">
            <DotLoader style="circle" height={16} />
            {t("模型正在加载")}
          </div>
        )}

        <Section title={t("说话人")}>
          <Row title={t("实时标出说话人")} detail={t("录音时分出不同的人，大约晚 5 秒标出。")}>
            <Toggle on={settings.liveSpeakers} onChange={(on) => void saveSettings({ liveSpeakers: on })} />
          </Row>
          {role("speakers").map((m) => (
            <ModelRow
              key={m.id}
              model={{ ...m, name: m.id === "standard" ? t("标准（最快）") : t("中英文（CAM++）") }}
              chosen={settings.speakerModel === m.id}
              onChoose={() => void saveSettings({ speakerModel: m.id })}
              deletable={overview.settings.speakerModel !== m.id}
            />
          ))}
        </Section>

        <Section title={t("语言")}>
          <Row title={t("界面语言")}>
            <Segmented
              value={settings.uiLanguage || "system"}
              onChange={(v) => void saveSettings({ uiLanguage: v === "system" ? "" : v })}
              options={[
                { value: "system", label: t("跟随系统") },
                { value: "zh", label: "中文" },
                { value: "en", label: "English" },
              ]}
            />
          </Row>
        </Section>

        <Section title={t("关于")}>
          <Row title={t("Nomi Windows 版 0.1 测试版")} detail={device ? `${device.cpu} · ${Math.round(device.memoryGb)} GB · ${device.os}` : undefined}>
            <span />
          </Row>
          <Row title={t("数据文件夹")} detail={overview.dataFolder}>
            <Button size="sm" onClick={() => void api.openFolder(overview.dataFolder)}><FolderOpen size={14} />{t("打开")}</Button>
          </Row>
          <Row title={t("模型文件夹")} detail={overview.modelsFolder}>
            <Button size="sm" onClick={() => void api.openFolder(overview.modelsFolder)}><FolderOpen size={14} />{t("打开")}</Button>
          </Row>
        </Section>
      </div>
    </Scroll>
  );
}
