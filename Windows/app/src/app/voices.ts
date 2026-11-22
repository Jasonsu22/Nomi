// App/AppModel+Voices.swift and AppModel+LiveSpeakers.swift: speakers, live and after recording.
import { invoke } from "@tauri-apps/api/core";
import { tr, trf } from "../i18n";
import { nowReference } from "../support/format";
import { prefs } from "../support/prefs";
import { MyVoice, VoiceLabels, type MeetingVoices, type VoiceSpan } from "../models/meetingVoices";
import { findModel } from "../models/localModels";
import type { Meeting } from "../models/meeting";
import { paths } from "../platform";
import { MeetingStore } from "./stores";
import { AppModel } from "./model";

/** Settings › Recording & Translation › live speaker model (Windows: sherpa-onnx models). */
export type SpeakerModelKind = "standard" | "zh-en";
export const speakerModelKinds: SpeakerModelKind[] = ["standard", "zh-en"];
export const SpeakerModels = {
  enabledKey: "lecturenote.liveSpeakers",
  choiceKey: "lecturenote.liveSpeakerModel",
  get isEnabled() {
    return prefs.bool(this.enabledKey) ?? true;
  },
  get chosen(): SpeakerModelKind {
    return prefs.string(this.choiceKey) === "zh-en" ? "zh-en" : "standard";
  },
  modelID: (k: SpeakerModelKind) => (k === "standard" ? "speakers-standard" : "speakers-zh-en"),
  title: (k: SpeakerModelKind) => (k === "standard" ? tr("标准") : "CAM++"),
  detail: (k: SpeakerModelKind) => (k === "standard" ? tr("最快，测试中最准，能记住你的声音") : tr("中英文课堂更稳")),
  page: (k: SpeakerModelKind) => (k === "standard" ? "https://huggingface.co/csukuangfj/sherpa-onnx-pyannote-segmentation-3-0" : "https://huggingface.co/csukuangfj/speaker-embedding-models"),
};

export const ClassmateVoicesPreference = {
  key: "lecturenote.classmateVoices",
  get isOn() {
    return prefs.bool(this.key) ?? true;
  },
};

declare module "./model" {
  interface AppModel {
    speakerFiles(): { segmentation: string; embedding: string } | null;
    startLiveSpeakers(meetingID: string, offset: number): void;
    liveVoices(meeting: Meeting): { voices: MeetingVoices; spans: VoiceSpan[] } | null;
    finishLiveSpeakers(meetingID: string): void;
    checkVoices(id: string, automatic?: boolean): void;
    checkVoicesAfterRecording(id: string): void;
    markMe(meetingID: string, paragraphID: number): void;
    showSpeaker(meetingID: string, speaker: string, shown: boolean): void;
    renameSpeaker(meetingID: string, speaker: string, name: string): void;
    clearMe(meetingID: string): void;
    setTeacher(meetingID: string, speaker: string): void;
  }
}

const P = AppModel.prototype;

P.speakerFiles = function () {
  const model = findModel(SpeakerModels.modelID(SpeakerModels.chosen));
  if (!model || !this.localModels.installed.has(model.id)) return null;
  const root = paths.join(paths.root, "models");
  return { segmentation: paths.join(root, model.files[0].file), embedding: paths.join(root, model.files[1].file) };
};

P.startLiveSpeakers = function (meetingID, offset) {
  this.liveSpeakerSpans = [];
  this.liveSpeakerPrints = {};
  const files = SpeakerModels.isEnabled ? this.speakerFiles() : null;
  const run = this.meetings.find((m) => m.id === meetingID)?.audioFiles?.length ?? 1;
  this.engine.speakerModel = files ? JSON.stringify(files) : null;
  this.engine.speakerOffset = offset;
  this.engine.speakerTag = `R${run}-`;
};

P.liveVoices = function (meeting) {
  if (!meeting.isLive || !this.liveSpeakerSpans.length) return null;
  const merged = VoiceLabels.merging(meeting.voices, this.liveSpeakerSpans, this.liveSpeakerPrints, nowReference());
  if (!merged) return null;
  const mine = MyVoice.print;
  if (!merged.voices.me && !merged.voices.meChosen && mine && merged.voices.prints) merged.voices.me = MyVoice.match(mine, merged.voices.prints, merged.voices.teacher);
  return merged;
};

P.finishLiveSpeakers = function (meetingID) {
  const spans = this.liveSpeakerSpans;
  const prints = this.liveSpeakerPrints;
  this.liveSpeakerSpans = [];
  this.liveSpeakerPrints = {};
  this.engine.speakerModel = null;
  const meeting = this.meetings.find((m) => m.id === meetingID);
  if (!meeting || meeting.isLive || !spans.length) return;
  const merged = VoiceLabels.merging(meeting.voices, spans, prints, nowReference());
  if (!merged) return;
  const mine = MyVoice.print;
  if (!merged.voices.me && !merged.voices.meChosen && mine && merged.voices.prints) merged.voices.me = MyVoice.match(mine, merged.voices.prints, merged.voices.teacher);
  this.meetings = this.meetings.map((m) => (m.id === meetingID ? { ...m, paragraphs: VoiceLabels.apply(merged.spans, m.paragraphs), voices: merged.voices } : m));
};

