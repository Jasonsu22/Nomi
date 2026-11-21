// Models/LocalModelLibrary.swift: which models are on this PC, and their downloads (done in Rust,
// from huggingface.co with hf-mirror.com as the fallback for mainland China).
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { tr } from "../i18n";
import { prefs } from "../support/prefs";
import { catalog, preferenceKey, type LocalModelDefinition, type LocalModelRole, type ModelDownloadProgress } from "../models/localModels";

type Progress = { id: string; received: number; total: number; state: "downloading" | "done" | "failed" | "cancelled"; message: string | null; bytesPerSecond: number };

export class LocalModelLibrary {
  installed = new Set<string>();
  downloads: Record<string, ModelDownloadProgress> = {};
  errors: Record<string, string> = {};
  switchingID: string | null = null;
  switchingRole: LocalModelRole | null = null;
  deletingID: string | null = null;
  onChange?: () => void;
  onInstalled?: (id: string) => void;

  async connect() {
    await listen<Progress>("download-progress", (e) => {
      const p = e.payload;
      if (p.state === "downloading") this.downloads = { ...this.downloads, [p.id]: { received: p.received, total: p.total, bytesPerSecond: p.bytesPerSecond } };
      else {
        const next = { ...this.downloads };
        delete next[p.id];
        this.downloads = next;
        if (p.state === "failed" && p.message) this.errors[p.id] = p.message;
        void this.refresh().then(() => {
          if (p.state === "done") this.onInstalled?.(p.id);
        });
      }
      this.onChange?.();
    });
    await this.refresh();
  }

  async refresh() {
    const ready = await invoke<string[]>("models_installed", { models: catalog.map((m) => ({ id: m.id, files: m.files })) }).catch(() => []);
    this.installed = new Set(ready);
    this.onChange?.();
  }

  refreshInBackground() {
    void this.refresh();
  }

  isDownloading(id: string) {
    return id in this.downloads;
  }

  download(model: LocalModelDefinition) {
    if (this.isDownloading(model.id) || this.installed.has(model.id)) return;
    delete this.errors[model.id];
    this.downloads = { ...this.downloads, [model.id]: { received: 0, total: model.files.reduce((n, f) => n + f.size, 0), bytesPerSecond: 0 } };
    this.onChange?.();
    invoke("model_download", { id: model.id, files: model.files }).catch((error) => {
      this.errors[model.id] = String(error);
      const next = { ...this.downloads };
      delete next[model.id];
      this.downloads = next;
      this.onChange?.();
    });
  }

  cancel(model: LocalModelDefinition) {
    void invoke("model_cancel_download", { id: model.id });
  }

  rememberSelection(model: LocalModelDefinition, role: LocalModelRole) {
    prefs.set(preferenceKey(role), model.id);
    this.onChange?.();
  }

  async trash(model: LocalModelDefinition) {
    if (this.isDownloading(model.id)) throw new Error(tr("模型正在下载，暂时无法删除。"));
    // Files another downloaded model also uses (the speaker segmentation model) stay.
    const keep = new Set(catalog.filter((m) => m.id !== model.id && this.installed.has(m.id)).flatMap((m) => m.files.map((f) => f.file)));
    await invoke("model_delete", { files: model.files.filter((f) => !keep.has(f.file)) });
    await this.refresh();
  }
}
