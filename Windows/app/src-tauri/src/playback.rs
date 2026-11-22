//! "Play this moment" in a citation card: a stretch of the meeting's recordings, read sample-exact
//! from the WAV files (laid end to end on the meeting's clock) and played on the default output.

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use tauri::State;

use crate::platform::{text, Result};
use crate::AppState;

#[derive(Default)]
pub struct Player {
    stop: Mutex<Option<Arc<AtomicBool>>>,
}

/// The samples from `start` for `seconds`, across files.
fn read_moment(files: &[String], start: f64, seconds: f64) -> Vec<f32> {
    let rate = crate::audio::RATE as f64;
    let mut skip = (start.max(0.0) * rate) as usize;
    let mut want = (seconds.max(0.0) * rate) as usize;
    let mut out = Vec::with_capacity(want);
    for file in files {
        if want == 0 {
            break;
        }
        let path = std::path::Path::new(file);
        if let Ok(mut reader) = hound::WavReader::open(path) {
            let spec = reader.spec();
            let total = reader.duration() as usize;
            if spec.sample_rate == crate::audio::RATE && spec.channels == 1 {
                if skip >= total {
                    skip -= total;
                    continue;
                }
                let _ = reader.seek(skip as u32);
                skip = 0;
                let before = out.len();
                for sample in reader.samples::<i16>().take(want).flatten() {
                    out.push(sample as f32 / 32_768.0);
                }
                want -= (out.len() - before).min(want);
                continue;
            }
        }
        // Not Nomi's own format: decode it whole.
        let Ok(samples) = crate::audio::decode_file(path) else { continue };
        if skip >= samples.len() {
            skip -= samples.len();
            continue;
        }
        let take = (samples.len() - skip).min(want);
        out.extend_from_slice(&samples[skip..skip + take]);
        skip = 0;
        want -= take;
    }
    out
}

#[tauri::command]
pub async fn moment_play(state: State<'_, AppState>, files: Vec<String>, start: f64, seconds: f64) -> Result<Option<f64>> {
    if let Some(flag) = state.player.stop.lock().unwrap().take() {
        flag.store(true, Ordering::SeqCst);
    }
    let samples = tokio::task::spawn_blocking(move || read_moment(&files, start, seconds)).await.map_err(text)?;
    if samples.len() < 1_600 {
        return Ok(None);
    }
    let length = samples.len() as f64 / crate::audio::RATE as f64;
    let stop = Arc::new(AtomicBool::new(false));
    *state.player.stop.lock().unwrap() = Some(stop.clone());
    let (ready_tx, ready_rx) = std::sync::mpsc::channel::<std::result::Result<(), String>>();
    std::thread::spawn(move || {
        let host = cpal::default_host();
        let Some(device) = host.default_output_device() else {
            let _ = ready_tx.send(Err("no speaker".into()));
            return;
        };
        let Ok(config) = device.default_output_config() else {
            let _ = ready_tx.send(Err("no output format".into()));
            return;
        };
        let channels = config.channels() as usize;
        let rate = config.sample_rate().0 as f64;
        let step = crate::audio::RATE as f64 / rate;
        let position = Arc::new(Mutex::new(0.0f64));
        let done = Arc::new(AtomicBool::new(false));
        let (pos, finished, data) = (position.clone(), done.clone(), samples);
        let stop_cb = stop.clone();
        let next = move || -> f32 {
            let mut p = pos.lock().unwrap();
            let i = *p as usize;
            if i + 1 >= data.len() || stop_cb.load(Ordering::SeqCst) {
                finished.store(true, Ordering::SeqCst);
                return 0.0;
            }
            let frac = (*p - i as f64) as f32;
            let value = data[i] * (1.0 - frac) + data[i + 1] * frac;
            *p += step;
            value
        };
        let stream_config: cpal::StreamConfig = config.clone().into();
        let error = |e| eprintln!("playback: {e}");
        let stream = match config.sample_format() {
            cpal::SampleFormat::F32 => device.build_output_stream(
                &stream_config,
                move |out: &mut [f32], _| {
                    for frame in out.chunks_mut(channels) {
                        let v = next();
                        frame.iter_mut().for_each(|s| *s = v);
                    }
                },
                error,
                None,
            ),
            cpal::SampleFormat::I16 => device.build_output_stream(
                &stream_config,
                move |out: &mut [i16], _| {
                    for frame in out.chunks_mut(channels) {
                        let v = (next() * 32_767.0) as i16;
                        frame.iter_mut().for_each(|s| *s = v);
                    }
                },
                error,
                None,
            ),
            other => {
                let _ = ready_tx.send(Err(format!("unsupported output {other:?}")));
                return;
            }
        };
        let stream = match stream {
            Ok(s) => s,
            Err(e) => {
                let _ = ready_tx.send(Err(e.to_string()));
                return;
            }
        };
        if let Err(e) = stream.play() {
            let _ = ready_tx.send(Err(e.to_string()));
            return;
        }
        let _ = ready_tx.send(Ok(()));
        while !done.load(Ordering::SeqCst) && !stop.load(Ordering::SeqCst) {
            std::thread::sleep(std::time::Duration::from_millis(50));
        }
        drop(stream);
    });
    match ready_rx.recv() {
        Ok(Ok(())) => Ok(Some(length)),
        Ok(Err(e)) => Err(e),
        Err(_) => Err("playback ended".into()),
    }
}

#[tauri::command]
pub fn moment_stop(state: State<'_, AppState>) {
    if let Some(flag) = state.player.stop.lock().unwrap().take() {
        flag.store(true, Ordering::SeqCst);
    }
}
