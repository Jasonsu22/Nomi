// The lecture languages the Mac app offers (Support/Languages.swift), with their names.
import type { Lang } from "./i18n";

const names: Record<string, [string, string]> = {
  auto: ["自动", "Auto"],
  zh: ["中文", "Chinese"],
  en: ["英文", "English"],
  ja: ["日文", "Japanese"],
  ko: ["韩文", "Korean"],
  de: ["德文", "German"],
  fr: ["法文", "French"],
  es: ["西班牙文", "Spanish"],
  ru: ["俄文", "Russian"],
  ar: ["阿拉伯文", "Arabic"],
  none: ["不翻译", "No translation"],
};

const supported = ["zh", "en", "ja", "ko", "de", "fr", "es", "ru", "ar"];

export function sourceOptions(lang: Lang) {
  return ["auto", ...supported].map((code) => ({ value: code, label: names[code][lang === "zh" ? 0 : 1] }));
}

export function targetOptions(lang: Lang) {
  return [...supported, "none"].map((code) => ({ value: code, label: names[code][lang === "zh" ? 0 : 1] }));
}
