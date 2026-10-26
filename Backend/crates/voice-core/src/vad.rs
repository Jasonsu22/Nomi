#[derive(Debug, Clone)]
pub struct VadConfig {
    pub sample_rate: u32,
    pub frame_samples: usize,
    /// The loudest the start and end levels can be; quiet rooms lower them (see `noise_floor`).
    pub start_rms: f32,
    pub end_rms: f32,
    /// The quietest the start and end levels can be, so hiss alone never opens a phrase.
    pub min_start_rms: f32,
    pub min_end_rms: f32,
    /// Speech must be this many times louder than the background to start, and to continue.
    pub start_over_floor: f32,
    pub end_over_floor: f32,
    pub start_frames: usize,
    pub end_silence_samples: usize,
    pub min_segment_samples: usize,
    pub max_segment_samples: usize,
    pub progressive_samples: usize,
}

impl Default for VadConfig {
    fn default() -> Self {
        let rate = 16_000usize;
        Self {
            sample_rate: 16_000,
            frame_samples: rate / 50,
            start_rms: 0.018,
            end_rms: 0.010,
            min_start_rms: 0.0045,
            min_end_rms: 0.0028,
            // About 7.6 dB over the room to start and 3.5 dB to keep going. A laptop across a
            // classroom hears speech only 8-10 dB over the room, which a stricter gate mostly missed.
            start_over_floor: 2.4,
            end_over_floor: 1.5,
            start_frames: 5,
            end_silence_samples: rate * 420 / 1000,
            min_segment_samples: rate * 420 / 1000,
            max_segment_samples: rate * 8,
            progressive_samples: rate * 1500 / 1000,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct VadOutput {
    pub burst_id: u64,
    pub samples: Vec<f32>,
    pub start: f64,
    pub end: f64,
    pub is_final: bool,
    pub hit_limit: bool,
}

#[derive(Debug)]
pub struct Vad {
    config: VadConfig,
    pending: Vec<f32>,
    cursor_samples: usize,
    speaking: bool,
    voiced_run: usize,
    silence_samples: usize,
    segment: Vec<f32>,
    segment_start: usize,
    burst_id: u64,
    samples_since_partial: usize,
    /// Background level, from quiet frames. It drops quickly and rises slowly, so a teacher
    /// far from the microphone still clears it while a fan or room tone does not.
    noise_floor: f32,
}

/// Lowest background level assumed, so digital silence cannot make every sound "speech".
const FLOOR_MIN: f32 = 0.0008;
const FLOOR_START: f32 = 0.003;

impl Vad {
    pub fn new(config: VadConfig) -> Self {
        Self {
            config,
            pending: Vec::new(),
            cursor_samples: 0,
            speaking: false,
            voiced_run: 0,
            silence_samples: 0,
            segment: Vec::new(),
            segment_start: 0,
            burst_id: 1,
            samples_since_partial: 0,
            noise_floor: FLOOR_START,
        }
    }

    /// The current background level estimate, as RMS.
    pub fn noise_floor(&self) -> f32 {
        self.noise_floor
    }

    /// The start and end levels for the current background.
    pub fn thresholds(&self) -> (f32, f32) {
        let c = &self.config;
        let start = (self.noise_floor * c.start_over_floor).clamp(c.min_start_rms, c.start_rms);
        let end = (self.noise_floor * c.end_over_floor).clamp(c.min_end_rms, c.end_rms);
        (start, end)
    }

    fn track_floor(&mut self, rms: f32) {
        // Per 20 ms frame: follow quiet frames down within a few frames, rise about 0.9 dB/s, so a
        // noisy room stops opening phrases within seconds while gaps between words keep it low.
        self.noise_floor = if rms < self.noise_floor {
            self.noise_floor * 0.9 + rms * 0.1
        } else {
            self.noise_floor * 1.002
        }
        .max(FLOOR_MIN);
    }

    pub fn push(&mut self, samples: &[f32]) -> Vec<VadOutput> {
        self.pending.extend_from_slice(samples);
        let mut outputs = Vec::new();
        let frame = self.config.frame_samples;
        while self.pending.len() >= frame {
            let chunk: Vec<f32> = self.pending.drain(..frame).collect();
            if let Some(output) = self.push_frame(&chunk) {
                outputs.push(output);
            }
        }
        outputs
    }

    pub fn finish(&mut self) -> Option<VadOutput> {
        if !self.pending.is_empty() {
            let rest = std::mem::take(&mut self.pending);
            let _ = self.push_frame(&rest);
        }
        if self.speaking && self.segment.len() >= self.config.min_segment_samples {
            return Some(self.emit(true, false));
        }
        self.speaking = false;
        self.segment.clear();
        None
    }

    fn push_frame(&mut self, frame: &[f32]) -> Option<VadOutput> {
        let rms = rms(frame);
        let (start_rms, end_rms) = self.thresholds();
        let voiced = if self.speaking { rms >= end_rms } else { rms >= start_rms };
        self.track_floor(rms);
        self.cursor_samples += frame.len();

        if !self.speaking {
            if voiced {
                self.voiced_run += 1;
                self.segment.extend_from_slice(frame);
                if self.voiced_run >= self.config.start_frames {
                    self.speaking = true;
                    self.silence_samples = 0;
                    self.samples_since_partial = self.segment.len();
                    self.segment_start = self.cursor_samples.saturating_sub(self.segment.len());
                }
            } else {
                self.voiced_run = 0;
                self.segment.clear();
            }
            return None;
        }

        self.segment.extend_from_slice(frame);
        if voiced {
            self.silence_samples = 0;
        } else {
            self.silence_samples += frame.len();
        }

        if self.segment.len() >= self.config.max_segment_samples {
            return Some(self.emit(true, true));
        }
        if self.silence_samples >= self.config.end_silence_samples
            && self.segment.len() >= self.config.min_segment_samples
        {
            return Some(self.emit(true, false));
        }
        self.samples_since_partial += frame.len();
        if self.samples_since_partial >= self.config.progressive_samples {
            self.samples_since_partial = 0;
            return Some(self.emit(false, false));
        }
        None
    }

    fn emit(&mut self, is_final: bool, hit_limit: bool) -> VadOutput {
        let output = VadOutput {
            burst_id: self.burst_id,
            samples: self.segment.clone(),
            start: self.segment_start as f64 / self.config.sample_rate as f64,
            end: self.cursor_samples as f64 / self.config.sample_rate as f64,
            is_final,
            hit_limit,
        };
        if is_final {
            self.speaking = false;
            self.voiced_run = 0;
            self.silence_samples = 0;
            self.segment.clear();
            self.samples_since_partial = 0;
            self.burst_id += 1;
        }
        output
    }
}

fn rms(frame: &[f32]) -> f32 {
    if frame.is_empty() {
        return 0.0;
    }
    let energy = frame.iter().map(|sample| sample * sample).sum::<f32>() / frame.len() as f32;
    energy.sqrt()
}

#[cfg(test)]
mod tests {
    use super::{Vad, VadConfig};

    #[test]
    fn a_tone_followed_by_silence_becomes_one_final_segment() {
        let mut vad = Vad::new(VadConfig::default());
        let tone = vec![0.2f32; 16_000];
        let silence = vec![0.0f32; 8_000];
        let mut outputs = vad.push(&tone);
        outputs.extend(vad.push(&silence));
        let finals: Vec<_> = outputs.iter().filter(|item| item.is_final).collect();
        assert_eq!(finals.len(), 1);
        assert!(finals[0].samples.len() > 8_000);
    }

    /// A voice -38 dB from a quiet room, the level of a teacher far from a laptop.
    #[test]
    fn quiet_speech_over_a_quiet_room_still_opens_a_phrase() {
        let mut vad = Vad::new(VadConfig::default());
        let room = vec![0.0015f32; 32_000];
        let voice: Vec<f32> = (0..32_000).map(|i| 0.0125 * (i as f32 * 0.05).sin().signum()).collect();
        let mut outputs = vad.push(&room);
        outputs.extend(vad.push(&voice));
        outputs.extend(vad.push(&room));
        assert!(outputs.iter().any(|item| item.is_final), "quiet speech should produce a phrase");
    }

    #[test]
    fn steady_background_noise_never_opens_a_phrase() {
        let mut vad = Vad::new(VadConfig::default());
        let mut state = 7u32;
        let noise: Vec<f32> = (0..16_000 * 30)
            .map(|_| {
                state = state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                ((state >> 8) as f32 / (1u32 << 24) as f32 - 0.5) * 0.02
            })
            .collect();
        let outputs = vad.push(&noise);
        assert!(outputs.is_empty(), "room noise alone should not become speech");
    }

    #[test]
    fn loud_rooms_keep_the_original_levels() {
        let mut vad = Vad::new(VadConfig::default());
        vad.push(&vec![0.05f32; 16_000 * 20]);
        let (start, end) = vad.thresholds();
        assert_eq!((start, end), (0.018, 0.010));
    }
}
