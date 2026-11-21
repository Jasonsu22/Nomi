//! Live speaker labels while recording, the Windows counterpart of the Mac's `StandardSpeakers`
//! (0.10): pyannote segmentation plus voiceprints, 5 s at a time, with voices matched across chunks
//! at a 0.5 bar. It runs through sherpa-onnx on the CPU, beside the speech model.
//!
//! Each 5 s chunk is split into voices by the segmentation model; each voice in the chunk gets a
//! voiceprint, which is matched to the voices heard so far or starts a new one.

use crate::voices::{my_voice::cosine, VoiceSpan};
use anyhow::{anyhow, Result};
use sherpa_rs::diarize::{Diarize, DiarizeConfig};
use sherpa_rs::speaker_id::{EmbeddingExtractor, ExtractorConfig};
use std::collections::BTreeMap;
use std::path::PathBuf;

pub const CHUNK_SECONDS: f64 = 5.0;
/// Voices at least this similar (cosine) are one person. The Mac's tested setting.
pub const MATCH: f32 = 0.5;
/// Less of one voice than this in a chunk is too little for a voiceprint.
const MINIMUM_PRINT_SECONDS: f64 = 0.5;

pub struct ModelFiles {
    pub segmentation: PathBuf,
    pub embedding: PathBuf,
}

pub fn files_for(kind: &str) -> Option<ModelFiles> {
    let model = crate::models::find(kind)?;
    if !crate::models::is_ready(&model) {
        return None;
    }
    Some(ModelFiles {
        segmentation: crate::models::file_path(&model.files[0]),
        embedding: crate::models::file_path(&model.files[1]),
    })
}

struct Voice {
    id: String,
    print: Vec<f32>,
    seconds: f64,
}

pub struct Tracker {
    diarize: Diarize,
    extractor: EmbeddingExtractor,
    buffer: Vec<f32>,
    consumed: f64,
    /// Where this run starts on the meeting's clock.
    offset: f64,
    tag: String,
    voices: Vec<Voice>,
    spans: Vec<VoiceSpan>,
}

impl Tracker {
    pub fn new(files: &ModelFiles, offset: f64, tag: &str) -> Result<Self> {
        let threads = std::thread::available_parallelism().map(|n| n.get().min(2)).unwrap_or(1);
        let diarize = Diarize::new(
            &files.segmentation,
            &files.embedding,
            DiarizeConfig { num_clusters: Some(-1), threshold: Some(0.5), min_duration_on: Some(0.3), min_duration_off: Some(0.5), provider: None, debug: false },
        )
        .map_err(|error| anyhow!("speaker model: {error}"))?;
        let extractor = EmbeddingExtractor::new(ExtractorConfig {
            model: files.embedding.to_string_lossy().into_owned(),
            provider: None,
            num_threads: Some(threads),
            debug: false,
        })
        .map_err(|error| anyhow!("voiceprint model: {error}"))?;
        Ok(Self { diarize, extractor, buffer: Vec::new(), consumed: 0.0, offset, tag: tag.to_string(), voices: Vec::new(), spans: Vec::new() })
    }

    /// Takes 16 kHz audio; returns every span so far when a chunk was processed.
    pub fn feed(&mut self, samples: &[f32]) -> Option<Vec<VoiceSpan>> {
        self.buffer.extend_from_slice(samples);
        let size = (CHUNK_SECONDS * 16_000.0) as usize;
        let mut changed = false;
        while self.buffer.len() >= size {
            let chunk: Vec<f32> = self.buffer.drain(..size).collect();
            self.process(chunk);
            self.consumed += CHUNK_SECONDS;
            changed = true;
        }
        changed.then(|| self.spans.clone())
    }

    /// The rest of the audio, at the end of a recording.
    pub fn finish(&mut self) -> Vec<VoiceSpan> {
        if self.buffer.len() >= 16_000 {
            let rest = std::mem::take(&mut self.buffer);
            self.process(rest);
        }
        self.spans.clone()
    }

    pub fn prints(&self) -> BTreeMap<String, Vec<f32>> {
        self.voices.iter().map(|voice| (voice.id.clone(), voice.print.clone())).collect()
    }

    fn process(&mut self, chunk: Vec<f32>) {
        let segments = match self.diarize.compute(chunk.clone(), None) {
            Ok(segments) => segments,
            // A chunk with no speech has no segments.
            Err(_) => return,
        };
        let mut local: BTreeMap<i32, Vec<(f64, f64)>> = BTreeMap::new();
        for segment in &segments {
            local.entry(segment.speaker).or_default().push((segment.start as f64, segment.end as f64));
        }
        for (_, ranges) in local {
            let audio: Vec<f32> = ranges
                .iter()
                .flat_map(|(start, end)| {
                    let a = ((start * 16_000.0) as usize).min(chunk.len());
                    let b = ((end * 16_000.0) as usize).min(chunk.len());
                    chunk[a..b].iter().copied()
                })
                .collect();
            let seconds = audio.len() as f64 / 16_000.0;
            let id = if seconds >= MINIMUM_PRINT_SECONDS {
                match self.extractor.compute_speaker_embedding(audio, 16_000) {
                    Ok(print) => self.assign(print, seconds),
                    Err(_) => continue,
                }
            } else {
                // Too short to tell; it joins the closest voice only if there is just one so far.
                match self.voices.as_slice() {
                    [only] => only.id.clone(),
                    _ => continue,
                }
            };
            for (start, end) in ranges {
                let base = self.offset + self.consumed;
                self.spans.push(VoiceSpan { start: base + start, end: base + end, speaker: id.clone() });
            }
        }
    }

    /// The voice this print belongs to; a new one when none is close enough.
    fn assign(&mut self, print: Vec<f32>, seconds: f64) -> String {
        let best = self
            .voices
            .iter_mut()
            .map(|voice| {
                let score = cosine(&voice.print, &print);
                (voice, score)
            })
            .max_by(|a, b| a.1.total_cmp(&b.1));
        if let Some((voice, score)) = best {
            if score >= MATCH {
                // The voice's print becomes the time-weighted average of everything it said.
                let weight = (seconds / (voice.seconds + seconds)) as f32;
                for (old, new) in voice.print.iter_mut().zip(&print) {
                    *old = *old * (1.0 - weight) + new * weight;
                }
                voice.seconds += seconds;
                return voice.id.clone();
            }
        }
        let id = format!("{}S{}", self.tag, self.voices.len() + 1);
        self.voices.push(Voice { id: id.clone(), print, seconds });
        id
    }
}
