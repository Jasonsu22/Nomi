// Engine/LocalEngine.swift: the shared engine (moxin-engine) and live transcription. Rust starts
// the engine process and holds the microphone and the recording socket; the transcript, the
// session and pause work here as on the Mac.
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { fetch } from "@tauri-apps/plugin-http";
import { tr } from "../i18n";
import { newID } from "../support/format";
import { paths } from "../platform";
import { LiveTranscript, type Paragraph } from "../models/transcript";
import { LevelMeter, SessionState } from "../models/session";
import { mainFile, selectedModel, type LocalModelDefinition, type LocalModelRole } from "../models/localModels";
import type { VoiceSpan } from "../models/meetingVoices";
import { Accumulator, ChatStream } from "./chatStream";
import { ClassroomMicPreference } from "./audioInputs";
import { prefs } from "../support/prefs";

export type EngineReadiness = "preview" | "preparing" | "ready" | "sourceOnly" | "asrMissing" | "unavailable";

export type RuntimeModel = { path: string; files: string; loaded: boolean; error?: string | null };
export type RuntimeStatus = { asr: RuntimeModel; translator: RuntimeModel; assistant?: RuntimeModel | null };

export class CancellationError extends Error {
  constructor() {
    super("cancelled");
  }
}

/** Windows-only engine settings (Settings › Local models › Advanced). */
export const EngineTuning = {
  get interim(): string {
    return prefs.string("nomi.windows.interim") ?? "skip-busy";
  },
  get asrDevice(): string {
    return prefs.string("nomi.windows.asrDevice") ?? "auto";
  },
  get llmDevice(): string {
    return prefs.string("nomi.windows.llmDevice") ?? "cpu";
  },
  get threads(): number {
    return prefs.number("nomi.windows.threads") ?? 0;
  },
};

export const modelPath = (m: LocalModelDefinition) => paths.join(paths.root, "models", mainFile(m).file);

export class LocalEngine {
  transcript = new LiveTranscript();
  level = new LevelMeter();
  session = new SessionState();
  loadError: string | null = null;
  readiness: EngineReadiness = "preparing";
  modelStatus: RuntimeStatus | null = null;
  isChangingModel = false;
  activeReplies = 0;
  static maxReplies = 3;
  sourceLanguage = "zh";
  targetLanguage = "en";
  transcriptionTopic = "";
  inputDeviceUID: string | null = null;
  recordingURL: string | null = null;
  /** Live speakers: the model, where this run starts, and its label prefix. Set before start. */
  speakerModel: string | null = null;
  speakerOffset = 0;
  speakerTag = "";
  onFinished?: (paragraphs: Paragraph[], duration: number) => void;
  onInputFallback?: (name: string) => void;
  onSpeakers?: (spans: VoiceSpan[], prints: Record<string, number[]>) => void;
  onChange?: () => void;

  private port: number | null = null;
  private token: string | null = null;
  private launchID = "";
  private restartAttempts = 0;
  private shuttingDown = false;
  private recordingID = "";
  private gateOpen = false;
  private preparingDeadline: ReturnType<typeof setTimeout> | undefined;
  private stopTimer: ReturnType<typeof setTimeout> | undefined;
  private backgroundReplies = new Set<string>();
  private cancelledReplies = new Set<string>();
  private replyControllers = new Map<string, AbortController>();

  get isGenerating() {
    return this.activeReplies > 0;
  }

  get canStart() {
    return this.port !== null && this.session.phase === "idle" && !this.isChangingModel && (this.readiness === "ready" || this.readiness === "sourceOnly");
  }

  private changed() {
    this.onChange?.();
  }

  async connect() {
    await listen<{ launchID: string; port: number; token: string }>("engine-ready", (e) => {
      if (e.payload.launchID !== this.launchID || this.shuttingDown) return;
      this.port = e.payload.port;
      this.token = e.payload.token;
      void this.refreshStatus();
    });
    await listen<{ launchID: string; message: string | null }>("engine-exited", (e) => {
      if (e.payload.launchID !== this.launchID) return;
      this.backendExited(e.payload.message);
    });
    await listen<{ id: string; text: string }>("rec-event", (e) => {
      if (e.payload.id === this.recordingID) this.handle(e.payload.text);
    });
    await listen<{ id: string; rms: number }>("rec-level", (e) => {
      if (e.payload.id === this.recordingID && this.gateOpen) this.level.recordMicrophoneRMS(e.payload.rms);
    });
    await listen<{ id: string; message: string | null }>("rec-closed", (e) => {
      if (e.payload.id !== this.recordingID || this.shuttingDown || this.session.phase === "idle") return;
      this.loadError = tr("连接转录服务失败");
      this.finish(this.session.phase === "stopping" ? this.session.elapsed : this.session.beginStopping());
    });
    await listen<{ id: string; message: string }>("rec-mic-failed", (e) => {
      if (e.payload.id !== this.recordingID) return;
      if (this.session.phase === "listening" || this.session.phase === "preparing") {
        this.loadError = e.payload.message;
        this.stop();
      }
    });
    await listen<{ id: string; spans: VoiceSpan[]; prints: Record<string, number[]> }>("speaker-update", (e) => {
      if (e.payload.id === this.recordingID) this.onSpeakers?.(e.payload.spans, e.payload.prints);
    });
  }

