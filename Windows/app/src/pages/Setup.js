import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// First start: what this PC has, which set of models suits it, and the downloads.
import { Cpu, Gauge, MemoryStick } from "lucide-react";
import { useEffect, useState } from "react";
import leaf from "../assets/leaf.svg";
import { DotLoader } from "../components/DotLoader";
import { ModelRow } from "../components/ModelRow";
import { Button, Card, Scroll, Toggle } from "../components/ui";
import { api } from "../lib/api";
import { bytes } from "../lib/format";
import { useT } from "../lib/i18n";
import { useApp } from "../store";
const SETS = {
    Lite: { asr: "qwen3-asr-0.6b", llm: "qwen3.5-0.8b", title: "轻量", detail: "适合 8 GB 内存、没有显卡的电脑", devices: { asrDevice: "auto", llmDevice: "cpu" } },
    Standard: { asr: "qwen3-asr-0.6b", llm: "qwen3.5-2b", title: "标准", detail: "适合 16 GB 内存的电脑，只用处理器也够快", devices: { asrDevice: "auto", llmDevice: "cpu" } },
    Full: { asr: "qwen3-asr-1.7b", llm: "qwen3.5-2b", title: "完整", detail: "适合有独立显卡的电脑，识别最准", devices: { asrDevice: "auto", llmDevice: "auto" } },
};
export function SetupPage() {
    const t = useT();
    const overview = useApp((s) => s.overview);
    const saveSettings = useApp((s) => s.saveSettings);
    const go = useApp((s) => s.go);
    const [device, setDevice] = useState(null);
    const [chosen, setChosen] = useState("Standard");
    const [speakers, setSpeakers] = useState(true);
    const [starting, setStarting] = useState(false);
    useEffect(() => {
        void api.deviceReport().then((report) => {
            setDevice(report);
            setChosen(report.suggestedSet);
        });
    }, []);
    if (!overview)
        return null;
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
    return (_jsx("div", { className: "flex h-full items-center justify-center p-6", children: _jsx(Card, { strong: true, className: "enter flex max-h-full w-[min(760px,96%)] flex-col overflow-hidden", children: _jsxs(Scroll, { className: "space-y-6 p-8", children: [_jsxs("div", { className: "flex items-center gap-4", children: [_jsx("img", { src: leaf, className: "h-12 w-12", alt: "" }), _jsxs("div", { children: [_jsx("h1", { className: "text-[22px] font-semibold", children: t("欢迎使用 Nomi") }), _jsx("p", { className: "text-[13.5px] text-[var(--text-2)]", children: t("Nomi 在这台电脑上把课堂实时转成文字并翻译，录音不会离开电脑。") })] })] }), _jsxs("section", { children: [_jsx("h2", { className: "mb-2 text-[13px] font-semibold text-[var(--text-2)]", children: t("这台电脑") }), device ? (_jsxs("div", { className: "fade-in grid grid-cols-3 gap-2", children: [_jsxs(Card, { className: "p-3", children: [_jsxs("div", { className: "flex items-center gap-1.5 text-[12px] text-[var(--text-2)]", children: [_jsx(Cpu, { size: 13 }), t("处理器")] }), _jsx("div", { className: "mt-1 truncate text-[13.5px] font-medium", title: device.cpu, children: device.cpu || "—" }), _jsx("div", { className: "text-[12px] text-[var(--text-2)]", children: t("%d 核 · %d 线程", device.cores, device.threads) })] }), _jsxs(Card, { className: "p-3", children: [_jsxs("div", { className: "flex items-center gap-1.5 text-[12px] text-[var(--text-2)]", children: [_jsx(MemoryStick, { size: 13 }), t("内存")] }), _jsxs("div", { className: "mt-1 text-[13.5px] font-medium", children: [Math.round(device.memoryGb), " GB"] }), _jsx("div", { className: "truncate text-[12px] text-[var(--text-2)]", children: device.os })] }), _jsxs(Card, { className: "p-3", children: [_jsxs("div", { className: "flex items-center gap-1.5 text-[12px] text-[var(--text-2)]", children: [_jsx(Gauge, { size: 13 }), t("显卡")] }), device.gpus.length === 0 ? (_jsx("div", { className: "mt-1 text-[13.5px] font-medium", children: t("没有可用的显卡") })) : (device.gpus.slice(0, 2).map((g) => (_jsxs("div", { className: "mt-1 truncate text-[13px] font-medium", title: g.description, children: [g.description, " ", _jsxs("span", { className: "text-[12px] font-normal text-[var(--text-2)]", children: ["(", g.kind === "igpu" ? t("集成") : t("独立"), ")"] })] }, g.index))))] })] })) : (_jsx("div", { className: "flex h-[86px] items-center justify-center", children: _jsx(DotLoader, { style: "gather", height: 20 }) }))] }), _jsxs("section", { children: [_jsx("h2", { className: "mb-2 text-[13px] font-semibold text-[var(--text-2)]", children: device ? t("推荐：%@", t(SETS[device.suggestedSet].title)) : t("模型") }), _jsx("div", { className: "grid grid-cols-3 gap-2", children: Object.keys(SETS).map((name) => {
                                    const s = SETS[name];
                                    const size = overview.models.filter((m) => m.id === s.asr || m.id === s.llm).reduce((a, m) => a + m.size, 0);
                                    const active = chosen === name;
                                    return (_jsxs("button", { onClick: () => setChosen(name), className: `press sheen rounded-[16px] p-3.5 text-left transition-all duration-[var(--t-layout)] ease-[var(--ease)] ${active ? "bg-[var(--selection)] text-[var(--on-selection)] shadow-[0_0_0_2px_var(--leaf)]" : "glass hover:bg-[var(--glass-strong)]"}`, children: [_jsxs("div", { className: "flex items-center justify-between", children: [_jsx("span", { className: "text-[15px] font-semibold", children: t(s.title) }), _jsx("span", { className: "text-[12px] opacity-75", children: bytes(size) })] }), _jsx("div", { className: "mt-1 text-[12px] leading-snug opacity-80", children: t(s.detail) })] }, name));
                                }) })] }), _jsxs("section", { className: "space-y-1", children: [models.map((m) => (_jsx(ModelRow, { model: m, deletable: false }, m.id))), _jsxs("div", { className: "flex items-center gap-3 px-3.5 py-2", children: [_jsxs("div", { className: "flex-1", children: [_jsx("div", { className: "text-[14px] font-medium", children: t("实时标出说话人") }), _jsx("div", { className: "text-[12px] text-[var(--text-2)]", children: t("录音时分出不同的人，大约晚 5 秒标出。") })] }), _jsx(Toggle, { on: speakers, onChange: setSpeakers })] })] }), _jsxs("div", { className: "flex justify-end gap-2", children: [missing.length > 0 && (_jsx(Button, { onClick: () => missing.forEach((m) => void api.downloadModel(m.id).then(() => useApp.getState().refresh())), children: t("全部下载") })), _jsx(Button, { tone: "primary", disabled: missing.length > 0 || starting, onClick: () => void finish(), children: t("开始使用") })] })] }) }) }));
}
