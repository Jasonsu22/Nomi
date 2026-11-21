// The Mac's UserDefaults: small settings, kept in prefs.json by the Rust side. Loaded once at
// start (`loadPrefs`), read synchronously after that, written back shortly after each change.
import { invoke } from "@tauri-apps/api/core";

let values: Record<string, unknown> = {};
let timer: ReturnType<typeof setTimeout> | undefined;
const listeners = new Set<() => void>();

export async function loadPrefs(): Promise<void> {
  try {
    values = (await invoke<Record<string, unknown>>("prefs_load")) ?? {};
  } catch {
    values = {};
  }
}

function persist() {
  clearTimeout(timer);
  timer = setTimeout(() => void invoke("prefs_save", { values }).catch(() => {}), 200);
}

export function flushPrefs(): Promise<void> {
  clearTimeout(timer);
  return invoke<void>("prefs_save", { values }).catch(() => {});
}

export const prefs = {
  string(key: string): string | undefined {
    const v = values[key];
    return typeof v === "string" ? v : undefined;
  },
  bool(key: string): boolean | undefined {
    const v = values[key];
    return typeof v === "boolean" ? v : undefined;
  },
  number(key: string): number | undefined {
    const v = values[key];
    return typeof v === "number" ? v : undefined;
  },
  get<T>(key: string): T | undefined {
    return values[key] as T | undefined;
  },
  set(key: string, value: unknown) {
    if (value === undefined || value === null) delete values[key];
    else values[key] = value;
    persist();
    listeners.forEach((f) => f());
  },
  remove(key: string) {
    delete values[key];
    persist();
    listeners.forEach((f) => f());
  },
  subscribe(f: () => void) {
    listeners.add(f);
    return () => listeners.delete(f);
  },
  /** For tests. */
  reset(next: Record<string, unknown> = {}) {
    values = { ...next };
  },
};
