// Support/InterfacePreferences.swift: light, dark or the system's, applied as data-scheme on <html>.
import { useSyncExternalStore } from "react";
import { prefs } from "./prefs";

export type InterfaceAppearance = "system" | "light" | "dark";
export const appearanceKey = "nomi.appearance";
export const microphonePromptKey = "nomi.microphonePrompt";

const media = window.matchMedia("(prefers-color-scheme: dark)");
const listeners = new Set<() => void>();

export const Appearance = {
  get choice(): InterfaceAppearance {
    const v = prefs.string(appearanceKey);
    return v === "light" || v === "dark" ? v : "system";
  },
  set choice(v: InterfaceAppearance) {
    prefs.set(appearanceKey, v);
    this.apply();
  },
  get dark() {
    const c = this.choice;
    return c === "dark" || (c === "system" && media.matches);
  },
  apply() {
    document.documentElement.dataset.scheme = this.dark ? "dark" : "light";
    listeners.forEach((l) => l());
  },
};
media.addEventListener("change", () => Appearance.apply());

export function useDark(): boolean {
  return useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => Appearance.dark,
  );
}
