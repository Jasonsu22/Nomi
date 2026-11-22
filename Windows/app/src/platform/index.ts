// Everything that touches the PC goes through here, to the Rust side (src-tauri/src/platform.rs).
// Paths are absolute; `paths.root` is Nomi's data folder (Windows: %LOCALAPPDATA%\Nomi).
import { invoke } from "@tauri-apps/api/core";
import { open as openDialog, save as saveDialog } from "@tauri-apps/plugin-dialog";

export type FileStat = { size: number; modified: number; isDir: boolean };

export const paths = {
  root: "",
  sep: "/",
  join(...parts: string[]) {
    return parts.filter(Boolean).join(this.sep).replace(/[\\/]+/g, this.sep);
  },
  name(path: string) {
    return path.split(/[\\/]/).pop() ?? path;
  },
  dir(path: string) {
    const i = Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\"));
    return i < 0 ? "" : path.slice(0, i);
  },
  ext(path: string) {
    const name = this.name(path);
    const dot = name.lastIndexOf(".");
    return dot < 0 ? "" : name.slice(dot + 1).toLowerCase();
  },
};

export async function initPlatform() {
  const info = await invoke<{ root: string; sep: string; os: string }>("platform_info");
  paths.root = info.root;
  paths.sep = info.sep;
  platformOS = info.os;
}

export let platformOS = "windows";

export const fs = {
  readText: (path: string) => invoke<string | null>("fs_read_text", { path }),
  writeText: (path: string, text: string) => invoke<void>("fs_write_text", { path, text }),
  readBase64: (path: string) => invoke<string>("fs_read_base64", { path }),
  writeBase64: (path: string, data: string) => invoke<void>("fs_write_base64", { path, data }),
  copy: (from: string, to: string) => invoke<void>("fs_copy", { from, to }),
  move: (from: string, to: string) => invoke<void>("fs_move", { from, to }),
  remove: (path: string) => invoke<void>("fs_remove", { path }),
  exists: (path: string) => invoke<boolean>("fs_exists", { path }),
  list: (path: string) => invoke<string[]>("fs_list", { path }),
  mkdir: (path: string) => invoke<void>("fs_mkdir", { path }),
  stat: (path: string) => invoke<FileStat | null>("fs_stat", { path }),
  tempDir: () => invoke<string>("fs_temp_dir"),
};

export const shell = {
  openURL: (url: string) => invoke<void>("open_url", { url }),
  openPath: (path: string) => invoke<void>("open_path", { path }),
  reveal: (path: string) => invoke<void>("reveal_path", { path }),
  mail: (to: string, subject: string, body: string) => invoke<void>("open_url", { url: `mailto:${to}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}` }),
};

export const secrets = {
  get: (service: string, account: string) => invoke<string | null>("secret_get", { service, account }),
  set: (service: string, account: string, secret: string) => invoke<void>("secret_set", { service, account, secret }),
  remove: (service: string, account: string) => invoke<void>("secret_delete", { service, account }),
};

export const images = {
  /** A model-ready copy: at most 2048 px on the long side, base64. */
  payload: (path: string, mime: string) => invoke<{ mime: string; base64: string } | null>("image_payload", { path, mime }),
  /** Checks an image and converts HEIC/TIFF to PNG. Returns the stored mime or null. */
  normalize: (path: string) => invoke<{ mime: string } | null>("image_normalize", { path }),
  thumbnail: (path: string, size: number) => invoke<string | null>("image_thumbnail", { path, size }),
};

/** Raw text pieces of a file, in order. TypeScript turns them into passages (models/sourceText.ts). */
export type TextSegment = {
  /** text: the whole document; page: a PDF page; slide; sheet (with name); chapter; picture (OCR of an embedded image). */
  kind: "text" | "page" | "slide" | "sheet" | "chapter" | "picture";
  index: number;
  name?: string | null;
  text: string;
};

export const documents = {
  segments: (path: string) => invoke<TextSegment[]>("document_segments", { path }),
  pageCount: (path: string) => invoke<number | null>("document_page_count", { path }),
  ocrAvailable: () => invoke<boolean>("ocr_available"),
};

export const dialogs = {
  openFiles: async (filters?: { name: string; extensions: string[] }[], multiple = true): Promise<string[]> => {
    const picked = await openDialog({ multiple, filters });
    if (!picked) return [];
    return Array.isArray(picked) ? picked : [picked];
  },
  openFolder: async (): Promise<string | null> => {
    const picked = await openDialog({ directory: true, multiple: false });
    return typeof picked === "string" ? picked : null;
  },
  save: async (defaultPath: string, filters?: { name: string; extensions: string[] }[]): Promise<string | null> => (await saveDialog({ defaultPath, filters })) ?? null,
};

/** What the window's close button does; unset means ask the first time. */
export type CloseAction = "minimize" | "quit";
export const closeActionKey = "nomi.closeAction";

export const app = {
  version: () => invoke<string>("app_version"),
  quit: () => invoke<void>("app_quit"),
  closeChoice: (choice: CloseAction) => invoke<void>("window_close_choice", { choice }),
  setCompact: (compact: boolean) => invoke<void>("window_set_compact", { compact }),
  diagnostics: () => invoke<string>("diagnostics"),
};

/** A URL the web view can load for a file on disk (Tauri's asset protocol). */
export { convertFileSrc as fileSrc } from "@tauri-apps/api/core";
