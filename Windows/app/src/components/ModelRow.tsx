// One model file set: its name and size, and Download, its progress, or Delete.
import { Check, Download, Trash2, X } from "lucide-react";
import { api, type ModelView } from "../lib/api";
import { bytes } from "../lib/format";
import { useT } from "../lib/i18n";
import { useApp } from "../store";
import { Button, Progress } from "./ui";

export function ModelRow({ model, chosen, onChoose, deletable = true }: { model: ModelView; chosen?: boolean; onChoose?: () => void; deletable?: boolean }) {
  const t = useT();
  const progress = useApp((s) => s.downloads[model.id]);
  const downloading = model.downloading || progress?.state === "downloading";
  const failed = progress?.state === "failed";
  return (
    <div
      className={`rounded-[14px] px-3.5 py-2.5 transition-colors duration-[var(--t-tap)] ${chosen ? "bg-[var(--selection)]/60" : ""} ${onChoose && model.ready ? "cursor-pointer hover:bg-[color-mix(in_srgb,var(--text)_5%,transparent)]" : ""}`}
      onClick={() => model.ready && onChoose?.()}
    >
      <div className="flex items-center gap-3">
        {onChoose && (
          <span className={`flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full border transition-colors ${chosen ? "border-[var(--leaf)] bg-[var(--leaf)] text-white" : "border-[var(--outline)]"}`}>
            {chosen && <Check size={12} strokeWidth={3} />}
          </span>
        )}
        <div className="min-w-0 flex-1">
          <div className="truncate text-[14px] font-medium">{model.name}</div>
          <div className="text-[12px] text-[var(--text-2)]">
            {bytes(model.size)}
            {model.ready && ` · ${t("已下载")}`}
            {downloading && progress && progress.bytesPerSecond > 0 && ` · ${bytes(progress.bytesPerSecond)}/s`}
          </div>
        </div>
        {model.ready ? (
          deletable && (
            <Button size="sm" tone="quiet" aria-label={t("删除")} onClick={(e) => { e.stopPropagation(); void api.deleteModel(model.id).then(() => useApp.getState().refresh()); }}>
              <Trash2 size={14} />
            </Button>
          )
        ) : downloading ? (
          <Button size="sm" tone="quiet" aria-label={t("取消")} onClick={(e) => { e.stopPropagation(); void api.cancelDownload(model.id); }}>
            <X size={14} />
          </Button>
        ) : (
          <Button size="sm" onClick={(e) => { e.stopPropagation(); void api.downloadModel(model.id).then(() => useApp.getState().refresh()); }}>
            <Download size={14} />
            {t("下载")}
          </Button>
        )}
      </div>
      {downloading && progress && (
        <div className="mt-2">
          <Progress value={progress.total ? progress.received / progress.total : 0} />
        </div>
      )}
      {failed && <div className="mt-1 text-[12px] text-[var(--danger)]">{t("下载失败：%@", progress.message ?? "")}</div>}
    </div>
  );
}