P.checkVoicesAfterRecording = function (id) {
  // The live model labelled this recording already; the after-recording pass is for meetings without it.
  const meeting = this.meetings.find((m) => m.id === id);
  if (meeting && !meeting.voices) this.checkVoices(id, true);
};

P.checkVoices = function (id, automatic = false) {
  const meeting = this.meetings.find((m) => m.id === id);
  if (this.checkingVoices.has(id) || !meeting || meeting.isLive || !meeting.audioFiles?.length) return;
  if (automatic && (!ClassmateVoicesPreference.isOn || this.recordingMeetingID !== null)) return;
  const files = this.speakerFiles();
  if (!files) {
    if (!automatic) {
      this.voiceError[id] = tr("先在设置里下载说话人模型。");
      this.changed();
    }
    return;
  }
  this.checkingVoices.add(id);
  delete this.voiceError[id];
  this.changed();
  const dir = MeetingStore.audioDirectory(id);
  void (async () => {
    try {
      const found = await invoke<{ spans: VoiceSpan[]; prints: Record<string, number[]> }>("voices_analyze", { files: meeting.audioFiles!.map((f) => paths.join(dir, f)), segmentation: files.segmentation, embedding: files.embedding });
      const current = this.meetings.find((m) => m.id === id);
      if (!current || current.isLive) return;
      const labelled = VoiceLabels.label(current.paragraphs, found.spans, nowReference());
      if (!labelled) {
        this.voiceError[id] = tr("录音里没有找到说话声。");
        return;
      }
      const voices = { ...labelled.voices, prints: found.prints };
      const mine = MyVoice.print;
      if (mine) voices.me = MyVoice.match(mine, found.prints, voices.teacher);
      this.meetings = this.meetings.map((m) => (m.id === id ? { ...m, paragraphs: labelled.paragraphs, voices } : m));
    } catch (error) {
      this.voiceError[id] = trf("无法识别声音：%@", error instanceof Error ? error.message : String(error));
    } finally {
      this.checkingVoices.delete(id);
      this.changed();
    }
  })();
};

function editVoices(m: AppModel, meetingID: string, change: (v: MeetingVoices) => MeetingVoices) {
  m.meetings = m.meetings.map((x) => (x.id === meetingID && x.voices ? { ...x, voices: change(x.voices) } : x));
}

P.markMe = function (meetingID, paragraphID) {
  const meeting = this.meetings.find((m) => m.id === meetingID);
  const voices = meeting?.voices;
  const paragraph = meeting?.paragraphs.find((p) => p.id === paragraphID);
  if (!meeting || !voices || !paragraph) return;
  const voice = VoiceLabels.mainVoice(paragraph, voices.teacher);
  if (!voice) return;
  editVoices(this, meetingID, (v) => ({ ...v, me: voice, meChosen: true }));
  const print = voices.prints?.[voice];
  if (!print) return;
  const mine = MyVoice.blended(MyVoice.print, print);
  MyVoice.print = mine;
  let changed = false;
  const updated = this.meetings.map((m) => {
    if (m.id === meetingID || !m.voices || m.voices.meChosen || !m.voices.prints) return m;
    const match = MyVoice.match(mine, m.voices.prints, m.voices.teacher);
    if ((match ?? null) === (m.voices.me ?? null)) return m;
    changed = true;
    return { ...m, voices: { ...m.voices, me: match } };
  });
  if (changed) this.meetings = updated;
};

P.showSpeaker = function (meetingID, speaker, shown) {
  this.meetings = this.meetings.map((m) => {
    if (m.id !== meetingID) return m;
    const hidden = new Set(m.hiddenSpeakers ?? []);
    if (shown) hidden.delete(speaker);
    else hidden.add(speaker);
    return { ...m, hiddenSpeakers: hidden.size ? [...hidden].sort() : null };
  });
};

P.renameSpeaker = function (meetingID, speaker, name) {
  const trimmed = name.trim();
  editVoices(this, meetingID, (v) => {
    const names = { ...(v.names ?? {}) };
    if (trimmed) names[speaker] = [...trimmed].slice(0, 40).join("");
    else delete names[speaker];
    return { ...v, names: Object.keys(names).length ? names : null };
  });
};

P.clearMe = function (meetingID) {
  editVoices(this, meetingID, (v) => ({ ...v, me: null, meChosen: true }));
};

P.setTeacher = function (meetingID, speaker) {
  editVoices(this, meetingID, (v) => (speaker in v.seconds ? { ...v, teacher: speaker } : v));
};
