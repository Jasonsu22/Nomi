// Engine/AudioInputs.swift: microphones on this PC and the one chosen.
import { invoke } from "@tauri-apps/api/core";
import { tr } from "../i18n";
import { prefs } from "../support/prefs";

export type AudioInputDevice = { id: string; name: string; isDefault: boolean };

export class AudioInputs {
  static systemDefault = "system";
  static key = "nomi.audioInputUID";
  devices: AudioInputDevice[] = [];
  onChange?: () => void;
  private _selected: string;

  constructor() {
    this._selected = prefs.string(AudioInputs.key) ?? AudioInputs.systemDefault;
  }

  get selectedUID() {
    return this._selected;
  }
  set selectedUID(value: string) {
    this._selected = value;
    prefs.set(AudioInputs.key, value);
    this.onChange?.();
  }

  get selectedDevice(): AudioInputDevice | null {
    if (this._selected === AudioInputs.systemDefault) return this.devices.find((d) => d.isDefault) ?? this.devices[0] ?? null;
    return this.devices.find((d) => d.id === this._selected) ?? null;
  }

  get selectionTitle() {
    if (this._selected === AudioInputs.systemDefault) return tr("系统默认");
    return this.selectedDevice?.name ?? tr("设备已断开");
  }

  async refresh() {
    try {
      this.devices = await invoke<AudioInputDevice[]>("audio_inputs");
    } catch {
      this.devices = [];
    }
    this.onChange?.();
  }
}

export const ClassroomMicPreference = {
  key: "lecturenote.classroomMic",
  get isOn() {
    return prefs.bool(this.key) ?? true;
  },
};
