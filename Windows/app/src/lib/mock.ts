// Browser preview only (npm run dev, opened outside Tauri): sample answers for every command, so
// the screens can be designed and checked in a normal browser. Never loaded inside the app.
import { mockIPC, mockWindows } from "@tauri-apps/api/mocks";
import type { Meeting, MeetingSummary, Overview } from "./api";

const settings = {
  setUp: true, asrModel: "qwen3-asr-0.6b", llmModel: "qwen3.5-2b", asrDevice: "auto", llmDevice: "cpu", threads: 0, interim: "skip-busy",
  sourceLanguage: "auto", targetLanguage: "en", inputDevice: "", liveSpeakers: true, speakerModel: "standard", myVoice: null, uiLanguage: "",
};

const model = (id: string, role: string, name: string, size: number, ready: boolean) => ({ id, role, name, sets: [], files: [], ready, downloading: false, size });

const overview: Overview = {
  settings: settings as Overview["settings"],
  models: [
    model("qwen3-asr-0.6b", "asr", "Qwen3-ASR 0.6B", 850e6, true) as never,
    model("qwen3-asr-1.7b", "asr", "Qwen3-ASR 1.7B", 2.18e9, false) as never,
    model("qwen3.5-0.8b", "llm", "Qwen3.5 0.8B", 532e6, false) as never,
    model("qwen3.5-2b", "llm", "Qwen3.5 2B", 1.28e9, true) as never,
    model("standard", "speakers", "Standard", 32e6, true) as never,
    model("zh-en", "speakers", "Chinese + English", 34e6, false) as never,
  ],
  engine: { state: "ready", message: null, status: null },
  engineFound: true,
  dataFolder: "C:\\Users\\student\\AppData\\Local\\Nomi",
  modelsFolder: "C:\\Users\\student\\AppData\\Local\\Nomi\\models",
  recording: false,
  material: "none",
};

const commit = (id: number, source: string, translation: string, start: number, speaker?: string) => ({ id, source, translation, start, end: start + 4, speaker });

const meeting: Meeting = {
  id: "M1", title: "NLP 第 8 讲：注意力机制", startedAt: 785_000_000, duration: 3120, sourceLanguage: "auto", targetLanguage: "en",
  isLive: false, inputDeviceName: "Microphone Array (Realtek)",
  paragraphs: [
    { id: 1, openedAt: 2, closed: true, tail: "", commits: [
      commit(1, "今天我们讲 attention 是怎么在 Transformer 里工作的。", "Today we'll look at how attention works inside the Transformer.", 2, "S1"),
      commit(2, "每个 token 都会和序列里其他所有 token 计算一个相似度。", "Every token computes a similarity score with every other token in the sequence.", 6, "S1"),
    ] },
    { id: 2, openedAt: 14, closed: true, tail: "", commits: [commit(3, "老师，这个复杂度是平方的吗？", "Teacher, is this cost quadratic?", 14, "S2")] },
    { id: 3, openedAt: 19, closed: true, tail: "", commits: [commit(4, "对，所以序列一长，成本就涨得很快。", "Yes, so the cost grows quickly as the sequence gets longer.", 19, "S1")] },
  ],
  voices: { teacher: "S1", seconds: { S1: 2900, S2: 40 } },
  speakerNames: { S1: { kind: "number", number: 1 }, S2: { kind: "number", number: 2 } },
  audioPath: null,
};

const summaries: MeetingSummary[] = [
  { id: "M1", title: meeting.title, startedAt: meeting.startedAt, duration: 3120, sourceLanguage: "auto", targetLanguage: "en", preview: "今天我们讲 attention 是怎么在 Transformer 里工作的。", lines: 4, speakers: 2, isLive: false },
  { id: "M2", title: "Academic English", startedAt: 784_900_000, duration: 2700, sourceLanguage: "en", targetLanguage: "zh", preview: "Okay, let's get started. Did you present in English before?", lines: 120, speakers: 3, isLive: false },
];

export function installMock() {
  mockWindows("main");
  mockIPC((command) => {
    switch (command) {
      case "overview": return overview;
      case "device_report": return { cpu: "Intel Core Ultra 9 185H", cores: 16, threads: 22, memoryGb: 31.6, gpus: [{ index: 0, name: "Vulkan0", description: "Intel(R) Arc(TM) Graphics", backend: "Vulkan", kind: "igpu", memoryTotalMb: 16000 }], os: "Windows 11 (26100)", suggestedSet: "Standard", reason: "igpu" };
      case "list_meetings": return summaries;
      case "get_meeting": return meeting;
      case "input_devices": return [{ name: "Microphone Array (Realtek)", isDefault: true }];
      case "live_snapshot": return null;
      default: return null;
    }
  }, { shouldMockEvents: true });
}
