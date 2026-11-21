//! One recording. Audio (microphone or file) goes three ways: to the engine's WebSocket for text,
//! to `audio-1.wav` in the meeting's folder, and to the live speaker tracker. The engine's events
//! build the transcript here, in Rust, so what is saved is exactly what was shown.

use crate::audio::{self, Capture};
use crate::speakers::{self, Tracker};
use crate::store::{self, Meeting};
use crate::transcript::{Commit, LiveTranscript, Paragraph};
use crate::voices::{labels, my_voice, VoiceName, VoiceSpan};
use anyhow::{anyhow, Result};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter};
use tokio::sync::{mpsc, oneshot};
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;

#[derive(Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct StartOptions {
    pub title: String,
    /// microphone or file.
    pub input: String,
    #[serde(default)]
    pub device: String,
    #[serde(default)]
    pub file: Option<PathBuf>,
    pub source_language: String,
    pub target_language: String,
}

/// What the live page shows, sent whenever the transcript changes.
#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct LiveUpdate {
    pub meeting_id: String,
    pub title: String,
    pub paragraphs: Vec<Paragraph>,
    pub speaker_names: BTreeMap<String, VoiceName>,
    pub elapsed: f64,
    /// listening, stopping, saving or done.
    pub state: String,
    pub asr: String,
    pub translator: String,
    pub input_name: String,
    pub speakers_on: bool,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct LiveNotice {
    pub code: String,
    pub message: String,
}

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum EngineEvent {
    State { value: String, asr: String, translator: String },
    Tail { text: String, start: f64 },
    Commit { id: i64, source: String, translation: String, start: f64, end: f64, tail: String },
    Level { rms: f32 },
    Error { code: String, message: String },
}

struct Live {
    meeting: Meeting,
    transcript: LiveTranscript,
    spans: Vec<VoiceSpan>,
    prints: BTreeMap<String, Vec<f32>>,
    started: Instant,
    state: String,
    asr: String,
    translator: String,
    input_name: String,
    speakers_on: bool,
    audio_seconds: f64,
}

impl Live {
    fn update(&self) -> LiveUpdate {
        let speaker_names = labels::merging(None, self.spans.clone(), self.prints.clone(), 0.0)
            .map(|(voices, _)| voices.all_names())
            .unwrap_or_default();
        LiveUpdate {
            meeting_id: self.meeting.id.clone(),
            title: self.meeting.title.clone(),
            paragraphs: self.transcript.paragraphs().to_vec(),
            speaker_names,
            elapsed: self.started.elapsed().as_secs_f64(),
            state: self.state.clone(),
            asr: self.asr.clone(),
            translator: self.translator.clone(),
            input_name: self.input_name.clone(),
            speakers_on: self.speakers_on,
        }
    }
}

pub struct Session {
    live: Arc<Mutex<Live>>,
    capture: Option<Capture>,
    control: mpsc::UnboundedSender<Message>,
    finished: Option<oneshot::Receiver<()>>,
    speakers: Option<std::thread::JoinHandle<Option<Tracker>>>,
    speaker_feed: Option<std::sync::mpsc::Sender<Vec<f32>>>,
    pump: Option<tauri::async_runtime::JoinHandle<()>>,
}

pub fn meeting_title(given: &str) -> String {
    if !given.trim().is_empty() {
        return given.trim().to_string();
    }
    "Lecture".to_string()
}

