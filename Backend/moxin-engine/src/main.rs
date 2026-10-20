mod pipeline;

use anyhow::{anyhow, Result};
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::response::IntoResponse;
use axum::routing::{get, post};
use axum::Router;
use pipeline::{read_wav, OutEvent, Pipeline, Worker};
use serde::Deserialize;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Instant;
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;

#[derive(Clone)]
struct App {
    token: String,
    pipeline: Arc<Mutex<Pipeline>>,
    busy: Arc<Mutex<Busy>>,
}

/// What the engine is doing. A recording and a chat reply may run together;
/// switching or unloading a model waits until both are idle.
#[derive(Default)]
struct Busy {
    recording: bool,
    assistant: bool,
    model: bool,
    /// The chat worker answering right now, so a recording can lower its priority.
    assistant_pid: Option<u32>,
}

#[derive(Clone, Copy)]
enum Job {
    Recording,
    Assistant,
    Model,
}

impl Busy {
    fn claim(&mut self, job: Job) -> bool {
        let free = match job {
            Job::Recording => !self.recording && !self.model,
            Job::Assistant => !self.assistant && !self.model,
            Job::Model => !self.recording && !self.assistant && !self.model,
        };
        if free {
            *self.flag(job) = true;
        }
        free
    }

    fn release(&mut self, job: Job) {
        *self.flag(job) = false;
    }

    fn flag(&mut self, job: Job) -> &mut bool {
        match job {
            Job::Recording => &mut self.recording,
            Job::Assistant => &mut self.assistant,
            Job::Model => &mut self.model,
        }
    }
}

/// Releases a job when its request ends, including when the work panics.
struct Release(Arc<Mutex<Busy>>, Job);

impl Drop for Release {
    fn drop(&mut self) {
        if let Ok(mut busy) = self.0.lock() {
            busy.release(self.1);
        }
    }
}

/// Stops the chat reply in progress. The worker ends at its next token and returns what it wrote.
async fn cancel_assistant(State(app): State<App>, headers: HeaderMap) -> axum::response::Response {
    if !authorized(&headers, &app.token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    if let Some(pid) = app.busy.lock().expect("busy").assistant_pid {
        cancel_reply(pid);
    }
    StatusCode::NO_CONTENT.into_response()
}

fn cancel_reply(pid: u32) {
    unsafe {
        libc::kill(pid as libc::pid_t, libc::SIGUSR1);
    }
}

/// Live transcription comes first. During a recording the chat worker runs in the
/// background priority band, which lowers its CPU and disk priority.
#[cfg(target_os = "macos")]
fn set_background(pid: u32, background: bool) {
    let value = if background { libc::PRIO_DARWIN_BG } else { 0 };
    unsafe {
        libc::setpriority(libc::PRIO_DARWIN_PROCESS, pid as libc::id_t, value);
    }
}

#[cfg(not(target_os = "macos"))]
fn set_background(_pid: u32, _background: bool) {}

#[tokio::main]
async fn main() -> Result<()> {
    if std::env::args().any(|arg| arg == "--managed-by-app") {
        manage_app_lifetime()?;
    }
    tracing_subscriber::fmt()
        .with_writer(io::stderr)
        .with_env_filter(EnvFilter::from_default_env().add_directive(tracing::Level::INFO.into()))
        .init();

    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("replay-wav") => replay_wav(args.collect()),
        _ => serve().await,
    }
}

