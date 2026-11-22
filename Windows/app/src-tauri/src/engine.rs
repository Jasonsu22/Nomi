//! Starts and stops the shared engine, `moxin-engine`, as the Mac app's LocalEngine does. The engine
//! loads the models in its worker programs, prints `{"port":…,"token":…}` and serves HTTP and
//! WebSocket on 127.0.0.1. The app holds the engine's stdin; when the app ends, the engine sees EOF
//! and ends too, and so do its workers.

use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Emitter, Manager, State};

use crate::platform::{text, Result};
use crate::AppState;

#[derive(Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct LaunchConfig {
    asr_model: String,
    translator_model: String,
    assistant_model: String,
    #[serde(default = "default_interim")]
    interim: String,
    #[serde(default = "auto")]
    asr_device: String,
    #[serde(default = "auto")]
    llm_device: String,
    #[serde(default)]
    threads: u32,
}
fn default_interim() -> String {
    "skip-busy".into()
}
fn auto() -> String {
    "auto".into()
}

#[derive(Deserialize)]
struct Hello {
    port: u16,
    token: String,
}

#[derive(Serialize, Clone)]
struct Ready {
    #[serde(rename = "launchID")]
    launch_id: String,
    port: u16,
    token: String,
}

#[derive(Serialize, Clone)]
struct Exited {
    #[serde(rename = "launchID")]
    launch_id: String,
    message: Option<String>,
}

pub struct EngineProcess {
    child: Arc<Mutex<Child>>,
    _stdin: ChildStdin,
    launch_id: String,
}

impl Drop for EngineProcess {
    fn drop(&mut self) {
        if let Ok(mut child) = self.child.lock() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

/// The folder with moxin-engine and the `asr/` and `llm/` worker folders.
pub fn engine_dir(resources: Option<PathBuf>) -> Option<PathBuf> {
    let name = if cfg!(windows) { "moxin-engine.exe" } else { "moxin-engine" };
    let candidates = [
        std::env::var("NOMI_ENGINE_DIR").ok().map(PathBuf::from),
        resources.map(|dir| dir.join("engine")),
        Some(PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/engine"))),
    ];
    candidates.into_iter().flatten().find(|dir| dir.join(name).is_file())
}

pub fn exe(dir: &Path, sub: &str, name: &str) -> PathBuf {
    let file = if cfg!(windows) { format!("{name}.exe") } else { name.to_string() };
    if sub.is_empty() { dir.join(file) } else { dir.join(sub).join(file) }
}

fn log_tail() -> String {
    let tail = std::fs::read_to_string(crate::paths::engine_log()).unwrap_or_default();
    let last: Vec<&str> = tail.lines().rev().filter(|l| !l.trim().is_empty()).take(4).collect();
    last.into_iter().rev().collect::<Vec<_>>().join(" / ")
}

fn spawn(dir: &Path, config: &LaunchConfig) -> anyhow::Result<(Child, ChildStdin, Hello)> {
    use anyhow::{anyhow, Context};
    std::fs::create_dir_all(crate::paths::root())?;
    let log = std::fs::OpenOptions::new().create(true).append(true).open(crate::paths::engine_log())?;
    let threads = if config.threads == 0 { String::new() } else { config.threads.to_string() };
    let mut command = Command::new(exe(dir, "", "moxin-engine"));
    command
        .arg("--managed-by-app")
        .arg("--asr-model")
        .arg(&config.asr_model)
        .arg("--llm-model")
        .arg(&config.translator_model)
        .arg("--assistant-model")
        .arg(&config.assistant_model)
        .env("ASR_WORKER_BIN", exe(dir, "asr", "asr-worker"))
        .env("LLM_WORKER_BIN", exe(dir, "llm", "llm-worker"))
        .env("NOMI_INTERIM", &config.interim)
        .env("NOMI_ASR_DEVICE", &config.asr_device)
        .env("NOMI_LLM_DEVICE", &config.llm_device)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::from(log));
    if !threads.is_empty() {
        command.env("NOMI_ASR_THREADS", &threads).env("NOMI_LLM_THREADS", &threads);
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
    let mut child = command.spawn().with_context(|| format!("starting the engine in {}", dir.display()))?;
    let stdin = child.stdin.take().ok_or_else(|| anyhow!("the engine has no stdin"))?;
    let stdout = child.stdout.take().ok_or_else(|| anyhow!("the engine has no stdout"))?;
    let mut line = String::new();
    BufReader::new(stdout).read_line(&mut line)?;
    if line.trim().is_empty() {
        let _ = child.kill();
        let _ = child.wait();
        return Err(anyhow!("the engine stopped while starting: {}", log_tail()));
    }
    let hello: Hello = serde_json::from_str(line.trim()).with_context(|| format!("engine said {line}"))?;
    Ok((child, stdin, hello))
}

/// Starts the engine for this launch; `engine-ready` follows, or `engine-exited` when it fails or
/// later stops.
#[tauri::command]
pub async fn engine_launch(app: AppHandle, state: State<'_, AppState>, launch_id: String, config: LaunchConfig) -> Result<()> {
    drop(state.engine.lock().unwrap().take());
    let dir = state.engine_dir.lock().unwrap().clone().ok_or("找不到引擎文件")?;
    let id = launch_id.clone();
    let started = tokio::task::spawn_blocking(move || spawn(&dir, &config)).await.map_err(text)?;
    let (child, stdin, hello) = match started {
        Ok(parts) => parts,
        Err(error) => {
            let _ = app.emit("engine-exited", Exited { launch_id: id, message: Some(error.to_string()) });
            return Ok(());
        }
    };
    let child = Arc::new(Mutex::new(child));
    *state.engine.lock().unwrap() = Some(EngineProcess { child: child.clone(), _stdin: stdin, launch_id: id.clone() });
    let _ = app.emit("engine-ready", Ready { launch_id: id.clone(), port: hello.port, token: hello.token });
    // Watch for the engine ending on its own (a crash, or out of memory).
    let handle = app.clone();
    std::thread::spawn(move || loop {
        std::thread::sleep(std::time::Duration::from_millis(500));
        let status = match child.lock() {
            Ok(mut c) => c.try_wait(),
            Err(_) => return,
        };
        match status {
            Ok(None) => continue,
            Ok(Some(_)) | Err(_) => {
                let state = handle.state::<AppState>();
                let current = state.engine.lock().unwrap().as_ref().map(|e| e.launch_id.clone());
                if current.as_deref() == Some(id.as_str()) {
                    drop(state.engine.lock().unwrap().take());
                    let _ = handle.emit("engine-exited", Exited { launch_id: id.clone(), message: Some(log_tail()).filter(|s| !s.is_empty()) });
                }
                return;
            }
        }
    });
    Ok(())
}

#[tauri::command]
pub fn engine_shutdown(state: State<'_, AppState>) {
    drop(state.engine.lock().unwrap().take());
}
