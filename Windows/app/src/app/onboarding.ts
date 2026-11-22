// App/AppModel+Onboarding.swift: the first-start guide.
import { prefs } from "../support/prefs";
import { catalog, findModel, selectedModel, type LocalModelDefinition, type LocalModelRole } from "../models/localModels";
import { AppModel } from "./model";

export const OnboardingPreference = {
  key: "lecturenote.onboardingDone",
  get done() {
    return prefs.bool(this.key) ?? false;
  },
  set done(value: boolean) {
    prefs.set(this.key, value);
  },
};

/** Memory and processor, read once at start (device_report). */
export const DeviceInfo = { memoryGB: 16, cores: 8, gpus: [] as { name: string; kind: string; memoryMB: number }[], cpu: "" };
let markReady: () => void = () => {};
/** Resolves once device_report has filled DeviceInfo (it asks the speech worker for GPUs). */
export const deviceReady = new Promise<void>((resolve) => (markReady = resolve));
export const deviceReported = () => markReady();

declare module "./model" {
  interface AppModel {
    readonly prefersLightModels: boolean;
    recommendedModel(role: LocalModelRole): LocalModelDefinition;
    alternativeModel(role: LocalModelRole): LocalModelDefinition | null;
    downloadAndUse(item: LocalModelDefinition, role: LocalModelRole): void;
    useProfileFromOnboarding(id: string): void;
    finishOnboarding(startTour: boolean): void;
  }
}

const P = AppModel.prototype;

/** PCs under 16 GB, or with few cores and no graphics card, get the lighter models (Phase 0 findings). */
Object.defineProperty(P, "prefersLightModels", {
  get() {
    return DeviceInfo.memoryGB < 15 || (DeviceInfo.cores < 6 && DeviceInfo.gpus.length === 0);
  },
});

P.recommendedModel = function (role) {
  if (role === "asr") {
    const discrete = DeviceInfo.gpus.some((g) => g.kind === "gpu" && g.memoryMB >= 6000) && DeviceInfo.memoryGB >= 15;
    return findModel(discrete ? "qwen3-asr-1.7b" : "qwen3-asr-0.6b")!;
  }
  return findModel(this.prefersLightModels ? "qwen3.5-0.8b" : "qwen3.5-2b") ?? selectedModel(role);
};

P.alternativeModel = function (role) {
  const pair = role === "asr" ? ["qwen3-asr-1.7b", "qwen3-asr-0.6b"] : ["qwen3.5-2b", "qwen3.5-0.8b"];
  const recommended = this.recommendedModel(role).id;
  return catalog.find((m) => pair.includes(m.id) && m.id !== recommended) ?? null;
};

P.downloadAndUse = function (item, role) {
  this.localModels.rememberSelection(item, role);
  if (!this.localModels.installed.has(item.id)) this.localModels.download(item);
  void (async () => {
    for (;;) {
      if (this.localModels.errors[item.id]) return;
      if (this.localModels.installed.has(item.id) && this.canSwitchModels && this.engine.readiness !== "preparing") break;
      await new Promise((r) => setTimeout(r, 1000));
    }
    const status = this.engine.modelStatus;
    const loaded = role === "asr" ? status?.asr : role === "translator" ? status?.translator : status?.assistant;
    if (loaded?.loaded && loaded.path.endsWith(item.files.at(-1)!.file)) return;
    if (this.engine.readiness === "unavailable" || this.engine.readiness === "asrMissing") this.engine.relaunch();
    else await this.selectLocalModel(item, role);
  })();
};

P.useProfileFromOnboarding = function (id) {
  if (!this.llmConfiguration.profiles.some((p) => p.id === id)) return;
  this.llmConfiguration.activate(id);
  this.llmConfiguration.setMode("api");
};

P.finishOnboarding = function (startTour) {
  OnboardingPreference.done = true;
  this.onboardingPresented = false;
  if (startTour) this.startTutorial();
  this.changed();
};
