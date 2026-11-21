//! Starts and stops the shared engine, `moxin-engine`, as the Mac app does. The engine loads the
//! two models in their worker programs, then prints `{"port":…,"token":…}` and serves HTTP and
//! WebSocket on 127.0.0.1. The app holds the engine's stdin; when the app ends, the engine sees
//! EOF and ends too, and each worker then sees EOF on its own stdin.

use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};

use crate::settings::Settings;

#[derive(Deserialize)]
struct Hello {
    port: u16,
    token: String,
}

pub struct Engine {
    child: Child,
    _stdin: ChildStdin,
    pub port: u16,
    pub token: String,
}

#[derive(Clone, Debug, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct EngineState {
    /// stopped, starting, ready or failed.
    pub state: String,
    pub message: Option<String>,
    /// The engine's own status: each model's files, whether loaded, and any load error.
    pub status: Option<serde_json::Value>,
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

fn exe(dir: &Path, sub: &str, name: &str) -> PathBuf {
    let file = if cfg!(windows) { format!("{name}.exe") } else { name.to_string() };
    if sub.is_empty() { dir.join(file) } else { dir.join(sub).join(file) }
}

impl Engine {
    /// Blocks until both models are loaded (seconds, longer on a first GPU run).
    pub fn start(dir: &Path, settings: &Settings) -> Result<Self> {
        let asr = crate::models::main_path(&settings.asr_model).ok_or_else(|| anyhow!("unknown speech model"))?;
        let llm = crate::models::main_path(&settings.llm_model).ok_or_else(|| anyhow!("unknown translation model"))?;
        std::fs::create_dir_all(crate::paths::root())?;
        let log = std::fs::OpenOptions::new().create(true).append(true).open(crate::paths::engine_log())?;
        let mut command = Command::new(exe(dir, "", "moxin-engine"));
        command
            .arg("--managed-by-app")
            .arg("--asr-model")
            .arg(&asr)
            .arg("--llm-model")
            .arg(&llm)
            .arg("--assistant-model")
            .arg(&llm)
            .env("ASR_WORKER_BIN", exe(dir, "asr", "asr-worker"))
            .env("LLM_WORKER_BIN", exe(dir, "llm", "llm-worker"))
            .env("NOMI_INTERIM", &settings.interim)
            .env("NOMI_ASR_DEVICE", &settings.asr_device)
            .env("NOMI_LLM_DEVICE", &settings.llm_device)
            .env("NOMI_ASR_THREADS", settings.threads.to_string())
            .env("NOMI_LLM_THREADS", settings.threads.to_string())
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::from(log));
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
            let tail = std::fs::read_to_string(crate::paths::engine_log()).unwrap_or_default();
            let last: Vec<&str> = tail.lines().rev().take(6).collect();
            return Err(anyhow!("the engine stopped while starting: {}", last.into_iter().rev().collect::<Vec<_>>().join(" / ")));
        }
        let hello: Hello = serde_json::from_str(line.trim()).with_context(|| format!("engine said {line}"))?;
        Ok(Self { child, _stdin: stdin, port: hello.port, token: hello.token })
    }

}

impl Drop for Engine {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

pub async fn status(port: u16, token: &str) -> Result<serde_json::Value> {
    let response = reqwest::Client::new()
        .get(format!("http://127.0.0.1:{port}/v1/status"))
        .bearer_auth(token)
        .send()
        .await?
        .error_for_status()?;
    Ok(response.json().await?)
}
