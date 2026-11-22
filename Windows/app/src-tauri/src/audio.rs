//! Audio in: a microphone (cpal, WASAPI on Windows) or an audio file played as if live (to test
//! without speaking). Either way it comes out as 16 kHz mono f32 in 100 ms chunks, the engine's
//! format.

use anyhow::{anyhow, Context, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use serde::Serialize;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::mpsc::UnboundedSender;

pub const RATE: u32 = 16_000;
pub const CHUNK: usize = 1_600;

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct InputDevice {
    pub name: String,
    pub is_default: bool,
}

pub fn input_devices() -> Vec<InputDevice> {
    let host = cpal::default_host();
    let default = host.default_input_device().and_then(|d| d.name().ok());
    host.input_devices()
        .map(|devices| {
            devices
                .filter_map(|d| d.name().ok())
                .map(|name| InputDevice { is_default: Some(&name) == default.as_ref(), name })
                .collect()
        })
        .unwrap_or_default()
}

/// Turns any rate into 16 kHz. Each output sample is the average of the input it covers, which
/// also keeps sound above 8 kHz from folding back into speech.
pub struct Resampler {
    ratio: f64,
    position: f64,
    sum: f32,
    count: u32,
}

impl Resampler {
    pub fn new(from: u32) -> Self {
        Self { ratio: from as f64 / RATE as f64, position: 0.0, sum: 0.0, count: 0 }
    }

    pub fn push(&mut self, input: &[f32], out: &mut Vec<f32>) {
        if (self.ratio - 1.0).abs() < 1e-9 {
            out.extend_from_slice(input);
            return;
        }
        if self.ratio < 1.0 {
            // Upsampling (rare: an 8 kHz headset): repeat samples.
            for sample in input {
                self.position += 1.0 / self.ratio;
                while self.position >= 1.0 {
                    out.push(*sample);
                    self.position -= 1.0;
                }
            }
            return;
        }
        for sample in input {
            self.sum += sample;
            self.count += 1;
            self.position += 1.0;
            if self.position >= self.ratio {
                out.push(self.sum / self.count as f32);
                self.sum = 0.0;
                self.count = 0;
                self.position -= self.ratio;
            }
        }
    }
}

/// A running capture. Dropping it, or `stop()`, ends it.
pub struct Capture {
    stop: Arc<AtomicBool>,
    thread: Option<std::thread::JoinHandle<()>>,
    pub device_name: String,
}

impl Capture {
    pub fn stop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

impl Drop for Capture {
    fn drop(&mut self) {
        self.stop();
    }
}

/// Chunks of 16 kHz audio, 100 ms each, sent as they arrive.
fn chunker(sender: UnboundedSender<Vec<f32>>) -> impl FnMut(Vec<f32>) -> bool {
    let mut pending: Vec<f32> = Vec::with_capacity(CHUNK * 2);
    move |samples: Vec<f32>| {
        pending.extend(samples);
        while pending.len() >= CHUNK {
            let chunk: Vec<f32> = pending.drain(..CHUNK).collect();
            if sender.send(chunk).is_err() {
                return false;
            }
        }
        true
    }
}

pub fn start_microphone(name: &str, sender: UnboundedSender<Vec<f32>>) -> Result<Capture> {
    let host = cpal::default_host();
    let device = if name.is_empty() {
        host.default_input_device()
    } else {
        host.input_devices()?.find(|d| d.name().ok().as_deref() == Some(name)).or_else(|| host.default_input_device())
    }
    .ok_or_else(|| anyhow!("no microphone"))?;
    let device_name = device.name().unwrap_or_default();
    let config = device.default_input_config().context("reading the microphone's format")?;
    let stop = Arc::new(AtomicBool::new(false));
    let stop_thread = stop.clone();
    let (ready_tx, ready_rx) = std::sync::mpsc::channel::<Result<()>>();
    // cpal streams must stay on the thread that made them.
    let thread = std::thread::spawn(move || {
        let channels = config.channels() as usize;
        let rate = config.sample_rate().0;
        let (raw_tx, raw_rx) = std::sync::mpsc::channel::<Vec<f32>>();
        let error = |error| eprintln!("microphone: {error}");
        let stream_config: cpal::StreamConfig = config.clone().into();
        let mono = move |data: &[f32]| -> Vec<f32> {
            data.chunks(channels).map(|frame| frame.iter().sum::<f32>() / channels as f32).collect()
        };
        let stream = match config.sample_format() {
            cpal::SampleFormat::F32 => {
                let tx = raw_tx.clone();
                device.build_input_stream(&stream_config, move |data: &[f32], _| { let _ = tx.send(mono(data)); }, error, None)
            }
            cpal::SampleFormat::I16 => {
                let tx = raw_tx.clone();
                device.build_input_stream(
                    &stream_config,
                    move |data: &[i16], _| {
                        let floats: Vec<f32> = data.iter().map(|s| *s as f32 / 32_768.0).collect();
                        let _ = tx.send(mono(&floats));
                    },
                    error,
                    None,
                )
            }
            cpal::SampleFormat::U16 => {
                let tx = raw_tx.clone();
                device.build_input_stream(
                    &stream_config,
                    move |data: &[u16], _| {
                        let floats: Vec<f32> = data.iter().map(|s| (*s as f32 - 32_768.0) / 32_768.0).collect();
                        let _ = tx.send(mono(&floats));
                    },
                    error,
                    None,
                )
            }
            other => {
                let _ = ready_tx.send(Err(anyhow!("unsupported microphone format {other:?}")));
                return;
            }
        };
        let stream = match stream.map_err(anyhow::Error::from).and_then(|s| s.play().map(|_| s).map_err(Into::into)) {
            Ok(stream) => stream,
            Err(error) => {
                let _ = ready_tx.send(Err(error));
                return;
            }
        };
        let _ = ready_tx.send(Ok(()));
        let mut resampler = Resampler::new(rate);
        let mut send = chunker(sender);
        while !stop_thread.load(Ordering::SeqCst) {
            match raw_rx.recv_timeout(Duration::from_millis(100)) {
                Ok(raw) => {
                    let mut out = Vec::with_capacity(raw.len());
                    resampler.push(&raw, &mut out);
                    if !send(out) {
                        break;
                    }
                }
                Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
                Err(_) => break,
            }
        }
        drop(stream);
    });
    ready_rx.recv().map_err(|_| anyhow!("the microphone thread ended"))??;
    Ok(Capture { stop, thread: Some(thread), device_name })
}

/// Decodes a whole audio file to 16 kHz mono.
pub fn decode_file(path: &Path) -> Result<Vec<f32>> {
    use symphonia::core::audio::SampleBuffer;
    use symphonia::core::codecs::DecoderOptions;
    use symphonia::core::formats::FormatOptions;
    use symphonia::core::io::MediaSourceStream;
    use symphonia::core::meta::MetadataOptions;
    use symphonia::core::probe::Hint;

    let file = std::fs::File::open(path).with_context(|| format!("opening {}", path.display()))?;
    let stream = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(extension) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(extension);
    }
    let probed = symphonia::default::get_probe().format(&hint, stream, &FormatOptions::default(), &MetadataOptions::default())?;
    let mut format = probed.format;
    let track = format.default_track().ok_or_else(|| anyhow!("no audio track"))?.clone();
    let mut decoder = symphonia::default::get_codecs().make(&track.codec_params, &DecoderOptions::default())?;
    let rate = track.codec_params.sample_rate.ok_or_else(|| anyhow!("unknown sample rate"))?;
    let mut resampler = Resampler::new(rate);
    let mut out = Vec::new();
    loop {
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(symphonia::core::errors::Error::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(symphonia::core::errors::Error::ResetRequired) => break,
            Err(error) => return Err(error.into()),
        };
        if packet.track_id() != track.id {
            continue;
        }
        let decoded = match decoder.decode(&packet) {
            Ok(decoded) => decoded,
            Err(symphonia::core::errors::Error::DecodeError(_)) => continue,
            Err(error) => return Err(error.into()),
        };
        let spec = *decoded.spec();
        let channels = spec.channels.count().max(1);
        let mut buffer = SampleBuffer::<f32>::new(decoded.capacity() as u64, spec);
        buffer.copy_interleaved_ref(decoded);
        let mono: Vec<f32> = buffer.samples().chunks(channels).map(|f| f.iter().sum::<f32>() / channels as f32).collect();
        resampler.push(&mono, &mut out);
    }
    Ok(out)
}

/// Plays decoded audio into the session at live speed, as a microphone would deliver it.
pub fn start_file(path: &Path, sender: UnboundedSender<Vec<f32>>) -> Result<Capture> {
    let samples = decode_file(path)?;
    if samples.len() < RATE as usize {
        return Err(anyhow!("the file holds less than a second of audio"));
    }
    let stop = Arc::new(AtomicBool::new(false));
    let stop_thread = stop.clone();
    let device_name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let thread = std::thread::spawn(move || {
        let started = Instant::now();
        for (index, chunk) in samples.chunks(CHUNK).enumerate() {
            if stop_thread.load(Ordering::SeqCst) || sender.send(chunk.to_vec()).is_err() {
                break;
            }
            let due = started + Duration::from_secs_f64((index + 1) as f64 * CHUNK as f64 / RATE as f64);
            if let Some(wait) = due.checked_duration_since(Instant::now()) {
                std::thread::sleep(wait);
            }
        }
    });
    Ok(Capture { stop, thread: Some(thread), device_name })
}

#[cfg(test)]
mod tests {
    use super::Resampler;

    #[test]
    fn forty_eight_kilohertz_becomes_sixteen() {
        let mut resampler = Resampler::new(48_000);
        let mut out = Vec::new();
        resampler.push(&vec![0.5; 4_800], &mut out);
        assert_eq!(out.len(), 1_600);
        assert!(out.iter().all(|s| (s - 0.5).abs() < 1e-6));
    }

    #[test]
    fn forty_four_one_keeps_its_length_over_time() {
        let mut resampler = Resampler::new(44_100);
        let mut out = Vec::new();
        for _ in 0..10 {
            resampler.push(&vec![0.0; 4_410], &mut out);
        }
        assert!((out.len() as i64 - 16_000).abs() <= 1);
    }
}
