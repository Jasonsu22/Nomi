// Models/PromptPreferences.swift: reply language and the student's own skills.
import { isEnglish, tr } from "../i18n";
import { languageName } from "../support/format";
import { LectureLanguages } from "../support/languages";
import { prefs } from "../support/prefs";

export type PromptSkill = { id: string; name: string; body: string; enabled: boolean };

const followInterface = "interface";
const languageKey = "nomi.prompt.replyLanguage";
const skillsKey = "nomi.prompt.skills";

export class PromptPreferences {
  static followInterface = followInterface;
  replyLanguage: string;
  skills: PromptSkill[];
  onChange?: () => void;

  constructor() {
    const language = prefs.string(languageKey) ?? followInterface;
    this.replyLanguage = language === followInterface || LectureLanguages.supported.includes(language) ? language : followInterface;
    this.skills = prefs.get<PromptSkill[]>(skillsKey) ?? [];
  }

  get replyLanguageTitle() {
    return this.replyLanguage === followInterface ? tr("跟随界面") : languageName(this.replyLanguage);
  }

  get modelLanguageName(): string {
    const code = this.replyLanguage === followInterface ? (isEnglish() ? "en" : "zh") : this.replyLanguage;
    return ({ zh: "Simplified Chinese", en: "English", ja: "Japanese", ko: "Korean", de: "German", fr: "French", es: "Spanish", ru: "Russian", ar: "Arabic" } as Record<string, string>)[code] ?? "English";
  }

  setReplyLanguage(code: string) {
    this.replyLanguage = code === followInterface || LectureLanguages.supported.includes(code) ? code : followInterface;
    prefs.set(languageKey, this.replyLanguage);
    this.onChange?.();
  }

  upsert(skill: PromptSkill) {
    const i = this.skills.findIndex((s) => s.id === skill.id);
    this.skills = i >= 0 ? this.skills.map((s) => (s.id === skill.id ? skill : s)) : [...this.skills, skill];
    this.persist();
  }

  setEnabled(enabled: boolean, id: string) {
    this.skills = this.skills.map((s) => (s.id === id ? { ...s, enabled } : s));
    this.persist();
  }

  delete(id: string) {
    this.skills = this.skills.filter((s) => s.id !== id);
    this.persist();
  }

  private persist() {
    prefs.set(skillsKey, this.skills);
    this.onChange?.();
  }
}
