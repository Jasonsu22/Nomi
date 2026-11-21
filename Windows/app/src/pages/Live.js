import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
// Record: choose the input and languages, start, and watch the text and translation arrive.
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import { FileAudio, Mic, Square } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { DotLoader } from "../components/DotLoader";
import { Transcript } from "../components/Transcript";
import { Button, Card, Label, Segmented, Select } from "../components/ui";
import { api } from "../lib/api";
import { clock } from "../lib/format";
import { useT } from "../lib/i18n";
import { sourceOptions, targetOptions } from "../lib/languages";
import { useApp } from "../store";
function LevelMeter() {
    const level = useApp((s) => s.level);
    // rms to a 0…1 bar on a decibel scale: -60 dB is empty, -12 dB is full.
    const db = 20 * Math.log10(Math.max(level, 1e-6));
    const value = Math.max(0, Math.min(1, (db + 60) / 48));
    return (_jsx("div", { className: "flex h-5 items-center gap-[3px]", "aria-label": "level", children: Array.from({ length: 12 }, (_, i) => (_jsx("span", { className: "w-[3px] rounded-full transition-[transform,opacity] duration-100", style: {
                height: 18,
                background: "var(--leaf)",
                transform: `scaleY(${value * 12 > i ? 0.35 + 0.65 * Math.sin(((i + 1) / 12) * Math.PI) : 0.2})`,
                opacity: value * 12 > i ? 1 : 0.35,
            } }, i))) }));
}
function Elapsed({ seconds, running }) {
    const base = useRef({ at: Date.now(), seconds });
    const [, tick] = useState(0);
    useEffect(() => {
        base.current = { at: Date.now(), seconds };
    }, [seconds]);
    useEffect(() => {
        if (!running)
            return;
        const id = window.setInterval(() => tick((n) => n + 1), 500);
        return () => window.clearInterval(id);
    }, [running]);
    const now = running ? base.current.seconds + (Date.now() - base.current.at) / 1000 : seconds;
    return _jsx("span", { className: "tabular-nums", children: clock(now) });
}
function EngineGate({ children }) {
    const t = useT();
    const engine = useApp((s) => s.engine);
    const overview = useApp((s) => s.overview);
    const go = useApp((s) => s.go);
    if (overview && !overview.engineFound) {
        return _jsx(Card, { className: "enter max-w-md p-6 text-sm text-[var(--text-2)]", children: t("找不到引擎文件。开发时请先运行 Windows/scripts/build-engine。") });
    }
    if (engine.state === "starting" || engine.state === "") {
        return (_jsxs("div", { className: "enter flex flex-col items-center gap-4 text-center", children: [_jsx(DotLoader, { style: "circle", height: 28 }), _jsx("div", { className: "text-[15px] font-medium", children: t("模型正在加载") }), _jsx("div", { className: "text-[13px] text-[var(--text-2)]", children: t("第一次在显卡上运行会慢一些") })] }));
    }
    if (engine.state === "failed") {
        return (_jsxs(Card, { className: "enter max-w-lg space-y-3 p-6", children: [_jsx("div", { className: "text-[15px] font-semibold", children: t("模型加载失败") }), _jsx("div", { className: "selectable max-h-40 overflow-auto text-[12.5px] whitespace-pre-wrap text-[var(--text-2)]", children: engine.message }), _jsxs("div", { className: "flex gap-2", children: [_jsx(Button, { tone: "primary", onClick: () => void api.startEngine(), children: t("重试") }), _jsx(Button, { onClick: () => go("settings"), children: t("设置") })] })] }));
    }
    return _jsx(_Fragment, { children: children });
}
function StartForm() {
    const t = useT();
    const lang = useApp((s) => s.lang);
    const settings = useApp((s) => s.overview?.settings);
    const saveSettings = useApp((s) => s.saveSettings);
    const [title, setTitle] = useState("");
    const [input, setInput] = useState("microphone");
    const [file, setFile] = useState(null);
    const [devices, setDevices] = useState([]);
    const [starting, setStarting] = useState(false);
    const [error, setError] = useState(null);
    useEffect(() => {
        void api.inputDevices().then(setDevices);
    }, []);
    if (!settings)
        return null;
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
        }
        catch (e) {
            setError(String(e));
        }
        finally {
            setStarting(false);
        }
    };
    const chooseFile = async () => {
        const picked = await openDialog({ multiple: false, filters: [{ name: "Audio", extensions: ["wav", "mp3", "m4a", "aac", "flac", "ogg"] }] });
        if (typeof picked === "string")
            setFile(picked);
    };
    return (_jsxs(Card, { strong: true, className: "enter w-[min(560px,92%)] space-y-5 p-7", children: [_jsxs("div", { children: [_jsx(Label, { children: t("标题") }), _jsx("input", { value: title, onChange: (e) => setTitle(e.target.value), placeholder: t("例如：自然语言处理 第 8 讲"), className: "glass h-11 w-full rounded-[12px] px-3.5 text-[15px] outline-none placeholder:text-[var(--text-2)]/70" })] }), _jsxs("div", { className: "grid grid-cols-2 gap-4", children: [_jsxs("div", { children: [_jsx(Label, { children: t("说话语言") }), _jsx(Select, { className: "w-full", value: settings.sourceLanguage, onChange: (v) => void saveSettings({ sourceLanguage: v }), options: sourceOptions(lang) })] }), _jsxs("div", { children: [_jsx(Label, { children: t("翻译成") }), _jsx(Select, { className: "w-full", value: settings.targetLanguage, onChange: (v) => void saveSettings({ targetLanguage: v }), options: targetOptions(lang) })] })] }), _jsxs("div", { children: [_jsx(Label, { children: t("输入") }), _jsxs("div", { className: "flex flex-wrap items-center gap-3", children: [_jsx(Segmented, { value: input, onChange: setInput, options: [
                                    { value: "microphone", label: t("麦克风") },
                                    { value: "file", label: t("音频文件") },
                                ] }), input === "microphone" ? (_jsx(Select, { className: "min-w-0 flex-1", value: settings.inputDevice, onChange: (v) => void saveSettings({ inputDevice: v }), options: [{ value: "", label: t("系统默认") }, ...devices.map((d) => ({ value: d.name, label: d.name }))] })) : (_jsxs(Button, { className: "min-w-0 flex-1 justify-start", onClick: () => void chooseFile(), children: [_jsx(FileAudio, { size: 16 }), _jsx("span", { className: "truncate", children: file ? file.split(/[\\/]/).pop() : t("选择文件…") })] }))] }), input === "file" && _jsx("div", { className: "mt-2 text-[12px] text-[var(--text-2)]", children: t("像现场一样播放文件，用来测试") })] }), error && _jsx("div", { className: "selectable text-[13px] text-[var(--danger)]", children: error }), _jsxs(Button, { tone: "primary", size: "lg", className: "w-full", disabled: starting || (input === "file" && !file), onClick: () => void start(), children: [starting ? _jsx(DotLoader, { style: "hop", height: 14 }) : _jsx(Mic, { size: 18 }), t("开始录音")] })] }));
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
        }
        finally {
            setStopping(false);
        }
    };
    if (!running) {
        return (_jsx("div", { className: "flex flex-1 items-center justify-center p-6", children: _jsx(EngineGate, { children: _jsx(StartForm, {}) }) }));
    }
    const status = live.state === "stopping" ? t("正在停止") : live.state === "saving" ? t("正在保存") : t("正在聆听");
    return (_jsxs("div", { className: "flex min-h-0 flex-1 flex-col", children: [_jsxs("header", { className: "glass m-2 flex items-center gap-4 rounded-[18px] px-4 py-2.5", children: [_jsxs("span", { className: "relative flex h-3 w-3", children: [_jsx("span", { className: "absolute inset-0 animate-ping rounded-full bg-[#e5484d] opacity-60" }), _jsx("span", { className: "relative h-3 w-3 rounded-full bg-[#e5484d]" })] }), _jsxs("div", { className: "min-w-0 flex-1", children: [_jsx("div", { className: "truncate text-[15px] font-semibold", children: live.title }), _jsxs("div", { className: "flex items-center gap-2 text-[12px] text-[var(--text-2)]", children: [_jsx(Elapsed, { seconds: live.elapsed, running: live.state === "listening" }), _jsx("span", { children: "\u00B7" }), _jsx("span", { className: "truncate", children: live.inputName }), _jsx("span", { children: "\u00B7" }), _jsx("span", { children: status }), live.speakersOn && (_jsxs(_Fragment, { children: [_jsx("span", { children: "\u00B7" }), _jsx("span", { children: t("说话人正在识别") })] }))] })] }), _jsx(LevelMeter, {}), _jsxs(Button, { tone: "danger", disabled: stopping || live.state !== "listening", onClick: () => void stop(), children: [stopping ? _jsx(DotLoader, { style: "breeze", height: 14 }) : _jsx(Square, { size: 14, fill: "currentColor" }), stopping ? t("正在停止") : t("停止")] })] }), notice && (_jsx("button", { onClick: clearNotice, className: "enter glass mx-2 mb-1 rounded-[12px] px-4 py-2 text-left text-[12.5px] text-[var(--danger)]", children: notice.message })), _jsx(Card, { className: "m-2 mt-0 flex min-h-0 flex-1 flex-col overflow-hidden", children: _jsx(Transcript, { live: true, paragraphs: live.paragraphs, sourceLanguage: settings?.sourceLanguage ?? "auto", targetLanguage: settings?.targetLanguage ?? "en", names: live.speakerNames, empty: _jsxs("div", { className: "flex h-60 flex-col items-center justify-center gap-3 text-[13px] text-[var(--text-2)]", children: [_jsx(DotLoader, { style: "breeze", height: 20 }), t("正在聆听")] }) }) })] }));
}
