import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// Settings: models and where they run, live text, speakers, language, folders.
import { FolderOpen } from "lucide-react";
import { useEffect, useState } from "react";
import { DotLoader } from "../components/DotLoader";
import { ModelRow } from "../components/ModelRow";
import { Button, Card, Scroll, Segmented, Select, Toggle } from "../components/ui";
import { api } from "../lib/api";
import { useT } from "../lib/i18n";
import { useApp } from "../store";
function Section({ title, children }) {
    return (_jsxs("section", { className: "enter", children: [_jsx("h2", { className: "mb-2 px-1 text-[13px] font-semibold text-[var(--text-2)]", children: title }), _jsx(Card, { className: "space-y-1 p-2", children: children })] }));
}
function Row({ title, detail, children }) {
    return (_jsxs("div", { className: "flex items-center gap-4 px-3 py-2.5", children: [_jsxs("div", { className: "min-w-0 flex-1", children: [_jsx("div", { className: "text-[14px] font-medium", children: title }), detail && _jsx("div", { className: "text-[12px] leading-snug text-[var(--text-2)]", children: detail })] }), children] }));
}
export function SettingsPage() {
    const t = useT();
    const overview = useApp((s) => s.overview);
    const engine = useApp((s) => s.engine);
    const saveSettings = useApp((s) => s.saveSettings);
    const [device, setDevice] = useState(null);
    const [pending, setPending] = useState({});
    useEffect(() => {
        void api.deviceReport().then(setDevice);
    }, []);
    if (!overview)
        return null;
    const settings = { ...overview.settings, ...pending };
    const engineChange = (change) => setPending({ ...pending, ...change });
    const dirty = Object.keys(pending).length > 0;
    const apply = async () => {
        await saveSettings(pending);
        setPending({});
        if (engine.state !== "ready")
            void api.startEngine();
    };
    const placement = [
        { value: "auto", label: t("自动（有显卡用显卡）") },
        { value: "cpu", label: t("处理器上") },
        ...(device?.gpus ?? []).map((g, i) => ({ value: `gpu:${i}`, label: `${t("显卡上")}: ${g.description}` })),
    ];
    const role = (r) => overview.models.filter((m) => m.role === r);
    return (_jsx(Scroll, { className: "flex-1", children: _jsxs("div", { className: "mx-auto max-w-[760px] space-y-6 p-6", children: [_jsx("h1", { className: "px-1 text-[22px] font-semibold", children: t("设置") }), _jsxs(Section, { title: t("识别模型"), children: [role("asr").map((m) => (_jsx(ModelRow, { model: m, chosen: settings.asrModel === m.id, onChoose: () => engineChange({ asrModel: m.id }), deletable: overview.settings.asrModel !== m.id }, m.id))), _jsx(Row, { title: t("运行位置"), children: _jsx(Select, { value: settings.asrDevice, onChange: (v) => engineChange({ asrDevice: v }), options: placement, className: "max-w-[300px]" }) })] }), _jsxs(Section, { title: t("翻译模型"), children: [role("llm").map((m) => (_jsx(ModelRow, { model: m, chosen: settings.llmModel === m.id, onChoose: () => engineChange({ llmModel: m.id }), deletable: overview.settings.llmModel !== m.id }, m.id))), _jsx(Row, { title: t("运行位置"), children: _jsx(Select, { value: settings.llmDevice, onChange: (v) => engineChange({ llmDevice: v }), options: placement, className: "max-w-[300px]" }) })] }), _jsxs(Section, { title: t("实时字幕"), children: [_jsx(Row, { title: t("实时字幕"), detail: t("灰色的正在说的那句多久更新一次。电脑慢时选“忙时跳过”或“只显示整句”。"), children: _jsx(Select, { value: settings.interim, onChange: (v) => engineChange({ interim: v }), options: [
                                    { value: "skip-busy", label: t("忙时跳过（推荐）") },
                                    { value: "all", label: t("每次都更新") },
                                    { value: "off", label: t("只显示整句") },
                                ] }) }), _jsx(Row, { title: t("处理器线程"), detail: t("0 表示自动"), children: _jsx("input", { type: "number", min: 0, max: 64, value: settings.threads, onChange: (e) => engineChange({ threads: Math.max(0, Number(e.target.value) || 0) }), className: "glass h-9 w-20 rounded-[12px] px-3 text-sm outline-none" }) })] }), _jsx("div", { className: `sticky bottom-3 z-20 flex items-center justify-end gap-3 transition-all duration-[var(--t-page)] ${dirty ? "opacity-100" : "pointer-events-none translate-y-3 opacity-0"}`, children: _jsxs(Card, { strong: true, className: "flex items-center gap-3 px-4 py-2", children: [_jsx("span", { className: "text-[13px] text-[var(--text-2)]", children: t("更改模型后会重新加载") }), _jsx(Button, { size: "sm", onClick: () => setPending({}), children: t("取消") }), _jsx(Button, { size: "sm", tone: "primary", onClick: () => void apply(), children: t("应用") })] }) }), engine.state === "starting" && (_jsxs("div", { className: "flex items-center gap-3 px-1 text-[13px] text-[var(--text-2)]", children: [_jsx(DotLoader, { style: "circle", height: 16 }), t("模型正在加载")] })), _jsxs(Section, { title: t("说话人"), children: [_jsx(Row, { title: t("实时标出说话人"), detail: t("录音时分出不同的人，大约晚 5 秒标出。"), children: _jsx(Toggle, { on: settings.liveSpeakers, onChange: (on) => void saveSettings({ liveSpeakers: on }) }) }), role("speakers").map((m) => (_jsx(ModelRow, { model: { ...m, name: m.id === "standard" ? t("标准（最快）") : t("中英文（CAM++）") }, chosen: settings.speakerModel === m.id, onChoose: () => void saveSettings({ speakerModel: m.id }), deletable: overview.settings.speakerModel !== m.id }, m.id)))] }), _jsx(Section, { title: t("语言"), children: _jsx(Row, { title: t("界面语言"), children: _jsx(Segmented, { value: settings.uiLanguage || "system", onChange: (v) => void saveSettings({ uiLanguage: v === "system" ? "" : v }), options: [
                                { value: "system", label: t("跟随系统") },
                                { value: "zh", label: "中文" },
                                { value: "en", label: "English" },
                            ] }) }) }), _jsxs(Section, { title: t("关于"), children: [_jsx(Row, { title: t("Nomi Windows 版 0.1 测试版"), detail: device ? `${device.cpu} · ${Math.round(device.memoryGb)} GB · ${device.os}` : undefined, children: _jsx("span", {}) }), _jsx(Row, { title: t("数据文件夹"), detail: overview.dataFolder, children: _jsxs(Button, { size: "sm", onClick: () => void api.openFolder(overview.dataFolder), children: [_jsx(FolderOpen, { size: 14 }), t("打开")] }) }), _jsx(Row, { title: t("模型文件夹"), detail: overview.modelsFolder, children: _jsxs(Button, { size: "sm", onClick: () => void api.openFolder(overview.modelsFolder), children: [_jsx(FolderOpen, { size: 14 }), t("打开")] }) })] })] }) }));
}
