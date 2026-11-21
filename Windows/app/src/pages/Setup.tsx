// First start: what this PC has, which set of models suits it, and the downloads.
import { Cpu, Gauge, MemoryStick } from "lucide-react";
import { useEffect, useState } from "react";
import leaf from "../assets/leaf.svg";
import { DotLoader } from "../components/DotLoader";
import { ModelRow } from "../components/ModelRow";
import { Button, Card, Scroll, Toggle } from "../components/ui";
import { api, type DeviceReport, type Settings } from "../lib/api";
import { bytes } from "../lib/format";
import { useT } from "../lib/i18n";
import { useApp } from "../store";

type SetName = "Lite" | "Standard" | "Full";

const SETS: Record<SetName, { asr: string; llm: string; detail: string; title: string; devices: Partial<Settings> }> = {
  Lite: { asr: "qwen3-asr-0.6b", llm: "qwen3.5-0.8b", title: "轻量", detail: "适合 8 GB 内存、没有显卡的电脑", devices: { asrDevice: "auto", llmDevice: "cpu" } },
  Standard: { asr: "qwen3-asr-0.6b", llm: "qwen3.5-2b", title: "标准", detail: "适合 16 GB 内存的电脑，只用处理器也够快", devices: { asrDevice: "auto", llmDevice: "cpu" } },
  Full: { asr: "qwen3-asr-1.7b", llm: "qwen3.5-2b", title: "完整", detail: "适合有独立显卡的电脑，识别最准", devices: { asrDevice: "auto", llmDevice: "auto" } },
};

export function SetupPage() {
  const t = useT();
  const overview = useApp((s) => s.overview);
  const saveSettings = useApp((s) => s.saveSettings);
  const go = useApp((s) => s.go);
  const [device, setDevice] = useState<DeviceReport | null>(null);
  const [chosen, setChosen] = useState<SetName>("Standard");
  const [speakers, setSpeakers] = useState(true);
  const [starting, setStarting] = useState(false);

  useEffect(() => {
    void api.deviceReport().then((report) => {
      setDevice(report);
      setChosen(report.suggestedSet);
    });
  }, []);

  if (!overview) return null;
  const set = SETS[chosen];
  const wanted = [set.asr, set.llm, ...(speakers ? ["standard"] : [])];
  const models = overview.models.filter((m) => wanted.includes(m.id));
  const missing = models.filter((m) => !m.ready);
  const finish = async () => {
    setStarting(true);
    await saveSettings({ setUp: true, asrModel: set.asr, llmModel: set.llm, liveSpeakers: speakers, speakerModel: "standard", ...set.devices });
    go("live");
    void api.startEngine();
  };

  return (
    <div className="flex h-full items-center justify-center p-6">
      <Card strong className="enter flex max-h-full w-[min(760px,96%)] flex-col overflow-hidden">
        <Scroll className="space-y-6 p-8">
          <div className="flex items-center gap-4">
            <img src={leaf} className="h-12 w-12" alt="" />
            <div>
              <h1 className="text-[22px] font-semibold">{t("欢迎使用 Nomi")}</h1>
              <p className="text-[13.5px] text-[var(--text-2)]">{t("Nomi 在这台电脑上把课堂实时转成文字并翻译，录音不会离开电脑。")}</p>
            </div>
          </div>

          <section>
            <h2 className="mb-2 text-[13px] font-semibold text-[var(--text-2)]">{t("这台电脑")}</h2>
            {device ? (
              <div className="fade-in grid grid-cols-3 gap-2">
                <Card className="p-3">
                  <div className="flex items-center gap-1.5 text-[12px] text-[var(--text-2)]"><Cpu size={13} />{t("处理器")}</div>
                  <div className="mt-1 truncate text-[13.5px] font-medium" title={device.cpu}>{device.cpu || "—"}</div>
                  <div className="text-[12px] text-[var(--text-2)]">{t("%d 核 · %d 线程", device.cores, device.threads)}</div>
                </Card>
                <Card className="p-3">
                  <div className="flex items-center gap-1.5 text-[12px] text-[var(--text-2)]"><MemoryStick size={13} />{t("内存")}</div>
                  <div className="mt-1 text-[13.5px] font-medium">{Math.round(device.memoryGb)} GB</div>
                  <div className="truncate text-[12px] text-[var(--text-2)]">{device.os}</div>
                </Card>
                <Card className="p-3">
                  <div className="flex items-center gap-1.5 text-[12px] text-[var(--text-2)]"><Gauge size={13} />{t("显卡")}</div>
                  {device.gpus.length === 0 ? (
                    <div className="mt-1 text-[13.5px] font-medium">{t("没有可用的显卡")}</div>
                  ) : (
                    device.gpus.slice(0, 2).map((g) => (
                      <div key={g.index} className="mt-1 truncate text-[13px] font-medium" title={g.description}>
                        {g.description} <span className="text-[12px] font-normal text-[var(--text-2)]">({g.kind === "igpu" ? t("集成") : t("独立")})</span>
                      </div>
                    ))
                  )}
                </Card>
              </div>
            ) : (
              <div className="flex h-[86px] items-center justify-center"><DotLoader style="gather" height={20} /></div>
            )}
          </section>

          <section>
            <h2 className="mb-2 text-[13px] font-semibold text-[var(--text-2)]">{device ? t("推荐：%@", t(SETS[device.suggestedSet].title)) : t("模型")}</h2>
            <div className="grid grid-cols-3 gap-2">
              {(Object.keys(SETS) as SetName[]).map((name) => {
                const s = SETS[name];
                const size = overview.models.filter((m) => m.id === s.asr || m.id === s.llm).reduce((a, m) => a + m.size, 0);
                const active = chosen === name;
                return (
                  <button
                    key={name}
                    onClick={() => setChosen(name)}
                    className={`press sheen rounded-[16px] p-3.5 text-left transition-all duration-[var(--t-layout)] ease-[var(--ease)] ${
                      active ? "bg-[var(--selection)] text-[var(--on-selection)] shadow-[0_0_0_2px_var(--leaf)]" : "glass hover:bg-[var(--glass-strong)]"
                    }`}
                  >
                    <div className="flex items-center justify-between">
                      <span className="text-[15px] font-semibold">{t(s.title)}</span>
                      <span className="text-[12px] opacity-75">{bytes(size)}</span>
                    </div>
                    <div className="mt-1 text-[12px] leading-snug opacity-80">{t(s.detail)}</div>
                  </button>
                );
              })}
            </div>
          </section>

          <section className="space-y-1">
            {models.map((m) => (
              <ModelRow key={m.id} model={m} deletable={false} />
            ))}
            <div className="flex items-center gap-3 px-3.5 py-2">
              <div className="flex-1">
                <div className="text-[14px] font-medium">{t("实时标出说话人")}</div>
                <div className="text-[12px] text-[var(--text-2)]">{t("录音时分出不同的人，大约晚 5 秒标出。")}</div>
              </div>
              <Toggle on={speakers} onChange={setSpeakers} />
            </div>
          </section>

          <div className="flex justify-end gap-2">
            {missing.length > 0 && (
              <Button onClick={() => missing.forEach((m) => void api.downloadModel(m.id).then(() => useApp.getState().refresh()))}>{t("全部下载")}</Button>
            )}
            <Button tone="primary" disabled={missing.length > 0 || starting} onClick={() => void finish()}>
              {t("开始使用")}
            </Button>
          </div>
        </Scroll>
      </Card>
    </div>
  );
}
