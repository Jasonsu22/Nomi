// tr / trf, as on the Mac: Chinese strings are the keys; English comes from en.json, which is
// generated from the Mac's Resources/en.lproj/Localizable.strings.
import en from "./en.json";
import windowsEn from "./windows-en.json";
import { prefs } from "../support/prefs";

const english = { ...(en as Record<string, string>), ...(windowsEn as Record<string, string>) };

/** The Mac's words for the PC: the strings are shared with the Mac app, so they are adjusted here. */
const pcWords: [RegExp, string][] = [
  [/这台 ?Mac/g, "这台电脑"],
  [/Mac 自带/g, "电脑自带"],
  [/~\/\.OminiX\/models/g, "%LOCALAPPDATA%\\Nomi\\models"],
  [/macOS/g, "Windows"],
  [/废纸篓/g, "回收站"],
  [/访达/g, "资源管理器"],
  [/⌘/g, "Ctrl+"],
  [/\bthe Mac's own\b/g, "the computer's own"],
  [/\bthe Mac's built-in\b/g, "the computer's built-in"],
  [/\bthis Mac\b/g, "this PC"],
  [/\bon your Mac\b/g, "on your PC"],
  [/\bthe Mac\b/g, "the PC"],
  [/\bFinder\b/g, "File Explorer"],
  [/\bthe Trash\b/g, "the Recycle Bin"],
  [/\bTrash\b/g, "Recycle Bin"],
];
const pcCache = new Map<string, string>();
function forPC(text: string): string {
  let hit = pcCache.get(text);
  if (hit === undefined) {
    hit = pcWords.reduce((t, [pattern, word]) => t.replace(pattern, word), text);
    pcCache.set(text, hit);
  }
  return hit;
}

export type InterfaceLanguage = "system" | "zh-Hans" | "en";
export const interfaceLanguageKey = "nomi.interfaceLanguage";

export function resolvedLanguage(choice = prefs.string(interfaceLanguageKey) ?? "system", preferred = navigator.language): "zh-Hans" | "en" {
  if (choice === "zh-Hans") return "zh-Hans";
  if (choice === "en") return "en";
  return preferred.toLowerCase().startsWith("zh") ? "zh-Hans" : "en";
}

export function isEnglish(): boolean {
  return resolvedLanguage() === "en";
}

export function tr(key: string): string {
  return forPC(isEnglish() ? (english[key] ?? key) : key);
}

/** printf-style formatting with %@, %d, %ld, %.1f, %%, and positional %1$@. */
export function format(template: string, args: (string | number)[]): string {
  let next = 0;
  return template.replace(/%(?:(\d+)\$)?(\.\d+)?(l{0,2})([@dfsu%])/g, (_m, pos: string | undefined, precision: string | undefined, _l, kind: string) => {
    if (kind === "%") return "%";
    const index = pos ? Number(pos) - 1 : next++;
    const value = args[index];
    if (value === undefined) return "";
    if (kind === "d" || kind === "u") return String(Math.trunc(Number(value)));
    if (kind === "f") return Number(value).toFixed(precision ? Number(precision.slice(1)) : 6);
    return String(value);
  });
}

export function trf(key: string, ...args: (string | number)[]): string {
  return format(tr(key), args);
}

export function locale(): string {
  return isEnglish() ? "en" : "zh-Hans";
}
