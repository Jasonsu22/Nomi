// Models/ChatImage.swift: pictures and files attached to a chat question.
import { tr } from "../i18n";
import { newID } from "../support/format";
import { fs, images, paths } from "../platform";
import { SourceText } from "./sourceText";

export type ChatImage = { id: string; name: string; mime: string; relativePath: string };
/** Before sending: a picture or file waiting in the composer. */
export type ChatImageDraft = { id: string; name: string; mime: string; fileURL: string };
export type ChatFileRef = { sourceID: string; name: string };
export type ModelImage = { mime: string; base64: string };

export const isDraftFile = (d: ChatImageDraft) => !d.mime.startsWith("image/");

export const ChatImages = {
  countLimit: 8,
  byteLimit: 10 * 1024 * 1024,
  fileByteLimit: 50 * 1024 * 1024,

  get root() {
    return paths.join(paths.root, "chat-images");
  },
  get temporaryRoot() {
    return paths.join(paths.root, "tmp", "nomi-chat-images");
  },

  fileURL(image: ChatImage) {
    return paths.join(this.root, image.relativePath);
  },

  seesImages(mode: "local" | "api", modelID: string): boolean {
    return mode === "api" && !modelID.toLowerCase().includes("minimax-m2");
  },

  mimeType(path: string): string | null {
    switch (paths.ext(path)) {
      case "jpg":
      case "jpeg":
        return "image/jpeg";
      case "png":
        return "image/png";
      case "gif":
        return "image/gif";
      case "webp":
        return "image/webp";
      case "heic":
      case "heif":
        return "image/heic";
      case "tif":
      case "tiff":
        return "image/tiff";
      default:
        return null;
    }
  },

  async intake(files: string[], existing: number): Promise<{ drafts: ChatImageDraft[]; notice: string | null }> {
    const drafts: ChatImageDraft[] = [];
    let notice: string | null = null;
    const note = (t: string) => {
      notice = notice ?? t;
    };
    let count = existing;
    for (const file of files) {
      if (count >= this.countLimit) {
        note(tr("一次最多 8 个图片或文件。"));
        break;
      }
      const mime = this.mimeType(file);
      const stat = await fs.stat(file);
      if (!stat) {
        note(tr("这个文件无法读取。"));
        continue;
      }
      if (stat.isDir) {
        note(tr("文件夹不能直接加入，请在资料页导入。"));
        continue;
      }
      if (!mime) {
        if (!SourceText.canRead(file)) {
          note(SourceText.refusal(file));
          continue;
        }
        if (stat.size > this.fileByteLimit) {
          note(tr("单个文件不能超过 50 MB。"));
          continue;
        }
        const id = newID();
        const destination = paths.join(this.temporaryRoot, id, paths.name(file));
        try {
          await fs.copy(file, destination);
        } catch {
          note(tr("这个文件无法读取。"));
          continue;
        }
        drafts.push({ id, name: paths.name(file), mime: "application/octet-stream", fileURL: destination });
        count++;
        continue;
      }
      if (stat.size > this.byteLimit) {
        note(tr("单张图片不能超过 10 MB。"));
        continue;
      }
      const draft = await this.storeFrom(file, paths.name(file), note);
      if (draft) {
        drafts.push(draft);
        count++;
      }
    }
    return { drafts, notice };
  },

  /** A pasted picture (from the clipboard), as base64. */
  async intakeBytes(base64: string, name: string, existing: number): Promise<{ drafts: ChatImageDraft[]; notice: string | null }> {
    if (existing >= this.countLimit) return { drafts: [], notice: tr("一次最多 8 个图片或文件。") };
    if ((base64.length * 3) / 4 > this.byteLimit) return { drafts: [], notice: tr("单张图片不能超过 10 MB。") };
    const id = newID();
    const temp = paths.join(this.temporaryRoot, id, name);
    await fs.writeBase64(temp, base64);
    let notice: string | null = null;
    const draft = await this.storeFrom(temp, name, (t) => (notice = t), id);
    return { drafts: draft ? [draft] : [], notice: draft ? null : notice ?? tr("这张图片无法读取。") };
  },

  async storeFrom(file: string, name: string, note: (t: string) => void, knownID?: string): Promise<ChatImageDraft | null> {
    const id = knownID ?? newID();
    const destination = paths.join(this.temporaryRoot, id, name);
    try {
      if (file !== destination) await fs.copy(file, destination);
      const checked = await images.normalize(destination);
      if (!checked) {
        note(tr("这张图片无法读取。"));
        return null;
      }
      const finalName = fileName(name, checked.mime);
      const finalPath = paths.join(this.temporaryRoot, id, finalName);
      if (finalPath !== destination) await fs.move(destination, finalPath).catch(() => {});
      return { id, name: finalName, mime: checked.mime, fileURL: finalPath };
    } catch {
      note(tr("这张图片无法读取。"));
      return null;
    }
  },

  async discard(draft: ChatImageDraft) {
    await fs.remove(paths.dir(draft.fileURL)).catch(() => {});
  },

  async removeTemporary() {
    await fs.remove(this.temporaryRoot).catch(() => {});
  },

  async promote(draft: ChatImageDraft): Promise<ChatImage | null> {
    const filename = fileName(draft.name, draft.mime);
    const destination = paths.join(this.root, draft.id, filename);
    try {
      await fs.move(draft.fileURL, destination);
      await fs.remove(paths.dir(draft.fileURL)).catch(() => {});
      return { id: draft.id, name: draft.name, mime: draft.mime, relativePath: `${draft.id}/${filename}` };
    } catch {
      return null;
    }
  },

  async delete(list: ChatImage[]) {
    for (const image of list) await fs.remove(paths.join(this.root, image.id)).catch(() => {});
  },

  payload(path: string, mime: string): Promise<ModelImage | null> {
    return images.payload(path, mime);
  },

  /** Pictures from the last four turns that still fit beside the new ones. */
  attachedImages(history: { id: string; images: ChatImage[] }[], currentCount: number, limit = 8): { history: ChatImage[]; omittedTurnIDs: Set<string>; mentionsOlderImages: boolean } {
    let room = Math.max(0, limit - Math.min(currentCount, limit));
    const chosen: ChatImage[] = [];
    const omitted = new Set<string>();
    for (const turn of history.slice(-4).reverse()) {
      if (!turn.images.length) continue;
      const before = chosen.length;
      for (const image of turn.images) {
        if (room <= 0) break;
        chosen.push(image);
        room--;
      }
      if (chosen.length === before) omitted.add(turn.id);
    }
    const older = history.slice(0, Math.max(0, history.length - 4)).some((t) => t.images.length);
    return { history: chosen, omittedTurnIDs: omitted, mentionsOlderImages: older };
  },
};

function fileName(original: string, mime: string): string {
  const leaf = paths.name(original);
  const cleaned = [...leaf].map((c) => (/[\p{L}\p{N}.\-_ ]/u.test(c) ? c : "-")).join("");
  const dot = cleaned.lastIndexOf(".");
  const stem = (dot < 0 ? cleaned : cleaned.slice(0, dot)).trim();
  const ext = mime === "image/jpeg" ? "jpg" : mime === "image/gif" ? "gif" : mime === "image/webp" ? "webp" : "png";
  if (!mime.startsWith("image/")) return leaf;
  return (stem || "image") + "." + ext;
}
