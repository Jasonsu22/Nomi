#[derive(Debug, Clone)]
pub struct VadConfig {
    pub sample_rate: u32,
    pub frame_samples: usize,
    pub start_rms: f32,
    pub end_rms: f32,
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
}

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
        }
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
        let voiced = if self.speaking {
            rms >= self.config.end_rms
        } else {
            rms >= self.config.start_rms
        };
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
}
