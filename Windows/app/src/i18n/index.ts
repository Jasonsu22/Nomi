// tr / trf, as on the Mac: Chinese strings are the keys; English comes from en.json, which is
// generated from the Mac's Resources/en.lproj/Localizable.strings.
import en from "./en.json";
import { prefs } from "../support/prefs";

const english = en as Record<string, string>;

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
  if (!isEnglish()) return key;
  return english[key] ?? key;
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
