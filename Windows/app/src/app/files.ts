// The file actions behind the answer and picture menus (Models/AnswerFiles.swift AnswerLinkActions,
// ChatImageActions): save a copy, copy the contents, copy a picture.
import { invoke } from "@tauri-apps/api/core";
import { dialogs, fs, paths } from "../platform";
import { AppModel } from "./model";

declare module "./model" {
  interface AppModel {
    saveFileCopy(path: string, name?: string): Promise<void>;
    copyFileContents(path: string): Promise<void>;
    copyImage(path: string): Promise<void>;
  }
}

const P = AppModel.prototype;

P.saveFileCopy = async function (path, name) {
  const destination = await dialogs.save(name ?? paths.name(path));
  if (!destination || destination.toLowerCase() === path.toLowerCase()) return;
  try {
    await fs.copy(path, destination);
  } catch (e) {
    this.noteError("exportError", e);
  }
};

P.copyFileContents = async function (path) {
  try {
    await navigator.clipboard.writeText((await fs.readText(path)) ?? "");
  } catch (e) {
    this.noteError("exportError", e);
  }
};

P.copyImage = async function (path) {
  try {
    await invoke("clipboard_copy_image", { path });
  } catch (e) {
    this.noteError("exportError", e);
  }
};
