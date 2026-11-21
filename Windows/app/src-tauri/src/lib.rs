//! Nomi for Windows: the Tauri core. The UI calls the commands below; long work reports back with
//! events (`engine-state`, `live-update`, `live-level`, `live-notice`, `download-progress`).

mod audio;
mod device;
mod engine;
mod models;
mod paths;
mod session;
mod settings;
mod speakers;
mod store;
mod transcript;
mod voices;

use serde::Serialize;
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Emitter, Manager, State};
use tokio::sync::Mutex as AsyncMutex;

use engine::{Engine, EngineState};
use settings::Settings;

#[derive(Default)]
struct AppState {
    engine: Mutex<Option<Engine>>,
    engine_state: Mutex<EngineState>,
    session: AsyncMutex<Option<session::Session>>,
    settings: Mutex<Settings>,
    downloads: Arc<models::Downloads>,
    engine_dir: Mutex<Option<PathBuf>>,
    /// mica, sidebar (macOS, development) or none: whether the window shows a system material.
    material: Mutex<String>,
}

type Result<T> = std::result::Result<T, String>;

fn text<E: std::fmt::Display>(error: E) -> String {
    error.to_string()
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ModelView {
    #[serde(flatten)]
    info: models::ModelInfo,
    ready: bool,
    downloading: bool,
    size: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Overview {
    settings: Settings,
    models: Vec<ModelView>,
    engine: EngineState,
    engine_found: bool,
    data_folder: String,
    models_folder: String,
    recording: bool,
    material: String,
}

fn model_views(state: &AppState) -> Vec<ModelView> {
    models::catalogue()
        .into_iter()
        .map(|info| ModelView {
            ready: models::is_ready(&info),
            downloading: state.downloads.is_active(info.id),
            size: info.files.iter().map(|f| f.size).sum(),
            info,
        })
        .collect()
}

#[tauri::command]
async fn overview(state: State<'_, AppState>) -> Result<Overview> {
    let recording = state.session.lock().await.is_some();
    let settings = state.settings.lock().unwrap().clone();
    let engine = state.engine_state.lock().unwrap().clone();
    let engine_found = state.engine_dir.lock().unwrap().is_some();
    let material = state.material.lock().unwrap().clone();
    Ok(Overview {
        models: model_views(&state),
        engine,
        engine_found,
        data_folder: paths::root().display().to_string(),
        models_folder: paths::models().display().to_string(),
        recording,
        material,
        settings,
    })
}

#[tauri::command]
async fn device_report(state: State<'_, AppState>) -> Result<device::DeviceReport> {
    let dir = state.engine_dir.lock().unwrap().clone();
    tokio::task::spawn_blocking(move || device::read(dir.as_deref())).await.map_err(text)
}

#[tauri::command]
async fn save_settings(app: AppHandle, state: State<'_, AppState>, settings: Settings) -> Result<()> {
    let restart = {
        let mut current = state.settings.lock().unwrap();
        let restart = current.asr_model != settings.asr_model
            || current.llm_model != settings.llm_model
            || current.asr_device != settings.asr_device
            || current.llm_device != settings.llm_device
            || current.threads != settings.threads
            || current.interim != settings.interim;
        *current = settings.clone();
        restart
    };
    settings::save(&settings).map_err(text)?;
    if restart && state.engine.lock().unwrap().is_some() {
        start_engine_inner(app, &state).await?;
    }
    Ok(())
}

#[tauri::command]
fn download_model(app: AppHandle, state: State<'_, AppState>, id: String) -> Result<()> {
    state.downloads.start(app, id).map_err(text)
}

#[tauri::command]
fn cancel_download(state: State<'_, AppState>, id: String) {
    state.downloads.cancel(&id);
}

#[tauri::command]
fn delete_model(id: String) -> Result<()> {
    let model = models::find(&id).ok_or("unknown model")?;
    for file in &model.files {
        // The segmentation file is shared by both speaker models.
        let shared = model.role == "speakers"
            && models::catalogue().iter().any(|other| other.id != model.id && other.files.iter().any(|f| f.file == file.file) && models::is_ready(other));
        if !shared {
            let _ = std::fs::remove_file(models::file_path(file));
        }
    }
    Ok(())
}

fn set_engine_state(app: &AppHandle, state: &AppState, value: EngineState) {
    *state.engine_state.lock().unwrap() = value.clone();
    let _ = app.emit("engine-state", value);
}

async fn start_engine_inner(app: AppHandle, state: &AppState) -> Result<()> {
    if state.session.lock().await.is_some() {
        return Err("正在录音，停止后才能切换模型".into());
    }
    let dir = state.engine_dir.lock().unwrap().clone().ok_or("找不到引擎文件")?;
    let settings = state.settings.lock().unwrap().clone();
    // The old engine ends first, so two never hold the models at once.
    drop(state.engine.lock().unwrap().take());
    set_engine_state(&app, state, EngineState { state: "starting".into(), message: None, status: None });
    match tokio::task::spawn_blocking(move || Engine::start(&dir, &settings)).await.map_err(text)? {
        Ok(engine) => {
            let status = engine::status(engine.port, &engine.token).await.ok();
            *state.engine.lock().unwrap() = Some(engine);
            set_engine_state(&app, state, EngineState { state: "ready".into(), message: None, status });
            Ok(())
        }
        Err(error) => {
            let message = error.to_string();
            set_engine_state(&app, state, EngineState { state: "failed".into(), message: Some(message.clone()), status: None });
            Err(message)
        }
    }
}

#[tauri::command]
async fn start_engine(app: AppHandle, state: State<'_, AppState>) -> Result<()> {
    start_engine_inner(app, &state).await
}

#[tauri::command]
fn input_devices() -> Vec<audio::InputDevice> {
    audio::input_devices()
}

#[tauri::command]
async fn start_recording(app: AppHandle, state: State<'_, AppState>, options: session::StartOptions) -> Result<String> {
    let mut slot = state.session.lock().await;
    if slot.is_some() {
        return Err("已经在录音".into());
    }
    let (port, token) = {
        let engine = state.engine.lock().unwrap();
        let engine = engine.as_ref().ok_or("模型还没有加载")?;
        (engine.port, engine.token.clone())
    };
    let settings = state.settings.lock().unwrap().clone();
    let session = session::Session::start(app, port, token, options, settings).await.map_err(text)?;
    let id = session.meeting_id();
    *slot = Some(session);
    Ok(id)
}

#[tauri::command]
async fn live_snapshot(state: State<'_, AppState>) -> Result<Option<session::LiveUpdate>> {
    Ok(state.session.lock().await.as_ref().map(|s| s.snapshot()))
}

#[tauri::command]
async fn stop_recording(app: AppHandle, state: State<'_, AppState>) -> Result<String> {
    let session = state.session.lock().await.take().ok_or("没有在录音")?;
    let my_voice = state.settings.lock().unwrap().my_voice.clone();
    let meeting = session.stop(app, my_voice).await.map_err(text)?;
    Ok(meeting.id)
}

/// A meeting as the UI shows it: the stored meeting plus each voice's name.
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct MeetingView {
    #[serde(flatten)]
    meeting: store::Meeting,
    speaker_names: BTreeMap<String, voices::VoiceName>,
    audio_path: Option<String>,
}

fn view(meeting: store::Meeting) -> MeetingView {
    let speaker_names = meeting.voices.as_ref().map(|v| v.all_names()).unwrap_or_default();
    let audio_path = meeting
        .audio_files
        .as_ref()
        .and_then(|files| files.first())
        .map(|file| paths::meeting_dir(&meeting.id).join(file))
        .filter(|path| path.is_file())
        .map(|path| path.display().to_string());
    MeetingView { meeting, speaker_names, audio_path }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct MeetingSummary {
    id: String,
    title: String,
    started_at: f64,
    duration: f64,
    source_language: String,
    target_language: String,
    preview: String,
    lines: usize,
    speakers: usize,
    is_live: bool,
}

#[tauri::command]
fn list_meetings() -> Vec<MeetingSummary> {
    store::load()
        .meetings
        .into_iter()
        .map(|m| {
            let lines = m.paragraphs.iter().map(|p| p.commits.len()).sum();
            // Hidden speakers stay out of the preview too.
            let shown = store::shown_paragraphs(&m);
            let preview: String = shown.iter().flat_map(|p| p.commits.iter()).take(3).map(|c| c.source.as_str()).collect::<Vec<_>>().join(" ");
            MeetingSummary {
                speakers: m.voices.as_ref().map(|v| v.seconds.len()).unwrap_or(0),
                preview: preview.chars().take(140).collect(),
                id: m.id,
                title: m.title,
                started_at: m.started_at,
                duration: m.duration,
                source_language: m.source_language,
                target_language: m.target_language,
                lines,
                is_live: m.is_live,
            }
        })
        .collect()
}

#[tauri::command]
fn get_meeting(id: String) -> Result<MeetingView> {
    store::load().meetings.into_iter().find(|m| m.id == id).map(view).ok_or_else(|| "找不到这个会议".into())
}

/// Changes one meeting and saves; returns it as the UI shows it.
fn edit_meeting(id: &str, change: impl FnOnce(&mut store::Meeting)) -> Result<MeetingView> {
    let mut snapshot = store::load();
    let meeting = snapshot.meetings.iter_mut().find(|m| m.id == id).ok_or("找不到这个会议")?;
    change(meeting);
    let result = meeting.clone();
    store::save(&snapshot).map_err(text)?;
    Ok(view(result))
}

#[tauri::command]
fn rename_meeting(id: String, title: String) -> Result<MeetingView> {
    edit_meeting(&id, |m| m.title = title.trim().to_string())
}

#[tauri::command]
fn delete_meeting(id: String) -> Result<()> {
    let mut snapshot = store::load();
    snapshot.meetings.retain(|m| m.id != id);
    store::save(&snapshot).map_err(text)?;
    let _ = std::fs::remove_dir_all(paths::meeting_dir(&id));
    Ok(())
}

#[tauri::command]
fn set_hidden_speakers(id: String, hidden: Vec<String>) -> Result<MeetingView> {
    edit_meeting(&id, |m| m.hidden_speakers = (!hidden.is_empty()).then_some(hidden))
}

#[tauri::command]
fn rename_speaker(id: String, speaker: String, name: String) -> Result<MeetingView> {
    edit_meeting(&id, |m| {
        if let Some(voices) = m.voices.as_mut() {
            let names = voices.names.get_or_insert_with(BTreeMap::new);
            if name.trim().is_empty() {
                names.remove(&speaker);
            } else {
                names.insert(speaker, name.trim().to_string());
            }
        }
    })
}

/// "This is me" (speaker given) or "This isn't me" (none). Saves your voiceprint for later lectures.
#[tauri::command]
fn set_me(state: State<'_, AppState>, id: String, speaker: Option<String>) -> Result<MeetingView> {
    let mut saved_print: Option<Vec<f32>> = None;
    let result = edit_meeting(&id, |m| {
        if let Some(voices) = m.voices.as_mut() {
            voices.me = speaker.clone();
            voices.me_chosen = Some(true);
            if let Some(print) = speaker.as_ref().and_then(|s| voices.prints.as_ref().and_then(|p| p.get(s))) {
                saved_print = Some(print.clone());
            }
        }
    })?;
    if let Some(print) = saved_print {
        let mut settings = state.settings.lock().unwrap();
        settings.my_voice = Some(voices::my_voice::blended(settings.my_voice.as_deref(), &print));
        settings::save(&settings).map_err(text)?;
    }
    Ok(result)
}

/// "This is the teacher" on a voice: it becomes Speaker 1.
#[tauri::command]
fn set_teacher(id: String, speaker: String) -> Result<MeetingView> {
    edit_meeting(&id, |m| {
        if let Some(voices) = m.voices.as_mut() {
            if voices.seconds.contains_key(&speaker) {
                voices.teacher = speaker;
            }
        }
    })
}

#[tauri::command]
fn open_folder(path: String) {
    let _ = std::fs::create_dir_all(&path);
    #[cfg(windows)]
    let _ = std::process::Command::new("explorer").arg(&path).spawn();
    #[cfg(target_os = "macos")]
    let _ = std::process::Command::new("open").arg(&path).spawn();
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(AppState::default())
        .setup(|app| {
            let state = app.state::<AppState>();
            *state.settings.lock().unwrap() = settings::load();
            *state.engine_dir.lock().unwrap() = engine::engine_dir(app.path().resource_dir().ok());
            let material = open_main_window(app)?;
            *state.material.lock().unwrap() = material;
            // Load the models at start when they are on disk, as the Mac app does.
            let ready = {
                let settings = state.settings.lock().unwrap();
                settings.set_up
                    && [&settings.asr_model, &settings.llm_model].iter().all(|id| models::find(id).is_some_and(|m| models::is_ready(&m)))
            };
            if ready {
                let handle = app.handle().clone();
                tauri::async_runtime::spawn(async move {
                    let state = handle.state::<AppState>();
                    let _ = start_engine_inner(handle.clone(), &state).await;
                });
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            overview,
            device_report,
            save_settings,
            download_model,
            cancel_download,
            delete_model,
            start_engine,
            input_devices,
            start_recording,
            live_snapshot,
            stop_recording,
            list_meetings,
            get_meeting,
            rename_meeting,
            delete_meeting,
            set_hidden_speakers,
            rename_speaker,
            set_me,
            set_teacher,
            open_folder,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Nomi");
}

/// Opens the window. On Windows 11 it is transparent with Mica behind it, so the panels' glass
/// shows the desktop's colors softly; Windows 10 has no Mica, so the window is opaque and the page
/// paints its own background.
fn open_main_window(app: &tauri::App) -> tauri::Result<String> {
    use tauri::window::{Effect, EffectsBuilder};
    let material = system_material();
    let mut builder = tauri::WebviewWindowBuilder::new(app, "main", tauri::WebviewUrl::default())
        .title("Nomi")
        .inner_size(1180.0, 780.0)
        .min_inner_size(860.0, 560.0)
        .transparent(material != "none");
    builder = match material.as_str() {
        "mica" => builder.effects(EffectsBuilder::new().effect(Effect::Mica).build()),
        "sidebar" => builder.effects(EffectsBuilder::new().effect(Effect::Sidebar).build()),
        _ => builder,
    };
    builder.build()?;
    Ok(material)
}

fn system_material() -> String {
    if cfg!(target_os = "macos") {
        return "sidebar".into();
    }
    if cfg!(windows) {
        // Mica needs Windows 11 (build 22000 or later).
        let build: u32 = sysinfo::System::kernel_version().and_then(|v| v.split('.').nth(2).or(Some(v.as_str())).and_then(|b| b.parse().ok())).unwrap_or(0);
        if build >= 22_000 {
            return "mica".into();
        }
    }
    "none".into()
}
