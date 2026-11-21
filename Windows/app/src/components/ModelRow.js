import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// One model file set: its name and size, and Download, its progress, or Delete.
import { Check, Download, Trash2, X } from "lucide-react";
import { api } from "../lib/api";
import { bytes } from "../lib/format";
import { useT } from "../lib/i18n";
import { useApp } from "../store";
import { Button, Progress } from "./ui";
export function ModelRow({ model, chosen, onChoose, deletable = true }) {
    const t = useT();
    const progress = useApp((s) => s.downloads[model.id]);
    const downloading = model.downloading || progress?.state === "downloading";
    const failed = progress?.state === "failed";
    return (_jsxs("div", { className: `rounded-[14px] px-3.5 py-2.5 transition-colors duration-[var(--t-tap)] ${chosen ? "bg-[var(--selection)]/60" : ""} ${onChoose && model.ready ? "cursor-pointer hover:bg-[color-mix(in_srgb,var(--text)_5%,transparent)]" : ""}`, onClick: () => model.ready && onChoose?.(), children: [_jsxs("div", { className: "flex items-center gap-3", children: [onChoose && (_jsx("span", { className: `flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full border transition-colors ${chosen ? "border-[var(--leaf)] bg-[var(--leaf)] text-white" : "border-[var(--outline)]"}`, children: chosen && _jsx(Check, { size: 12, strokeWidth: 3 }) })), _jsxs("div", { className: "min-w-0 flex-1", children: [_jsx("div", { className: "truncate text-[14px] font-medium", children: model.name }), _jsxs("div", { className: "text-[12px] text-[var(--text-2)]", children: [bytes(model.size), model.ready && ` · ${t("已下载")}`, downloading && progress && progress.bytesPerSecond > 0 && ` · ${bytes(progress.bytesPerSecond)}/s`] })] }), model.ready ? (deletable && (_jsx(Button, { size: "sm", tone: "quiet", "aria-label": t("删除"), onClick: (e) => { e.stopPropagation(); void api.deleteModel(model.id).then(() => useApp.getState().refresh()); }, children: _jsx(Trash2, { size: 14 }) }))) : downloading ? (_jsx(Button, { size: "sm", tone: "quiet", "aria-label": t("取消"), onClick: (e) => { e.stopPropagation(); void api.cancelDownload(model.id); }, children: _jsx(X, { size: 14 }) })) : (_jsxs(Button, { size: "sm", onClick: (e) => { e.stopPropagation(); void api.downloadModel(model.id).then(() => useApp.getState().refresh()); }, children: [_jsx(Download, { size: 14 }), t("下载")] }))] }), downloading && progress && (_jsx("div", { className: "mt-2", children: _jsx(Progress, { value: progress.total ? progress.received / progress.total : 0 }) })), failed && _jsx("div", { className: "mt-1 text-[12px] text-[var(--danger)]", children: t("下载失败：%@", progress.message ?? "") })] }));
}