impl Session {
    pub async fn start(app: AppHandle, port: u16, token: String, options: StartOptions, settings: crate::settings::Settings) -> Result<Self> {
        let id = store::new_id();
        let folder = crate::paths::meeting_dir(&id);
        std::fs::create_dir_all(&folder)?;

        let mut request = format!("ws://127.0.0.1:{port}/v1/session").into_client_request()?;
        request.headers_mut().insert("Authorization", format!("Bearer {token}").parse()?);
        let (socket, _) = tokio_tungstenite::connect_async(request).await.map_err(|error| anyhow!("connecting to the engine: {error}"))?;
        let (mut sink, mut stream) = socket.split();
        let start = serde_json::json!({
            "type": "start",
            "sourceLanguage": options.source_language,
            "targetLanguage": options.target_language,
            "context": options.title,
        });
        sink.send(Message::Text(start.to_string().into())).await?;

        let (audio_tx, mut audio_rx) = mpsc::unbounded_channel::<Vec<f32>>();
        let capture = match options.input.as_str() {
            "file" => audio::start_file(options.file.as_deref().ok_or_else(|| anyhow!("choose an audio file"))?, audio_tx)?,
            _ => audio::start_microphone(&options.device, audio_tx)?,
        };

        let meeting = Meeting {
            id: id.clone(),
            title: meeting_title(&options.title),
            started_at: store::now_reference(),
            duration: 0.0,
            source: "microphone".into(),
            source_language: options.source_language.clone(),
            target_language: options.target_language.clone(),
            category_id: None,
            paragraphs: Vec::new(),
            is_live: true,
            input_device_name: Some(capture.device_name.clone()),
            audio_files: Some(vec!["audio-1.wav".into()]),
            assistant: None,
            voices: None,
            hidden_speakers: None,
        };
        save_meeting(&meeting);

        let speaker_files = if settings.live_speakers { speakers::files_for(&settings.speaker_model) } else { None };
        let live = Arc::new(Mutex::new(Live {
            transcript: LiveTranscript::new(&options.source_language, Vec::new(), 0.0),
            meeting,
            spans: Vec::new(),
            prints: BTreeMap::new(),
            started: Instant::now(),
            state: "listening".into(),
            asr: String::new(),
            translator: String::new(),
            input_name: capture.device_name.clone(),
            speakers_on: speaker_files.is_some(),
            audio_seconds: 0.0,
        }));

        // Speakers run on their own thread; the model is a few milliseconds per second of audio.
        let (speaker_feed, speakers) = match speaker_files {
            Some(files) => {
                let (tx, rx) = std::sync::mpsc::channel::<Vec<f32>>();
                let live = live.clone();
                let app = app.clone();
                let thread = std::thread::spawn(move || {
                    let mut tracker = match Tracker::new(&files, 0.0, "") {
                        Ok(tracker) => tracker,
                        Err(error) => {
                            let _ = app.emit("live-notice", LiveNotice { code: "speakers_failed".into(), message: error.to_string() });
                            return None;
                        }
                    };
                    while let Ok(chunk) = rx.recv() {
                        if let Some(spans) = tracker.feed(&chunk) {
                            let prints = tracker.prints();
                            let update = {
                                let mut live = live.lock().unwrap();
                                labels::apply(&spans, live.transcript.paragraphs_mut());
                                live.spans = spans;
                                live.prints = prints;
                                live.update()
                            };
                            let _ = app.emit("live-update", update);
                        }
                    }
                    Some(tracker)
                });
                (Some(tx), Some(thread))
            }
            None => (None, None),
        };

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

        // Audio fan-out: engine, WAV file, speakers.
        let pump = {
            let control = control.clone();
            let speaker_feed = speaker_feed.clone();
            let live = live.clone();
            let wav_path = folder.join("audio-1.wav");
            tauri::async_runtime::spawn(async move {
                let spec = hound::WavSpec { channels: 1, sample_rate: audio::RATE, bits_per_sample: 16, sample_format: hound::SampleFormat::Int };
                let mut wav = hound::WavWriter::create(&wav_path, spec).ok();
                let mut since_flush = 0usize;
                while let Some(chunk) = audio_rx.recv().await {
                    if let Some(writer) = wav.as_mut() {
                        for sample in &chunk {
                            let _ = writer.write_sample((sample.clamp(-1.0, 1.0) * 32_767.0) as i16);
                        }
                        since_flush += chunk.len();
                        // Keep the header current, so a crash leaves a playable file.
                        if since_flush >= 16_000 * 10 {
                            let _ = writer.flush();
                            since_flush = 0;
                        }
                    }
                    if let Some(feed) = &speaker_feed {
                        let _ = feed.send(chunk.clone());
                    }
                    live.lock().unwrap().audio_seconds += chunk.len() as f64 / audio::RATE as f64;
                    if control.send(Message::Binary(voice_core_bytes(&chunk).into())).is_err() {
                        break;
                    }
                }
                if let Some(writer) = wav {
                    let _ = writer.finalize();
                }
            })
        };

        // Incoming: engine events build the transcript.
        let (done_tx, done_rx) = oneshot::channel::<()>();
        {
            let live = live.clone();
            let app = app.clone();
            tauri::async_runtime::spawn(async move {
                let mut last_save = Instant::now();
                while let Some(Ok(message)) = stream.next().await {
                    let Message::Text(text) = message else { continue };
                    let Ok(event) = serde_json::from_str::<EngineEvent>(&text) else { continue };
                    match event {
                        EngineEvent::Level { rms } => {
                            let _ = app.emit("live-level", rms);
                        }
                        EngineEvent::Error { code, message } => {
                            let _ = app.emit("live-notice", LiveNotice { code, message });
                        }
                        EngineEvent::State { value, asr, translator } => {
                            let update = {
                                let mut live = live.lock().unwrap();
                                live.asr = asr;
                                live.translator = translator;
                                if value != "idle" {
                                    live.state = value.clone();
                                }
                                live.update()
                            };
                            let _ = app.emit("live-update", update);
                            if value == "idle" {
                                break;
                            }
                        }
                        EngineEvent::Tail { text, start } => {
                            let update = {
                                let mut live = live.lock().unwrap();
                                live.transcript.apply_tail(&text, start);
                                live.update()
                            };
                            let _ = app.emit("live-update", update);
                        }
                        EngineEvent::Commit { id, source, translation, start, end, tail } => {
                            let update = {
                                let mut live = live.lock().unwrap();
                                live.transcript.apply_commit(Commit { id, source, translation, start, end, speaker: None }, &tail);
                                let spans = live.spans.clone();
                                if !spans.is_empty() {
                                    labels::apply(&spans, live.transcript.paragraphs_mut());
                                }
                                if last_save.elapsed() >= Duration::from_secs(30) {
                                    last_save = Instant::now();
                                    let mut meeting = live.meeting.clone();
                                    meeting.paragraphs = live.transcript.paragraphs().to_vec();
                                    meeting.duration = live.audio_seconds;
                                    save_meeting(&meeting);
                                }
                                live.update()
                            };
                            let _ = app.emit("live-update", update);
                        }
                    }
                }
                let _ = done_tx.send(());
            });
        }

        let update = live.lock().unwrap().update();
        let _ = app.emit("live-update", update);
        Ok(Self { live, capture: Some(capture), control, finished: Some(done_rx), speakers, speaker_feed, pump: Some(pump) })
    }

