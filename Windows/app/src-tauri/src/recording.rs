//! One recording run, the Windows side of the Mac's LocalEngine capture: the microphone goes to the
//! engine's WebSocket, to the run's WAV file and to the live speaker tracker. The engine's events
//! go back to the UI unchanged (`rec-event`); the transcript is built there, as on the Mac.
//!
//! The gate is the pause button: while it is shut, audio is dropped everywhere, so the file, the
//! transcript clock and the speaker spans all leave the pause out.

use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Emitter, State};
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;

use crate::audio::{self, Capture};
use crate::platform::{text, Result};
use crate::speakers::{ModelFiles, Tracker, VoiceSpan};
use crate::AppState;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenOptions {
    id: String,
    port: u16,
    token: String,
    /// The engine's `start` message, as the UI wrote it.
    start: String,
    device_id: Option<String>,
    recording_path: Option<String>,
    #[serde(default)]
    classroom: bool,
    /// {"segmentation": path, "embedding": path} when live speakers are on.
    speaker_model: Option<String>,
    #[serde(default)]
    speaker_offset: f64,
    #[serde(default)]
    speaker_tag: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Opened {
    device_name: String,
    fell_back: bool,
}

#[derive(Serialize, Clone)]
struct EventPayload {
    id: String,
    text: String,
}
#[derive(Serialize, Clone)]
struct LevelPayload {
    id: String,
    rms: f32,
}
#[derive(Serialize, Clone)]
struct ClosedPayload {
    id: String,
    message: Option<String>,
}
#[derive(Serialize, Clone)]
pub struct SpeakersPayload {
    id: String,
    spans: Vec<VoiceSpan>,
    prints: BTreeMap<String, Vec<f32>>,
}

#[derive(Serialize, Clone)]
pub struct SpeakerResult {
    spans: Vec<VoiceSpan>,
    prints: BTreeMap<String, Vec<f32>>,
}

type Wav = hound::WavWriter<std::io::BufWriter<std::fs::File>>;

pub struct Recording {
    gate: Arc<AtomicBool>,
    capture: Option<Capture>,
    control: mpsc::UnboundedSender<Message>,
    wav: Arc<Mutex<Option<Wav>>>,
    speaker_feed: Option<std::sync::mpsc::Sender<Vec<f32>>>,
    speakers: Option<std::thread::JoinHandle<Option<Tracker>>>,
}

impl Recording {
    fn stop_microphone(&mut self) {
        self.gate.store(false, Ordering::SeqCst);
        if let Some(mut capture) = self.capture.take() {
            capture.stop();
        }
        if let Some(wav) = self.wav.lock().unwrap().take() {
            let _ = wav.finalize();
        }
    }
}

impl Drop for Recording {
    fn drop(&mut self) {
        self.stop_microphone();
        let _ = self.control.send(Message::Close(None));
    }
}

fn bytes(samples: &[f32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(samples.len() * 4);
    for s in samples {
        out.extend_from_slice(&s.to_le_bytes());
    }
    out
}

fn rms(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    (samples.iter().map(|s| s * s).sum::<f32>() / samples.len() as f32).sqrt()
}

/// Classroom microphone: a gentle high-pass for desk and air-conditioning rumble, and an automatic
/// gain that brings a distant teacher up without pumping the room noise.
struct Classroom {
    previous_in: f32,
    previous_out: f32,
    gain: f32,
}

impl Classroom {
    fn new() -> Self {
        Self { previous_in: 0.0, previous_out: 0.0, gain: 1.0 }
    }

    fn process(&mut self, chunk: &mut [f32]) {
        // One-pole high-pass at about 100 Hz.
        let a = 0.962_f32;
        for s in chunk.iter_mut() {
            let y = a * (self.previous_out + *s - self.previous_in);
            self.previous_in = *s;
            self.previous_out = y;
            *s = y;
        }
        let level = rms(chunk);
        // Only speech-like levels move the gain; silence keeps it.
        if level > 0.004 {
            let wanted = (0.08 / level).clamp(1.0, 6.0);
            let rate = if wanted < self.gain { 0.5 } else { 0.05 };
            self.gain += (wanted - self.gain) * rate;
        }
        for s in chunk.iter_mut() {
            *s = (*s * self.gain).clamp(-1.0, 1.0);
        }
    }
}

fn start_capture(device: Option<&str>, sender: mpsc::UnboundedSender<Vec<f32>>) -> anyhow::Result<(Capture, bool)> {
    // Development and tests: replay a file as if it were the microphone.
    if let Ok(file) = std::env::var("NOMI_TEST_AUDIO") {
        return Ok((audio::start_file(std::path::Path::new(&file), sender)?, false));
    }
    let wanted = device.unwrap_or("");
    let present = wanted.is_empty() || audio::input_devices().iter().any(|d| d.name == wanted);
    let capture = audio::start_microphone(if present { wanted } else { "" }, sender)?;
    Ok((capture, !present))
}

#[tauri::command]
pub async fn recording_open(app: AppHandle, state: State<'_, AppState>, options: OpenOptions) -> Result<Opened> {
    let id = options.id.clone();
    let mut request = format!("ws://127.0.0.1:{}/v1/session", options.port).into_client_request().map_err(text)?;
    request.headers_mut().insert("Authorization", format!("Bearer {}", options.token).parse().map_err(text)?);
    let (socket, _) = tokio_tungstenite::connect_async(request).await.map_err(|e| format!("engine: {e}"))?;
    let (mut sink, mut stream) = socket.split();
    sink.send(Message::Text(options.start.clone().into())).await.map_err(text)?;

    // Outgoing: audio and control messages share one writer.
    let (control, mut control_rx) = mpsc::unbounded_channel::<Message>();
    tauri::async_runtime::spawn(async move {
        while let Some(message) = control_rx.recv().await {
            let close = matches!(message, Message::Close(_));
            if sink.send(message).await.is_err() || close {
                break;
            }
        }
    });

    // Incoming: the engine's events, passed through.
    {
        let app = app.clone();
        let id = id.clone();
        tauri::async_runtime::spawn(async move {
            let mut message_out: Option<String> = None;
            while let Some(next) = stream.next().await {
                match next {
                    Ok(Message::Text(text)) => {
                        let _ = app.emit("rec-event", EventPayload { id: id.clone(), text: text.to_string() });
                    }
                    Ok(Message::Close(_)) => break,
                    Ok(_) => {}
                    Err(error) => {
                        message_out = Some(error.to_string());
                        break;
                    }
                }
            }
            let _ = app.emit("rec-closed", ClosedPayload { id, message: message_out });
        });
    }

    // Speakers run on their own thread; the model needs a few milliseconds per second of audio.
    let files: Option<ModelFiles> = options.speaker_model.as_deref().and_then(|json| serde_json::from_str::<serde_json::Value>(json).ok()).and_then(|v| {
        Some(ModelFiles { segmentation: v["segmentation"].as_str()?.into(), embedding: v["embedding"].as_str()?.into() })
    });
    let (speaker_feed, speakers) = match files {
        Some(files) => {
            let (tx, rx) = std::sync::mpsc::channel::<Vec<f32>>();
            let app = app.clone();
            let id = id.clone();
            let offset = options.speaker_offset;
            let tag = options.speaker_tag.clone();
            let thread = std::thread::spawn(move || {
                let mut tracker = Tracker::new(&files, offset, &tag, crate::speakers::CHUNK_SECONDS).ok()?;
                while let Ok(chunk) = rx.recv() {
                    if let Some(spans) = tracker.feed(&chunk) {
                        let _ = app.emit("speaker-update", SpeakersPayload { id: id.clone(), spans, prints: tracker.prints() });
                    }
                }
                Some(tracker)
            });
            (Some(tx), Some(thread))
        }
        None => (None, None),
    };

    let wav = Arc::new(Mutex::new(match options.recording_path.as_deref() {
        Some(path) => {
            if let Some(parent) = std::path::Path::new(path).parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            let spec = hound::WavSpec { channels: 1, sample_rate: audio::RATE, bits_per_sample: 16, sample_format: hound::SampleFormat::Int };
            hound::WavWriter::create(path, spec).ok()
        }
        None => None,
    }));

    let (audio_tx, mut audio_rx) = mpsc::unbounded_channel::<Vec<f32>>();
    let (capture, fell_back) = match start_capture(options.device_id.as_deref(), audio_tx) {
        Ok(parts) => parts,
        Err(error) => {
            let _ = control.send(Message::Close(None));
            return Err(format!("microphone: {error}"));
        }
    };
    let device_name = capture.device_name.clone();
    let gate = Arc::new(AtomicBool::new(false));

    // Audio fan-out: engine, WAV file, speakers, level meter.
    {
        let gate = gate.clone();
        let control = control.clone();
        let feed = speaker_feed.clone();
        let wav = wav.clone();
        let app = app.clone();
        let id = id.clone();
        let mut classroom = options.classroom.then(Classroom::new);
        tauri::async_runtime::spawn(async move {
            let mut since_flush = 0usize;
            let mut got_audio = false;
            while let Some(mut chunk) = audio_rx.recv().await {
                got_audio = true;
                if !gate.load(Ordering::SeqCst) {
                    continue;
                }
                if let Some(c) = classroom.as_mut() {
                    c.process(&mut chunk);
                }
                let _ = app.emit("rec-level", LevelPayload { id: id.clone(), rms: rms(&chunk) });
                if let Some(writer) = wav.lock().unwrap().as_mut() {
                    for s in &chunk {
                        let _ = writer.write_sample((s.clamp(-1.0, 1.0) * 32_767.0) as i16);
                    }
                    since_flush += chunk.len();
                    // Keep the header current, so a crash leaves a playable file.
                    if since_flush >= audio::RATE as usize * 10 {
                        let _ = writer.flush();
                        since_flush = 0;
                    }
                }
                if let Some(feed) = &feed {
                    let _ = feed.send(chunk.clone());
                }
                if control.send(Message::Binary(bytes(&chunk).into())).is_err() {
                    break;
                }
            }
            // The capture ended while the gate was still open: the device went away.
            if gate.load(Ordering::SeqCst) && std::env::var("NOMI_TEST_AUDIO").is_err() {
                let message = if got_audio { "麦克风已断开" } else { "打不开麦克风" };
                let _ = app.emit("rec-mic-failed", serde_json::json!({ "id": id, "message": message }));
            }
        });
    }

    let recording = Recording { gate, capture: Some(capture), control, wav, speaker_feed, speakers };
    state.recordings.lock().unwrap().insert(id, recording);
    Ok(Opened { device_name, fell_back })
}

#[tauri::command]
pub fn recording_gate(state: State<'_, AppState>, id: String, open: bool) {
    if let Some(r) = state.recordings.lock().unwrap().get(&id) {
        r.gate.store(open, Ordering::SeqCst);
    }
}

#[tauri::command]
pub fn recording_send(state: State<'_, AppState>, id: String, text: String) -> Result<()> {
    let recordings = state.recordings.lock().unwrap();
    let r = recordings.get(&id).ok_or("no such recording")?;
    r.control.send(Message::Text(text.into())).map_err(|_| "the engine connection closed".to_string())
}

#[tauri::command]
pub fn recording_stop_mic(state: State<'_, AppState>, id: String) {
    if let Some(r) = state.recordings.lock().unwrap().get_mut(&id) {
        r.stop_microphone();
        // The tracker finishes what it has once its feed closes.
        r.speaker_feed = None;
    }
}

#[tauri::command]
pub fn recording_close(state: State<'_, AppState>, id: String) {
    let removed = state.recordings.lock().unwrap().remove(&id);
    drop(removed);
}

/// Everything the live speaker model heard in this run, the rest of the audio included.
#[tauri::command]
pub async fn speakers_finish(state: State<'_, AppState>, id: String) -> Result<Option<SpeakerResult>> {
    let thread = {
        let mut recordings = state.recordings.lock().unwrap();
        let Some(r) = recordings.get_mut(&id) else { return Ok(None) };
        r.speaker_feed = None;
        r.speakers.take()
    };
    let Some(thread) = thread else { return Ok(None) };
    let tracker = tokio::task::spawn_blocking(move || thread.join().ok().flatten()).await.map_err(text)?;
    Ok(tracker.map(|mut t| {
        let spans = t.finish();
        SpeakerResult { spans, prints: t.prints() }
    }))
}

/// Who spoke when in a finished meeting's recordings (Settings' speaker model), for "Find
/// speakers". The files are one after another on the meeting's clock.
#[tauri::command]
pub async fn voices_analyze(files: Vec<String>, segmentation: String, embedding: String) -> Result<SpeakerResult> {
    tokio::task::spawn_blocking(move || {
        let model = ModelFiles { segmentation: segmentation.into(), embedding: embedding.into() };
        let mut tracker = Tracker::new(&model, 0.0, "", 20.0).map_err(text)?;
        for file in files {
            let Ok(samples) = audio::decode_file(std::path::Path::new(&file)) else { continue };
            for chunk in samples.chunks(audio::RATE as usize * 20) {
                tracker.feed(chunk);
            }
        }
        let spans = tracker.finish();
        Ok(SpeakerResult { spans, prints: tracker.prints() })
    })
    .await
    .map_err(text)?
}

#[tauri::command]
pub fn audio_inputs() -> Vec<serde_json::Value> {
    audio::input_devices().into_iter().map(|d| serde_json::json!({ "id": d.name, "name": d.name, "isDefault": d.is_default })).collect()
}
