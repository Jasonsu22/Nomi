// Record: choose the input and languages, start, and watch the text and translation arrive.
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import { FileAudio, Mic, Square } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { DotLoader } from "../components/DotLoader";
import { Transcript } from "../components/Transcript";
import { Button, Card, Label, Segmented, Select } from "../components/ui";
import { api, type InputDevice } from "../lib/api";
import { clock } from "../lib/format";
import { useT } from "../lib/i18n";
import { sourceOptions, targetOptions } from "../lib/languages";
import { useApp } from "../store";

function LevelMeter() {
  const level = useApp((s) => s.level);
  // rms to a 0…1 bar on a decibel scale: -60 dB is empty, -12 dB is full.
  const db = 20 * Math.log10(Math.max(level, 1e-6));
  const value = Math.max(0, Math.min(1, (db + 60) / 48));
  return (
    <div className="flex h-5 items-center gap-[3px]" aria-label="level">
      {Array.from({ length: 12 }, (_, i) => (
        <span
          key={i}
          className="w-[3px] rounded-full transition-[transform,opacity] duration-100"
          style={{
            height: 18,
            background: "var(--leaf)",
            transform: `scaleY(${value * 12 > i ? 0.35 + 0.65 * Math.sin(((i + 1) / 12) * Math.PI) : 0.2})`,
            opacity: value * 12 > i ? 1 : 0.35,
          }}
        />
      ))}
    </div>
  );
}

function Elapsed({ seconds, running }: { seconds: number; running: boolean }) {
  const base = useRef({ at: Date.now(), seconds });
  const [, tick] = useState(0);
  useEffect(() => {
    base.current = { at: Date.now(), seconds };
  }, [seconds]);
  useEffect(() => {
    if (!running) return;
    const id = window.setInterval(() => tick((n) => n + 1), 500);
    return () => window.clearInterval(id);
  }, [running]);
  const now = running ? base.current.seconds + (Date.now() - base.current.at) / 1000 : seconds;
  return <span className="tabular-nums">{clock(now)}</span>;
}

function EngineGate({ children }: { children: React.ReactNode }) {
  const t = useT();
  const engine = useApp((s) => s.engine);
  const overview = useApp((s) => s.overview);
  const go = useApp((s) => s.go);
  if (overview && !overview.engineFound) {
    return <Card className="enter max-w-md p-6 text-sm text-[var(--text-2)]">{t("找不到引擎文件。开发时请先运行 Windows/scripts/build-engine。")}</Card>;
  }
  if (engine.state === "starting" || engine.state === "") {
    return (
      <div className="enter flex flex-col items-center gap-4 text-center">
        <DotLoader style="circle" height={28} />
        <div className="text-[15px] font-medium">{t("模型正在加载")}</div>
        <div className="text-[13px] text-[var(--text-2)]">{t("第一次在显卡上运行会慢一些")}</div>
      </div>
    );
  }
  if (engine.state === "failed") {
    return (
      <Card className="enter max-w-lg space-y-3 p-6">
        <div className="text-[15px] font-semibold">{t("模型加载失败")}</div>
        <div className="selectable max-h-40 overflow-auto text-[12.5px] whitespace-pre-wrap text-[var(--text-2)]">{engine.message}</div>
        <div className="flex gap-2">
          <Button tone="primary" onClick={() => void api.startEngine()}>{t("重试")}</Button>
          <Button onClick={() => go("settings")}>{t("设置")}</Button>
        </div>
      </Card>
    );
  }
  return <>{children}</>;
}

