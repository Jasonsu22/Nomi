// Starts the app: the data folder and saved settings first, since the model reads them as it is
// built (as UserDefaults is ready before the Mac's AppModel), then the UI.
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { invoke } from "@tauri-apps/api/core";
import { initPlatform } from "./platform";
import { flushPrefs, loadPrefs } from "./support/prefs";
import "./styles.css";

function captureLogs() {
  const send = (level: string, args: unknown[]) => {
    const message = args.map((a) => (a instanceof Error ? `${a.message}\n${a.stack ?? ""}` : typeof a === "string" ? a : JSON.stringify(a))).join(" ");
    void invoke("log_line", { level, message }).catch(() => {});
  };
  for (const level of ["error", "warn"] as const) {
    const original = console[level].bind(console);
    console[level] = (...args: unknown[]) => {
      original(...args);
      send(level, args);
    };
  }
  window.addEventListener("error", (e) => send("error", [e.error ?? e.message]));
  window.addEventListener("unhandledrejection", (e) => send("error", ["unhandled", e.reason]));
}

async function start() {
  captureLogs();
  await initPlatform();
  await loadPrefs();
  const [{ Root }, { DeviceInfo }] = await Promise.all([import("./views/Root"), import("./app/onboarding")]);
  void invoke<{ cpu: string; cores: number; memoryGb: number; gpus: { name: string; kind: string; memoryTotalMb: number }[] }>("device_report").then((r) => {
    DeviceInfo.cpu = r.cpu;
    DeviceInfo.cores = r.cores;
    DeviceInfo.memoryGB = r.memoryGb;
    DeviceInfo.gpus = r.gpus.map((g) => ({ name: g.name, kind: g.kind, memoryMB: g.memoryTotalMb }));
  }, () => {});
  window.addEventListener("beforeunload", () => void flushPrefs());
  createRoot(document.getElementById("root")!).render(
    <StrictMode>
      <Root />
    </StrictMode>,
  );
}

void start();
