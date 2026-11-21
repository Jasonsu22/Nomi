// Models/LocalModelCatalog.swift and LocalModelLibrary.swift, for Windows: the same roles, as GGUF
// files run by the Windows workers. Files live in %LOCALAPPDATA%\Nomi\models.
import { tr } from "../i18n";
import { prefs } from "../support/prefs";

export type LocalModelRole = "asr" | "translator" | "assistant";
export const localModelRoles: LocalModelRole[] = ["asr", "translator", "assistant"];
export const roleTitle = (r: LocalModelRole) => ({ asr: tr("语音识别模型"), translator: tr("翻译模型"), assistant: tr("本地大模型") })[r];
export const preferenceKey = (r: LocalModelRole) => `nomi.model.${r}`;
const defaultID = (r: LocalModelRole) => (r === "asr" ? "qwen3-asr-0.6b" : "qwen3.5-2b");

export type ModelFile = { file: string; path: string; size: number };

export type LocalModelDefinition = {
  id: string;
  role: LocalModelRole | "speakers";
  name: string;
  quantization: string;
  files: ModelFile[];
};

export const supports = (m: LocalModelDefinition, role: LocalModelRole) => m.role === role || (role === "assistant" && m.role === "translator");
export const modelBytes = (m: LocalModelDefinition) => m.files.reduce((n, f) => n + f.size, 0);

const segmentation: ModelFile = { file: "pyannote-segmentation-3.0.onnx", path: "csukuangfj/sherpa-onnx-pyannote-segmentation-3-0/resolve/main/model.onnx", size: 5_992_913 };

/** The models offered on Windows. Sizes are the published files. */
export const catalog: LocalModelDefinition[] = [
  { id: "qwen3-0.6b", role: "assistant", name: "Qwen3 0.6B", quantization: "Q8_0 GGUF", files: [{ file: "Qwen3-0.6B-Q8_0.gguf", path: "Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf", size: 639_446_688 }] },
  { id: "qwen3-4b", role: "assistant", name: "Qwen3 4B", quantization: "Q4_K_M GGUF", files: [{ file: "Qwen3-4B-Q4_K_M.gguf", path: "Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf", size: 2_497_280_256 }] },
  { id: "qwen3-asr-0.6b", role: "asr", name: "Qwen3-ASR 0.6B", quantization: "Q8_0 GGUF", files: [{ file: "Qwen3-ASR-0.6B-Q8_0.gguf", path: "handy-computer/Qwen3-ASR-0.6B-gguf/resolve/main/Qwen3-ASR-0.6B-Q8_0.gguf", size: 850_423_456 }] },
  { id: "qwen3-asr-1.7b", role: "asr", name: "Qwen3-ASR 1.7B", quantization: "Q8_0 GGUF", files: [{ file: "Qwen3-ASR-1.7B-Q8_0.gguf", path: "handy-computer/Qwen3-ASR-1.7B-gguf/resolve/main/Qwen3-ASR-1.7B-Q8_0.gguf", size: 2_185_030_624 }] },
  { id: "qwen3.5-0.8b", role: "translator", name: "Qwen3.5 0.8B", quantization: "Q4_K_M GGUF", files: [{ file: "Qwen3.5-0.8B-Q4_K_M.gguf", path: "unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf", size: 532_517_120 }] },
  { id: "qwen3.5-2b", role: "translator", name: "Qwen3.5 2B", quantization: "Q4_K_M GGUF", files: [{ file: "Qwen3.5-2B-Q4_K_M.gguf", path: "unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf", size: 1_280_835_840 }] },
  { id: "qwen3.5-4b", role: "translator", name: "Qwen3.5 4B", quantization: "Q4_K_M GGUF", files: [{ file: "Qwen3.5-4B-Q4_K_M.gguf", path: "unsloth/Qwen3.5-4B-GGUF/resolve/main/Qwen3.5-4B-Q4_K_M.gguf", size: 2_740_937_888 }] },
  { id: "speakers-standard", role: "speakers", name: "Standard", quantization: "ONNX", files: [segmentation, { file: "wespeaker-resnet34.onnx", path: "csukuangfj/speaker-embedding-models/resolve/main/wespeaker_en_voxceleb_resnet34_LM.onnx", size: 26_530_550 }] },
  { id: "speakers-zh-en", role: "speakers", name: "CAM++", quantization: "ONNX", files: [segmentation, { file: "campplus-zh-en.onnx", path: "csukuangfj/speaker-embedding-models/resolve/main/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx", size: 28_281_165 }] },
];

export const findModel = (id: string) => catalog.find((m) => m.id === id) ?? null;

export function selectedModel(role: LocalModelRole): LocalModelDefinition {
  const id = prefs.string(preferenceKey(role)) ?? defaultID(role);
  return catalog.find((m) => supports(m, role) && m.id === id) ?? catalog.find((m) => m.id === defaultID(role))!;
}

/** The main file (the GGUF the worker loads). */
export const mainFile = (m: LocalModelDefinition) => m.files[m.files.length - 1];

export type ModelDownloadProgress = { received: number; total: number; bytesPerSecond: number };