  launch() {
    this.readiness = "preparing";
    this.loadError = null;
    this.port = null;
    this.token = null;
    this.launchID = newID();
    this.changed();
    const launchID = this.launchID;
    invoke("engine_launch", {
      launchId: launchID,
      config: {
        asrModel: modelPath(selectedModel("asr")),
        translatorModel: modelPath(selectedModel("translator")),
        assistantModel: modelPath(selectedModel("assistant")),
        interim: EngineTuning.interim,
        asrDevice: EngineTuning.asrDevice,
        llmDevice: EngineTuning.llmDevice,
        threads: EngineTuning.threads,
      },
    }).catch((error) => {
      if (launchID !== this.launchID) return;
      this.readiness = "unavailable";
      this.loadError = tr("引擎没有启动");
      console.error("engine_launch", error);
      this.changed();
    });
  }

  /** Starts the engine again, for model or device changes made outside a recording. */
  relaunch() {
    if (this.session.phase !== "idle") return;
    this.restartAttempts = 0;
    void invoke("engine_shutdown").finally(() => this.launch());
  }

  private backendExited(message: string | null) {
    if (this.shuttingDown) return;
    this.port = null;
    this.token = null;
    this.modelStatus = null;
    this.readiness = "unavailable";
    this.loadError = message || tr("引擎没有启动");
    if (this.session.phase !== "idle") this.finish(this.session.phase === "stopping" ? this.session.elapsed : this.session.beginStopping());
    this.changed();
    if (this.restartAttempts >= 1) return;
    this.restartAttempts++;
    this.readiness = "preparing";
    setTimeout(() => {
      if (!this.shuttingDown) this.launch();
    }, 1000);
  }

  private headers(json = false): Record<string, string> {
    const h: Record<string, string> = { Authorization: `Bearer ${this.token}` };
    if (json) h["Content-Type"] = "application/json";
    return h;
  }

  private url(path: string) {
    return `http://127.0.0.1:${this.port}/v1/${path}`;
  }

  async refreshStatus() {
    const port = this.port, token = this.token;
    if (port === null || token === null) return;
    try {
      const response = await fetch(this.url("status"), { headers: this.headers() });
      if (this.port !== port || this.shuttingDown) return;
      if (response.status !== 200) {
        this.readiness = "unavailable";
        this.changed();
        return;
      }
      this.apply(await response.json());
    } catch {
      if (this.port !== port || this.shuttingDown) return;
      this.readiness = "unavailable";
      this.changed();
    }
  }

  private apply(status: RuntimeStatus) {
    this.modelStatus = status;
    if (!status.asr.loaded) {
      this.readiness = status.asr.files === "missing" ? "asrMissing" : "unavailable";
      if (this.readiness === "unavailable") this.loadError = status.asr.error || tr("识别模型没有加载");
      this.changed();
      return;
    }
    this.loadError = null;
    this.readiness = status.translator.loaded ? "ready" : "sourceOnly";
    this.restartAttempts = 0;
    this.changed();
  }

  async selectModel(model: LocalModelDefinition, role: LocalModelRole) {
    if (this.session.phase !== "idle" || this.isChangingModel || this.port === null) throw new Error(tr("引擎还没准备好"));
    this.isChangingModel = true;
    this.changed();
    try {
      const response = await fetch(this.url("models/select"), { method: "POST", headers: this.headers(true), body: JSON.stringify({ role, path: modelPath(model) }) });
      const text = await response.text();
      if (response.status !== 200) throw new Error(text || tr("模型加载失败，请重试。"));
      const status = JSON.parse(text) as RuntimeStatus;
      this.apply(status);
      const loaded = role === "asr" ? status.asr.loaded : role === "translator" ? status.translator.loaded : status.assistant?.loaded;
      if (!loaded) throw new Error(tr("模型加载失败，请重试。"));
    } catch (error) {
      await this.refreshStatus();
      throw error;
    } finally {
      this.isChangingModel = false;
      this.changed();
    }
  }

