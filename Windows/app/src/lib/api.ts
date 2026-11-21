// The Rust core's commands and events, typed. Names match src-tauri/src/lib.rs.
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

export type Settings = {
  setUp: boolean;
  asrModel: string;
  llmModel: string;
  asrDevice: string;
  llmDevice: string;
  threads: number;
  interim: "all" | "skip-busy" | "off";
  sourceLanguage: string;
  targetLanguage: string;
  inputDevice: string;
  liveSpeakers: boolean;
  speakerModel: string;
  myVoice: number[] | null;
  uiLanguage: string;
};

export type ModelView = {
  id: string;
  role: "asr" | "llm" | "speakers";
  name: string;
  sets: string[];
  files: { file: string; size: number }[];
  ready: boolean;
  downloading: boolean;
  size: number;
};

export type EngineState = {
  state: "stopped" | "starting" | "ready" | "failed" | "";
  message: string | null;
  status: Record<string, { files: string; loaded: boolean; error: string | null }> | null;
};

export type Overview = {
  settings: Settings;
  models: ModelView[];
  engine: EngineState;
  engineFound: boolean;
  dataFolder: string;
  modelsFolder: string;
  recording: boolean;
  material: "mica" | "sidebar" | "none";
};

export type Gpu = { index: number; name: string; description: string; backend: string; kind: string; memoryTotalMb: number };

export type DeviceReport = {
  cpu: string;
  cores: number;
  threads: number;
  memoryGb: number;
  gpus: Gpu[];
  os: string;
  suggestedSet: "Lite" | "Standard" | "Full";
  reason: string;
};

export type Commit = { id: number; source: string; translation: string; start: number; end: number; speaker?: string };

export type Paragraph = {
  id: number;
  openedAt: number;
  commits: Commit[];
  tail: string;
  closed: boolean;
  sourceLanguage?: string;
};

export type VoiceName =
  | { kind: "named"; name: string }
  | { kind: "me" }
  | { kind: "several" }
  | { kind: "number"; number: number };

export type Voices = {
  teacher: string;
  seconds: Record<string, number>;
  me?: string;
  names?: Record<string, string>;
};

export type Meeting = {
  id: string;
  title: string;
  startedAt: number;
  duration: number;
  sourceLanguage: string;
  targetLanguage: string;
  paragraphs: Paragraph[];
  isLive: boolean;
  inputDeviceName?: string;
  voices?: Voices;
  hiddenSpeakers?: string[];
  speakerNames: Record<string, VoiceName>;
  audioPath: string | null;
};

export type MeetingSummary = {
  id: string;
  title: string;
  startedAt: number;
  duration: number;
  sourceLanguage: string;
  targetLanguage: string;
  preview: string;
  lines: number;
  speakers: number;
  isLive: boolean;
};

export type LiveUpdate = {
  meetingId: string;
  title: string;
  paragraphs: Paragraph[];
  speakerNames: Record<string, VoiceName>;
  elapsed: number;
  state: "listening" | "stopping" | "saving" | "done" | string;
  asr: string;
  translator: string;
  inputName: string;
  speakersOn: boolean;
};

export type StartOptions = {
  title: string;
  input: "microphone" | "file";
  device: string;
  file: string | null;
  sourceLanguage: string;
  targetLanguage: string;
};

export type Progress = {
  id: string;
  received: number;
  total: number;
  state: "downloading" | "done" | "failed" | "cancelled";
  message: string | null;
  bytesPerSecond: number;
};

export type InputDevice = { name: string; isDefault: boolean };

export const api = {
  overview: () => invoke<Overview>("overview"),
  deviceReport: () => invoke<DeviceReport>("device_report"),
  saveSettings: (settings: Settings) => invoke<void>("save_settings", { settings }),
  downloadModel: (id: string) => invoke<void>("download_model", { id }),
  cancelDownload: (id: string) => invoke<void>("cancel_download", { id }),
  deleteModel: (id: string) => invoke<void>("delete_model", { id }),
  startEngine: () => invoke<void>("start_engine"),
  inputDevices: () => invoke<InputDevice[]>("input_devices"),
  startRecording: (options: StartOptions) => invoke<string>("start_recording", { options }),
  liveSnapshot: () => invoke<LiveUpdate | null>("live_snapshot"),
  stopRecording: () => invoke<string>("stop_recording"),
  listMeetings: () => invoke<MeetingSummary[]>("list_meetings"),
  getMeeting: (id: string) => invoke<Meeting>("get_meeting", { id }),
  renameMeeting: (id: string, title: string) => invoke<Meeting>("rename_meeting", { id, title }),
  deleteMeeting: (id: string) => invoke<void>("delete_meeting", { id }),
  setHiddenSpeakers: (id: string, hidden: string[]) => invoke<Meeting>("set_hidden_speakers", { id, hidden }),
  renameSpeaker: (id: string, speaker: string, name: string) => invoke<Meeting>("rename_speaker", { id, speaker, name }),
  setMe: (id: string, speaker: string | null) => invoke<Meeting>("set_me", { id, speaker }),
  setTeacher: (id: string, speaker: string) => invoke<Meeting>("set_teacher", { id, speaker }),
  openFolder: (path: string) => invoke<void>("open_folder", { path }),
};

export const events = {
  engineState: (f: (s: EngineState) => void): Promise<UnlistenFn> => listen<EngineState>("engine-state", (e) => f(e.payload)),
  liveUpdate: (f: (u: LiveUpdate) => void): Promise<UnlistenFn> => listen<LiveUpdate>("live-update", (e) => f(e.payload)),
  liveLevel: (f: (rms: number) => void): Promise<UnlistenFn> => listen<number>("live-level", (e) => f(e.payload)),
  liveNotice: (f: (n: { code: string; message: string }) => void): Promise<UnlistenFn> =>
    listen<{ code: string; message: string }>("live-notice", (e) => f(e.payload)),
  download: (f: (p: Progress) => void): Promise<UnlistenFn> => listen<Progress>("download-progress", (e) => f(e.payload)),
};
