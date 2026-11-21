// Live/SessionState.swift and Live/LevelMeter.swift
export type SessionPhase = "idle" | "preparing" | "listening" | "stopping";

export class SessionState {
  phase: SessionPhase = "idle";
  isPaused = false;
  private accumulated = 0;
  private runningSince: number | null = null;

  get elapsed(): number {
    if (this.runningSince === null || this.phase !== "listening" || this.isPaused) return this.accumulated;
    return this.accumulated + (performance.now() - this.runningSince) / 1000;
  }

  begin(offset = 0) {
    this.phase = "preparing";
    this.isPaused = false;
    this.accumulated = Math.max(0, offset);
    this.runningSince = null;
  }

  markListening() {
    this.phase = "listening";
    this.isPaused = false;
    this.runningSince = performance.now();
  }

  togglePause() {
    if (this.phase !== "listening") return;
    if (this.isPaused) {
      this.isPaused = false;
      this.runningSince = performance.now();
    } else {
      this.accumulated = this.elapsed;
      this.isPaused = true;
      this.runningSince = null;
    }
  }

  beginStopping(): number {
    this.accumulated = this.elapsed;
    this.runningSince = null;
    this.isPaused = false;
    this.phase = "stopping";
    return this.accumulated;
  }

  markIdle() {
    this.phase = "idle";
    this.isPaused = false;
    this.runningSince = null;
  }
}

/** About two seconds of loudness, for the dot waveform. */
export class LevelHistory {
  static shift = 0.05;
  static rest = 0.2;
  private entries: { time: number; level: number }[] = [];

  record(rms: number, time: number) {
    this.entries.push({ time, level: Math.min(1, Math.max(LevelHistory.rest, rms)) });
    const cutoff = time - 2;
    const keep = this.entries.findIndex((e) => e.time >= cutoff);
    if (keep > 0) this.entries.splice(0, keep);
  }

  columnLevel(index: number, count: number, time: number, reduceMotion: boolean): number {
    const sampleTime = time - (count - 1 - index) * LevelHistory.shift;
    const target = this.value(sampleTime);
    if (reduceMotion) return target;
    const bucket = Math.floor(sampleTime / LevelHistory.shift) * LevelHistory.shift;
    const previous = this.value(bucket - 0.0001);
    const fraction = Math.min(1, Math.max(0, (sampleTime - bucket) / LevelHistory.shift));
    const progress = 1 - Math.pow(0.65, fraction * 0.05 * 60);
    return previous + (target - previous) * progress;
  }

  private value(time: number): number {
    let result = LevelHistory.rest;
    for (const e of this.entries) if (e.time <= time) result = e.level;
    return result;
  }
}

export class LevelMeter {
  history = new LevelHistory();
  rms = 0;

  recordMicrophoneRMS(value: number) {
    const decibels = 20 * Math.log10(Math.max(value, 0.000001));
    this.rms = Math.min(1, Math.max(0, (decibels + 65) / 45));
    this.history.record(this.rms, performance.now() / 1000);
  }

  columnLevel(index: number, count: number, time: number, reduceMotion: boolean) {
    return this.history.columnLevel(index, count, time, reduceMotion);
  }
}
