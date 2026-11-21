const names = {
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
export function sourceOptions(lang) {
    return ["auto", ...supported].map((code) => ({ value: code, label: names[code][lang === "zh" ? 0 : 1] }));
}
export function targetOptions(lang) {
    return [...supported, "none"].map((code) => ({ value: code, label: names[code][lang === "zh" ? 0 : 1] }));
}