  async unloadModel(model: LocalModelDefinition) {
    if (this.port === null) return;
    const response = await fetch(this.url("models/unload-path"), { method: "POST", headers: this.headers(true), body: JSON.stringify({ path: modelPath(model) }) });
    if (response.status !== 200) throw new Error((await response.text()) || tr("本地模型请求失败。"));
    this.apply(await response.json());
  }

  async generate(system: string, prompt: string, o: { maxTokens?: number; background?: boolean; onUpdate?: (text: string) => void; signal?: AbortSignal } = {}): Promise<string> {
    if (this.isChangingModel) throw new Error(tr("请等待本地模型切换结束。"));
    if (this.port === null) throw new Error(tr("引擎还没准备好"));
    const replyID = newID();
    const controller = new AbortController();
    this.replyControllers.set(replyID, controller);
    o.signal?.addEventListener("abort", () => {
      this.cancelledReplies.add(replyID);
      controller.abort();
      void this.cancelReply(replyID);
    });
    if (o.background) this.backgroundReplies.add(replyID);
    else this.activeReplies++;
    this.changed();
    try {
      const response = await fetch(this.url("assistant/generate"), {
        method: "POST",
        headers: this.headers(true),
        body: JSON.stringify({ system, prompt, max_tokens: o.maxTokens ?? 2048, reply_id: replyID }),
        signal: controller.signal,
      });
      if (response.status !== 200) throw new Error((await response.text()) || tr("本地模型请求失败。"));
      const reader = response.body!.getReader();
      const decoder = new TextDecoder();
      const acc = new Accumulator();
      let buffer = "";
      let last = 0;
      let shown = "";
      reading: while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        let nl: number;
        while ((nl = buffer.indexOf("\n")) >= 0) {
          const line = buffer.slice(0, nl);
          buffer = buffer.slice(nl + 1);
          const parsed = ChatStream.line(line);
          if (parsed.kind === "skip") continue;
          if (parsed.kind === "done") acc.finished = true;
          else {
            const object = ChatStream.object(parsed.payload);
            if (!object) continue;
            const message = acc.apply(object);
            if (message) throw new Error(message);
          }
          if (acc.finished) break reading;
          if (performance.now() - last < 80) continue;
          const text = acc.display;
          if (text && text !== shown) {
            last = performance.now();
            shown = text;
            o.onUpdate?.(text);
          }
        }
      }
      acc.finished = true;
      if (this.cancelledReplies.has(replyID)) throw new CancellationError();
      const answer = acc.answer;
      if (!answer) throw new Error(tr("模型未返回文字，请重试。"));
      if (answer !== shown) o.onUpdate?.(answer);
      return answer;
    } catch (error) {
      if (this.cancelledReplies.has(replyID) || controller.signal.aborted) throw new CancellationError();
      throw error;
    } finally {
      if (o.background) this.backgroundReplies.delete(replyID);
      else this.activeReplies--;
      this.cancelledReplies.delete(replyID);
      this.replyControllers.delete(replyID);
      this.changed();
    }
  }

  private async cancelReply(replyID: string) {
    if (this.port === null) return;
    await fetch(this.url("assistant/cancel"), { method: "POST", headers: this.headers(true), body: JSON.stringify({ reply_id: replyID }) }).catch(() => {});
  }

  async cancelBackgroundGeneration() {
    for (const id of this.backgroundReplies) {
      this.cancelledReplies.add(id);
      await this.cancelReply(id);
    }
  }

  // MARK: Recording

  start(resuming: Paragraph[] = [], offset = 0) {
    if (!this.canStart) return;
    this.loadError = null;
    this.transcript.setSourceLanguage(this.sourceLanguage);
    this.transcript.reset(resuming, offset);
    this.session.begin(offset);
    this.recordingID = newID();
    this.changed();
    const id = this.recordingID;
    void this.openSession(id);
    clearTimeout(this.preparingDeadline);
    this.preparingDeadline = setTimeout(() => {
      if (this.recordingID !== id) return;
      const stalled = this.session.phase === "preparing" || (this.session.phase === "listening" && !this.gateOpen && !this.session.isPaused);
      if (stalled) this.failStart(tr("麦克风或转录服务没有响应，请重试，或换一个输入源。"));
    }, 15_000);
  }

  private async openSession(id: string) {
    if (this.port === null || this.token === null) {
      this.failStart(tr("引擎还没准备好"));
      return;
    }
    const start = JSON.stringify({ type: "start", source: "microphone", sourceLanguage: this.sourceLanguage, targetLanguage: this.targetLanguage, context: this.transcriptionTopic });
    try {
      const opened = await invoke<{ deviceName: string; fellBack: boolean }>("recording_open", {
        options: {
          id,
          port: this.port,
          token: this.token,
          start,
          deviceId: this.inputDeviceUID,
          recordingPath: this.recordingURL,
          classroom: ClassroomMicPreference.isOn,
          speakerModel: this.speakerModel,
          speakerOffset: this.speakerOffset,
          speakerTag: this.speakerTag,
        },
      });
      if (this.recordingID !== id || (this.session.phase !== "preparing" && this.session.phase !== "listening")) {
        void invoke("recording_close", { id });
        return;
      }
      if (opened.fellBack) this.onInputFallback?.(opened.deviceName);
      this.gateOpen = true;
      await invoke("recording_gate", { id, open: true });
    } catch (error) {
      if (this.recordingID !== id) return;
      const message = String(error);
      this.failStart(message.includes("microphone") || message.includes("麦克风") ? tr("打不开麦克风") : tr("连接转录服务失败"));
    }
  }

  stop() {
    if (this.session.phase !== "preparing" && this.session.phase !== "listening") return;
    clearTimeout(this.preparingDeadline);
    this.gateOpen = false;
    const id = this.recordingID;
    void invoke("recording_stop_mic", { id });
    const duration = this.session.beginStopping();
    this.level.rms = 0;
    this.changed();
    void invoke("recording_send", { id, text: '{"type":"stop"}' });
    clearTimeout(this.stopTimer);
    this.stopTimer = setTimeout(() => {
      if (this.session.phase === "stopping" && this.recordingID === id) this.finish(duration);
    }, 45_000);
  }

  togglePause() {
    if (this.session.phase !== "listening") return;
    this.session.togglePause();
    this.gateOpen = !this.session.isPaused;
    if (this.session.isPaused) this.level.rms = 0;
    void invoke("recording_gate", { id: this.recordingID, open: this.gateOpen });
    this.changed();
  }

  async shutdown() {
    this.shuttingDown = true;
    this.gateOpen = false;
    await invoke("recording_close", { id: this.recordingID }).catch(() => {});
    await invoke("engine_shutdown").catch(() => {});
  }

  private handle(text: string) {
    let event: Record<string, unknown>;
    try {
      event = JSON.parse(text);
    } catch {
      return;
    }
    switch (event.type) {
      case "state":
        if (event.value === "listening" && this.session.phase === "preparing") {
          this.session.markListening();
          this.changed();
        } else if (event.value === "idle") {
          this.finish(this.session.phase === "stopping" ? this.session.elapsed : this.session.beginStopping());
        }
        break;
      case "tail": {
        const t = String(event.text ?? "");
        if (t) this.transcript.applyTail(t, Number(event.start ?? 0));
        break;
      }
      case "commit":
        this.transcript.applyCommit(
          { id: Number(event.id ?? 0), source: String(event.source ?? ""), translation: String(event.translation ?? ""), start: Number(event.start ?? 0), end: Number(event.end ?? 0) },
          String(event.tail ?? ""),
        );
        break;
      case "error":
        if (event.code === "asr_missing") {
          this.readiness = "asrMissing";
          this.failStart(tr("缺少识别模型"));
        }
        break;
    }
  }

  /** Everything the speaker model heard, at the end of a recording. */
  finishSpeakers(): Promise<{ spans: VoiceSpan[]; prints: Record<string, number[]> } | null> {
    return invoke<{ spans: VoiceSpan[]; prints: Record<string, number[]> } | null>("speakers_finish", { id: this.recordingID }).catch(() => null);
  }

  private finish(duration: number) {
    if (this.session.phase === "idle") return;
    clearTimeout(this.stopTimer);
    clearTimeout(this.preparingDeadline);
    this.gateOpen = false;
    const id = this.recordingID;
    this.transcript.flush(duration);
    const paragraphs = this.transcript.paragraphs;
    this.session.markIdle();
    this.level.rms = 0;
    this.changed();
    // The speaker model hears the rest of the audio before the socket and file close.
    void this.finishSpeakers().then((result) => {
      if (result) this.onSpeakers?.(result.spans, result.prints);
      void invoke("recording_close", { id });
      this.onFinished?.(paragraphs, duration);
    });
  }

  private failStart(message: string) {
    clearTimeout(this.preparingDeadline);
    this.loadError = message;
    this.gateOpen = false;
    void invoke("recording_close", { id: this.recordingID }).catch(() => {});
    this.session.markIdle();
    this.changed();
    this.onFinished?.([], 0);
  }

  updateTranscriptionTopic(topic: string) {
    this.transcriptionTopic = topic;
    if (this.session.phase === "idle") return;
    void invoke("recording_send", { id: this.recordingID, text: JSON.stringify({ type: "topic", context: topic }) });
  }
}
