// Support/Languages.swift
import { prefs } from "./prefs";

export const LectureLanguages = {
  automatic: "auto",
  followSystem: "system",
  sourceKey: "nomi.sourceLanguage",
  targetKey: "nomi.targetLanguage",
  supported: ["zh", "en", "ja", "ko", "de", "fr", "es", "ru", "ar"],

  code(forPreferred: string): string {
    const n = forPreferred.toLowerCase().replace(/_/g, "-");
    for (const code of ["zh", "en", "ja", "ko", "de", "fr", "es", "ru", "ar"]) if (n.startsWith(code)) return code;
    return "en";
  },

  defaultTarget(source: string): string {
    return source === "zh" ? "en" : source === "en" ? "zh" : "en";
  },

  resolve(preferred: string, storedSource?: string, storedTarget?: string): { source: string; target: string } {
    const source = storedSource && (storedSource === "auto" || this.supported.includes(storedSource)) ? storedSource : this.code(preferred);
    const target = storedTarget && (storedTarget === "none" || this.supported.includes(storedTarget)) ? storedTarget : this.defaultTarget(source);
    return { source, target };
  },

  currentPair(): { source: string; target: string } {
    return this.resolve(navigator.language || "en", prefs.string(this.sourceKey), prefs.string(this.targetKey));
  },
};