function StartForm() {
  const t = useT();
  const lang = useApp((s) => s.lang);
  const settings = useApp((s) => s.overview?.settings);
  const saveSettings = useApp((s) => s.saveSettings);
  const [title, setTitle] = useState("");
  const [input, setInput] = useState<"microphone" | "file">("microphone");
  const [file, setFile] = useState<string | null>(null);
  const [devices, setDevices] = useState<InputDevice[]>([]);
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    void api.inputDevices().then(setDevices);
  }, []);
  if (!settings) return null;

  const start = async () => {
    setStarting(true);
    setError(null);
    try {
      await api.startRecording({
        title,
        input,
        device: settings.inputDevice,
        file,
        sourceLanguage: settings.sourceLanguage,
        targetLanguage: settings.targetLanguage,
      });
    } catch (e) {
      setError(String(e));
    } finally {
      setStarting(false);
    }
  };

  const chooseFile = async () => {
    const picked = await openDialog({ multiple: false, filters: [{ name: "Audio", extensions: ["wav", "mp3", "m4a", "aac", "flac", "ogg"] }] });
    if (typeof picked === "string") setFile(picked);
  };

  return (
    <Card strong className="enter w-[min(560px,92%)] space-y-5 p-7">
      <div>
        <Label>{t("标题")}</Label>
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder={t("例如：自然语言处理 第 8 讲")}
          className="glass h-11 w-full rounded-[12px] px-3.5 text-[15px] outline-none placeholder:text-[var(--text-2)]/70"
        />
      </div>
      <div className="grid grid-cols-2 gap-4">
        <div>
          <Label>{t("说话语言")}</Label>
          <Select className="w-full" value={settings.sourceLanguage} onChange={(v) => void saveSettings({ sourceLanguage: v })} options={sourceOptions(lang)} />
        </div>
        <div>
          <Label>{t("翻译成")}</Label>
          <Select className="w-full" value={settings.targetLanguage} onChange={(v) => void saveSettings({ targetLanguage: v })} options={targetOptions(lang)} />
        </div>
      </div>
      <div>
        <Label>{t("输入")}</Label>
        <div className="flex flex-wrap items-center gap-3">
          <Segmented
            value={input}
            onChange={setInput}
            options={[
              { value: "microphone", label: t("麦克风") },
              { value: "file", label: t("音频文件") },
            ]}
          />
          {input === "microphone" ? (
            <Select
              className="min-w-0 flex-1"
              value={settings.inputDevice}
              onChange={(v) => void saveSettings({ inputDevice: v })}
              options={[{ value: "", label: t("系统默认") }, ...devices.map((d) => ({ value: d.name, label: d.name }))]}
            />
          ) : (
            <Button className="min-w-0 flex-1 justify-start" onClick={() => void chooseFile()}>
              <FileAudio size={16} />
              <span className="truncate">{file ? file.split(/[\\/]/).pop() : t("选择文件…")}</span>
            </Button>
          )}
        </div>
        {input === "file" && <div className="mt-2 text-[12px] text-[var(--text-2)]">{t("像现场一样播放文件，用来测试")}</div>}
      </div>
      {error && <div className="selectable text-[13px] text-[var(--danger)]">{error}</div>}
      <Button tone="primary" size="lg" className="w-full" disabled={starting || (input === "file" && !file)} onClick={() => void start()}>
        {starting ? <DotLoader style="hop" height={14} /> : <Mic size={18} />}
        {t("开始录音")}
      </Button>
    </Card>
  );
}

export function LivePage() {
  const t = useT();
  const live = useApp((s) => s.live);
  const settings = useApp((s) => s.overview?.settings);
  const notice = useApp((s) => s.notice);
  const clearNotice = useApp((s) => s.clearNotice);
  const open = useApp((s) => s.open);
  const [stopping, setStopping] = useState(false);
  const running = !!live && live.state !== "done";

  const stop = async () => {
    setStopping(true);
    try {
      const id = await api.stopRecording();
      useApp.setState({ live: null });
      open(id);
    } finally {
      setStopping(false);
    }
  };

  if (!running) {
    return (
      <div className="flex flex-1 items-center justify-center p-6">
        <EngineGate>
          <StartForm />
        </EngineGate>
      </div>
    );
  }

  const status = live.state === "stopping" ? t("正在停止") : live.state === "saving" ? t("正在保存") : t("正在聆听");
  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <header className="glass m-2 flex items-center gap-4 rounded-[18px] px-4 py-2.5">
        <span className="relative flex h-3 w-3">
          <span className="absolute inset-0 animate-ping rounded-full bg-[#e5484d] opacity-60" />
          <span className="relative h-3 w-3 rounded-full bg-[#e5484d]" />
        </span>
        <div className="min-w-0 flex-1">
          <div className="truncate text-[15px] font-semibold">{live.title}</div>
          <div className="flex items-center gap-2 text-[12px] text-[var(--text-2)]">
            <Elapsed seconds={live.elapsed} running={live.state === "listening"} />
            <span>·</span>
            <span className="truncate">{live.inputName}</span>
            <span>·</span>
            <span>{status}</span>
            {live.speakersOn && (
              <>
                <span>·</span>
                <span>{t("说话人正在识别")}</span>
              </>
            )}
          </div>
        </div>
        <LevelMeter />
        <Button tone="danger" disabled={stopping || live.state !== "listening"} onClick={() => void stop()}>
          {stopping ? <DotLoader style="breeze" height={14} /> : <Square size={14} fill="currentColor" />}
          {stopping ? t("正在停止") : t("停止")}
        </Button>
      </header>
      {notice && (
        <button onClick={clearNotice} className="enter glass mx-2 mb-1 rounded-[12px] px-4 py-2 text-left text-[12.5px] text-[var(--danger)]">
          {notice.message}
        </button>
      )}
      <Card className="m-2 mt-0 flex min-h-0 flex-1 flex-col overflow-hidden">
        <Transcript
          live
          paragraphs={live.paragraphs}
          sourceLanguage={settings?.sourceLanguage ?? "auto"}
          targetLanguage={settings?.targetLanguage ?? "en"}
          names={live.speakerNames}
          empty={
            <div className="flex h-60 flex-col items-center justify-center gap-3 text-[13px] text-[var(--text-2)]">
              <DotLoader style="breeze" height={20} />
              {t("正在聆听")}
            </div>
          }
        />
      </Card>
    </div>
  );
}