// The app owns stdin's write end. EOF also covers an app crash or forced quit.
// Use a private process group so only this engine and its workers are terminated.
fn manage_app_lifetime() -> Result<()> {
    if unsafe { libc::setpgid(0, 0) } != 0 {
        return Err(io::Error::last_os_error().into());
    }
    std::thread::spawn(|| {
        let mut buffer = [0u8; 64];
        loop {
            match io::stdin().read(&mut buffer) {
                Ok(0) => break,
                Ok(_) => {},
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
        unsafe { libc::kill(0, libc::SIGTERM); }
    });
    Ok(())
}

fn replay_wav(args: Vec<String>) -> Result<()> {
    let input = args.first().cloned().ok_or_else(|| anyhow!("用法：moxin-engine replay-wav 文件.wav --out 输出.jsonl"))?;
    let output = flag(&args, "--out").ok_or_else(|| anyhow!("replay-wav 需要 --out"))?;
    let source = flag(&args, "--source-language").unwrap_or_else(|| "zh".into());
    let target = flag(&args, "--target-language").unwrap_or_else(|| "en".into());
    let asr = model_path(flag(&args, "--asr-model"), "qwen3-asr-1.7b");
    let llm = model_path(flag(&args, "--llm-model"), "Qwen3.5-2B-MLX-4bit");
    let mut pipeline = Pipeline::start(asr, llm, &source, &target)?;
    let mut file = std::fs::File::create(output)?;
    write_event(&mut file, &state_event(&pipeline, "loading"))?;
    if pipeline.asr_label() != "ready" {
        write_event(
            &mut file,
            &OutEvent::Error {
                code: "asr_missing".into(),
                message: "识别模型没有加载".into(),
            },
        )?;
        return Err(anyhow!("asr_missing"));
    }
    let samples = read_wav(Path::new(&input))?;
    write_event(&mut file, &state_event(&pipeline, "listening"))?;
    let started = Instant::now();
    let mut latencies_ms = Vec::new();
    for chunk in samples.chunks(1600) {
        let chunk_started = Instant::now();
        for event in pipeline.push_audio(chunk) {
            if let OutEvent::Commit { id, end, .. } = &event {
                let latency_ms = chunk_started.elapsed().as_millis();
                latencies_ms.push(latency_ms);
                eprintln!("commit id={id} audio_end={end:.2} latency_ms={latency_ms}");
            }
            write_event(&mut file, &event)?;
        }
    }
    write_event(&mut file, &state_event(&pipeline, "stopping"))?;
    let finish_started = Instant::now();
    for event in pipeline.finish() {
        if let OutEvent::Commit { id, end, .. } = &event {
            let latency_ms = finish_started.elapsed().as_millis();
            latencies_ms.push(latency_ms);
            eprintln!("commit id={id} audio_end={end:.2} latency_ms={latency_ms}");
        }
        write_event(&mut file, &event)?;
    }
    write_event(&mut file, &state_event(&pipeline, "idle"))?;
    let audio_secs = samples.len() as f64 / 16_000.0;
    let wall_secs = started.elapsed().as_secs_f64();
    let (p50, p95) = percentiles_ms(&latencies_ms);
    eprintln!(
        "latency_summary commits={} p50_ms={p50} p95_ms={p95} audio_secs={audio_secs:.1} wall_secs={wall_secs:.1}",
        latencies_ms.len()
    );
    Ok(())
}

fn percentiles_ms(values: &[u128]) -> (u128, u128) {
    if values.is_empty() {
        return (0, 0);
    }
    let mut sorted = values.to_vec();
    sorted.sort_unstable();
    let pick = |fraction: f64| sorted[((sorted.len() - 1) as f64 * fraction).round() as usize];
    (pick(0.50), pick(0.95))
}

fn write_event(file: &mut impl Write, event: &OutEvent) -> Result<()> {
    writeln!(file, "{}", serde_json::to_string(event)?)?;
    Ok(())
}

fn state_event(pipeline: &Pipeline, value: &str) -> OutEvent {
    OutEvent::State {
        value: value.into(),
        asr: pipeline.asr_label().into(),
        translator: pipeline.translator_label().into(),
    }
}

async fn serve() -> Result<()> {
    let port = flag_from_env("--port").unwrap_or_else(|| "0".into()).parse::<u16>()?;
    let asr = model_path(flag_from_env("--asr-model"), "qwen3-asr-1.7b");
    let llm = model_path(flag_from_env("--llm-model"), "Qwen3.5-2B-MLX-4bit");
    let mut pipeline = Pipeline::start(asr, llm, "zh", "en")?;
    pipeline.configure_assistant(model_path(flag_from_env("--assistant-model"), "Qwen3.5-2B-MLX-4bit"));
    let token = random_token();
    let app = App {
        token: token.clone(),
        pipeline: Arc::new(Mutex::new(pipeline)),
        busy: Arc::new(Mutex::new(Busy::default())),
    };
    let listener = TcpListener::bind(("127.0.0.1", port)).await?;
    let bound = listener.local_addr()?.port();
    println!("{}", serde_json::json!({ "port": bound, "token": token }));
    io::stdout().flush()?;
    let router = Router::new()
        .route("/health", get(health))
        .route("/v1/status", get(status))
        .route("/v1/session", get(session))
        .route("/v1/models/asr/load", post(load_asr))
        .route("/v1/models/asr/unload", post(unload_asr))
        .route("/v1/models/llm/load", post(load_llm))
        .route("/v1/models/llm/unload", post(unload_llm))
        .route("/v1/models/select", post(select_model))
        .route("/v1/models/unload-path", post(unload_path))
        .route("/v1/assistant/generate", post(generate_assistant))
        .route("/v1/assistant/cancel", post(cancel_assistant))
        .with_state(app);
    axum::serve(listener, router).await?;
    Ok(())
}

async fn health(State(app): State<App>, headers: HeaderMap) -> impl IntoResponse {
    if !authorized(&headers, &app.token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    (StatusCode::OK, "ok").into_response()
}

async fn status(State(app): State<App>, headers: HeaderMap) -> impl IntoResponse {
    if !authorized(&headers, &app.token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    let body = app.pipeline.lock().expect("pipeline").status_json();
    axum::Json(body).into_response()
}

async fn load_asr(State(app): State<App>, headers: HeaderMap) -> impl IntoResponse {
    model_action(app, headers, |pipeline| pipeline.load_asr()).await
}

async fn unload_asr(State(app): State<App>, headers: HeaderMap) -> impl IntoResponse {
    model_action(app, headers, |pipeline| {
        pipeline.unload_asr();
        Ok(())
    })
    .await
}

async fn load_llm(State(app): State<App>, headers: HeaderMap) -> impl IntoResponse {
    model_action(app, headers, |pipeline| pipeline.load_llm()).await
}

async fn unload_llm(State(app): State<App>, headers: HeaderMap) -> impl IntoResponse {
    model_action(app, headers, |pipeline| {
        pipeline.unload_llm();
        Ok(())
    })
    .await
}

#[derive(Deserialize)]
struct ModelSelection {
    role: String,
    path: PathBuf,
}

async fn select_model(State(app): State<App>, headers: HeaderMap, axum::Json(selection): axum::Json<ModelSelection>) -> impl IntoResponse {
    exclusive_model_action(app, headers, move |pipeline| {
        pipeline.select_model(&selection.role, selection.path)?;
        Ok(pipeline.status_json())
    }).await
}

#[derive(Deserialize)]
struct ModelPath { path: PathBuf }

async fn unload_path(State(app): State<App>, headers: HeaderMap, axum::Json(model): axum::Json<ModelPath>) -> impl IntoResponse {
    exclusive_model_action(app, headers, move |pipeline| {
        pipeline.unload_path(&model.path);
        Ok(pipeline.status_json())
    }).await
}

#[derive(Deserialize)]
struct AssistantRequest { system: String, prompt: String, max_tokens: usize }

async fn generate_assistant(State(app): State<App>, headers: HeaderMap, axum::Json(request): axum::Json<AssistantRequest>) -> axum::response::Response {
    if !authorized(&headers, &app.token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    if !app.busy.lock().expect("busy").claim(Job::Assistant) {
        return (StatusCode::CONFLICT, "上一条回答还没结束，或本地模型正在切换，请稍后再试").into_response();
    }
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel::<String>();
    let busy = app.busy.clone();
    let pipeline = app.pipeline.clone();
    tokio::task::spawn_blocking(move || {
        let _release = Release(busy.clone(), Job::Assistant);
        let send = |value: serde_json::Value| {
            let _ = tx.send(format!("data: {value}\n\n"));
        };
        let outcome = (|| -> Result<String> {
            // The pipeline lock is only held to hand the worker over and back,
            // so audio from a recording keeps being transcribed during the reply.
            let (worker, path, id) = pipeline.lock().expect("pipeline").checkout_assistant()?;
            let mut worker = match worker {
                Some(worker) => worker,
                None => Worker::spawn_assistant(&path)?,
            };
            let pid = worker.pid();
            {
                let mut state = busy.lock().expect("busy");
                state.assistant_pid = Some(pid);
                set_background(pid, state.recording);
            }
            let mut stopped = false;
            let result = worker.generate(id, request.system, request.prompt, request.max_tokens, &mut |text| {
                if text.is_empty() {
                    return;
                }
                let line = format!("data: {}\n\n", serde_json::json!({ "text": text }));
                // The app went away (Stop, or a newer question): end the reply instead of finishing it unseen.
                if tx.send(line).is_err() && !stopped {
                    stopped = true;
                    cancel_reply(pid);
                }
            });
            busy.lock().expect("busy").assistant_pid = None;
            set_background(pid, false);
            // A worker that failed mid-reply may be out of step; start a fresh one next time.
            if result.is_ok() {
                pipeline.lock().expect("pipeline").checkin_assistant(worker, &path);
            }
            result
        })();
        match outcome {
            Ok(text) => send(serde_json::json!({ "done": true, "text": text })),
            Err(error) => send(serde_json::json!({ "error": error.to_string() })),
        }
    });
    let stream = futures::stream::unfold(rx, |mut rx| async move {
        let next = rx.recv().await?;
        Some((Ok::<_, std::io::Error>(axum::body::Bytes::from(next)), rx))
    });
    axum::response::Response::builder()
        .header("content-type", "text/event-stream")
        .header("cache-control", "no-cache")
        .body(axum::body::Body::from_stream(stream))
        .unwrap_or_else(|_| StatusCode::INTERNAL_SERVER_ERROR.into_response())
}

async fn exclusive_model_action(app: App, headers: HeaderMap, action: impl FnOnce(&mut Pipeline) -> Result<serde_json::Value> + Send + 'static) -> axum::response::Response {
    if !authorized(&headers, &app.token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    if !app.busy.lock().expect("busy").claim(Job::Model) {
        return (StatusCode::CONFLICT, "录制或其他本地模型操作正在进行，请稍后再试").into_response();
    }
    let busy = app.busy.clone();
    let result = tokio::task::spawn_blocking(move || {
        let _release = Release(busy, Job::Model);
        let mut pipeline = app.pipeline.lock().expect("pipeline");
        action(&mut pipeline)
    }).await;
    match result {
        Ok(Ok(status)) => axum::Json(status).into_response(),
        Ok(Err(error)) => (StatusCode::BAD_REQUEST, error.to_string()).into_response(),
        Err(error) => (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()).into_response(),
    }
}

async fn model_action(app: App, headers: HeaderMap, action: impl FnOnce(&mut Pipeline) -> Result<()> + Send + 'static) -> impl IntoResponse {
    if !authorized(&headers, &app.token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    let result = tokio::task::spawn_blocking(move || {
        let mut pipeline = app.pipeline.lock().expect("pipeline");
        action(&mut pipeline)
    })
    .await;
    match result {
        Ok(Ok(())) => StatusCode::OK.into_response(),
        Ok(Err(error)) => (StatusCode::BAD_REQUEST, error.to_string()).into_response(),
        Err(error) => (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()).into_response(),
    }
}

async fn session(State(app): State<App>, headers: HeaderMap, upgrade: WebSocketUpgrade) -> impl IntoResponse {
    if !authorized(&headers, &app.token) {
        return StatusCode::UNAUTHORIZED.into_response();
    }
    if !app.busy.lock().expect("busy").claim(Job::Recording) {
        return StatusCode::CONFLICT.into_response();
    }
    upgrade.on_upgrade(move |socket| handle_session(socket, app)).into_response()
}

async fn handle_session(mut socket: WebSocket, app: App) {
    let _release = Release(app.busy.clone(), Job::Recording);
    if let Some(pid) = app.busy.lock().expect("busy").assistant_pid {
        set_background(pid, true);
    }
    let mut started = false;
    loop {
        let incoming = if started {
            match tokio::time::timeout(std::time::Duration::from_secs(1), socket.recv()).await {
                Ok(message) => message,
                Err(_) => {
                    let pipeline = app.pipeline.clone();
                    let events = tokio::task::spawn_blocking(move || pipeline.lock().expect("pipeline").poll_clock())
                        .await
                        .unwrap_or_default();
                    for event in events {
                        send_json(&mut socket, &event).await;
                    }
                    continue;
                }
            }
        } else {
            socket.recv().await
        };
        let Some(message) = incoming else { break };
        let message = match message {
            Ok(message) => message,
            Err(_) => break,
        };
        match message {
            Message::Text(text) => {
                let value: serde_json::Value = match serde_json::from_str(&text) {
                    Ok(value) => value,
                    Err(error) => {
                        send_json(&mut socket, &OutEvent::Error { code: "bad_message".into(), message: error.to_string() }).await;
                        continue;
                    }
                };
                match value.get("type").and_then(|item| item.as_str()) {
                    Some("start") => {
                        let source = value.get("sourceLanguage").and_then(|item| item.as_str()).unwrap_or("zh");
                        let target = value.get("targetLanguage").and_then(|item| item.as_str()).unwrap_or("en");
                        let (event, ready) = {
                            let mut pipeline = app.pipeline.lock().expect("pipeline");
                            pipeline.configure(source, target);
                            let ready = pipeline.asr_label() == "ready";
                            let event = if ready {
                                state_event(&pipeline, "listening")
                            } else {
                                OutEvent::Error {
                                    code: "asr_missing".into(),
                                    message: "识别模型没有加载".into(),
                                }
                            };
                            (event, ready)
                        };
                        send_json(&mut socket, &event).await;
                        started = ready;
                        if !ready {
                            break;
                        }
                    }
                    Some("stop") => {
                        send_json(&mut socket, &{
                            let pipeline = app.pipeline.lock().expect("pipeline");
                            state_event(&pipeline, "stopping")
                        })
                        .await;
                        let pipeline = app.pipeline.clone();
                        let events = tokio::task::spawn_blocking(move || pipeline.lock().expect("pipeline").finish())
                            .await
                            .unwrap_or_default();
                        for event in events {
                            send_json(&mut socket, &event).await;
                        }
                        let idle = {
                            let pipeline = app.pipeline.lock().expect("pipeline");
                            state_event(&pipeline, "idle")
                        };
                        send_json(&mut socket, &idle).await;
                        break;
                    }
                    _ => {}
                }
            }
            Message::Binary(bytes) if started => {
                let samples = voice_core::pcm_from_bytes(&bytes);
                let pipeline = app.pipeline.clone();
                let events = tokio::task::spawn_blocking(move || pipeline.lock().expect("pipeline").push_audio(&samples))
                    .await
                    .unwrap_or_default();
                for event in events {
                    send_json(&mut socket, &event).await;
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
    }
    if let Some(pid) = app.busy.lock().expect("busy").assistant_pid {
        set_background(pid, false);
    }
}

async fn send_json(socket: &mut WebSocket, event: &OutEvent) {
    if let Ok(text) = serde_json::to_string(event) {
        let _ = socket.send(Message::Text(text)).await;
    }
}

fn authorized(headers: &HeaderMap, token: &str) -> bool {
    headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| value == format!("Bearer {token}"))
}

fn model_path(explicit: Option<String>, folder: &str) -> PathBuf {
    if let Some(path) = explicit {
        return PathBuf::from(path);
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    PathBuf::from(home).join(".OminiX/models").join(folder)
}

fn flag(args: &[String], name: &str) -> Option<String> {
    args.iter().position(|arg| arg == name).and_then(|index| args.get(index + 1)).cloned().or_else(|| {
        args.iter().find_map(|arg| arg.strip_prefix(&format!("{name}=")).map(str::to_string))
    })
}

fn flag_from_env(name: &str) -> Option<String> {
    flag(&std::env::args().skip(1).collect::<Vec<_>>(), name)
}

fn random_token() -> String {
    let mut bytes = [0u8; 16];
    if let Ok(mut file) = std::fs::File::open("/dev/urandom") {
        use std::io::Read;
        let _ = file.read_exact(&mut bytes);
    }
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::{Busy, Job};

    #[test]
    fn a_chat_reply_and_a_recording_run_together() {
        let mut busy = Busy::default();
        assert!(busy.claim(Job::Recording));
        assert!(busy.claim(Job::Assistant));
        assert!(!busy.claim(Job::Recording), "only one recording at a time");
        assert!(!busy.claim(Job::Assistant), "only one chat reply at a time");
        assert!(!busy.claim(Job::Model), "models stay put while either runs");
        busy.release(Job::Recording);
        assert!(!busy.claim(Job::Model));
        busy.release(Job::Assistant);
        assert!(busy.claim(Job::Model));
        assert!(!busy.claim(Job::Recording), "a model change blocks a new recording");
        assert!(!busy.claim(Job::Assistant), "a model change blocks a new reply");
    }
}