    pub fn meeting_id(&self) -> String {
        self.live.lock().unwrap().meeting.id.clone()
    }

    pub fn snapshot(&self) -> LiveUpdate {
        self.live.lock().unwrap().update()
    }

    /// Stops the audio, lets the engine finish the last phrase and its translation, labels the
    /// speakers, and saves the meeting. Returns the meeting's id.
    pub async fn stop(mut self, app: AppHandle, my_voice: Option<Vec<f32>>) -> Result<Meeting> {
        {
            let mut live = self.live.lock().unwrap();
            live.state = "stopping".into();
            let update = live.update();
            let _ = app.emit("live-update", update);
        }
        if let Some(mut capture) = self.capture.take() {
            capture.stop();
        }
        // The pump ends when the capture's sender is gone; all audio is then with the engine.
        if let Some(pump) = self.pump.take() {
            let _ = pump.await;
        }
        let _ = self.control.send(Message::Text(r#"{"type":"stop"}"#.to_string().into()));
        if let Some(finished) = self.finished.take() {
            // The last phrase and its translation; a slow PC may need a while.
            let _ = tokio::time::timeout(Duration::from_secs(120), finished).await;
        }
        let _ = self.control.send(Message::Close(None));
        drop(self.speaker_feed.take());
        let tracker = match self.speakers.take() {
            Some(thread) => tokio::task::spawn_blocking(move || thread.join().ok().flatten()).await.ok().flatten(),
            None => None,
        };

        let mut live = self.live.lock().unwrap();
        live.state = "saving".into();
        let end = live.audio_seconds;
        live.transcript.flush(end);
        let mut meeting = live.meeting.clone();
        meeting.paragraphs = live.transcript.paragraphs().to_vec();
        meeting.duration = end;
        meeting.is_live = false;
        if let Some(mut tracker) = tracker {
            let spans = tracker.finish();
            let prints = tracker.prints();
            if let Some((mut voices, spans)) = labels::merging(None, spans, prints, store::now_reference()) {
                labels::apply(&spans, &mut meeting.paragraphs);
                // Your saved voice, found in this recording.
                if let (Some(mine), Some(prints)) = (my_voice.as_deref(), voices.prints.as_ref()) {
                    voices.me = my_voice::find(mine, prints, &voices.teacher);
                }
                meeting.voices = Some(voices);
            }
        }
        save_meeting(&meeting);
        live.meeting = meeting.clone();
        live.state = "done".into();
        let update = live.update();
        let _ = app.emit("live-update", update);
        Ok(meeting)
    }
}

fn voice_core_bytes(samples: &[f32]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(samples.len() * 4);
    for sample in samples {
        bytes.extend_from_slice(&sample.to_le_bytes());
    }
    bytes
}

/// Replaces the meeting in meetings.json (or adds it at the front).
pub fn save_meeting(meeting: &Meeting) {
    let mut snapshot = store::load();
    match snapshot.meetings.iter_mut().find(|m| m.id == meeting.id) {
        Some(existing) => *existing = meeting.clone(),
        None => snapshot.meetings.insert(0, meeting.clone()),
    }
    if let Err(error) = store::save(&snapshot) {
        eprintln!("saving meetings: {error}");
    }
}
