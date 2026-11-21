//! Model files and their downloads. The catalog lives in the UI (models/localModels.ts); each
//! command gets the files it is about. A file comes from the first source that answers:
//! huggingface.co, then hf-mirror.com (huggingface.co is blocked in mainland China). A download
//! resumes from its `.part` file and is checked against its size.

use anyhow::{anyhow, bail, Result};
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, State};
use tokio::io::AsyncWriteExt;

const SOURCES: [&str; 2] = ["https://huggingface.co", "https://hf-mirror.com"];

#[derive(Clone, Deserialize, Serialize)]
pub struct ModelFile {
    pub file: String,
    pub path: String,
    pub size: u64,
}

#[derive(Deserialize)]
pub struct ModelFiles {
    id: String,
    files: Vec<ModelFile>,
}

pub fn file_path(file: &ModelFile) -> PathBuf {
    crate::paths::models().join(&file.file)
}

fn present(file: &ModelFile) -> bool {
    std::fs::metadata(file_path(file)).is_ok_and(|m| m.len() == file.size)
}

#[tauri::command]
pub fn models_installed(models: Vec<ModelFiles>) -> Vec<String> {
    models.into_iter().filter(|m| m.files.iter().all(present)).map(|m| m.id).collect()
}

#[tauri::command]
pub fn model_download(app: AppHandle, state: State<'_, crate::AppState>, id: String, files: Vec<ModelFile>) -> std::result::Result<(), String> {
    state.downloads.clone().start(app, id, files).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn model_cancel_download(state: State<'_, crate::AppState>, id: String) {
    state.downloads.cancel(&id);
}

/// To the Recycle Bin, so a model deleted by mistake can be put back.
#[tauri::command]
pub fn model_delete(files: Vec<ModelFile>) -> std::result::Result<(), String> {
    for file in &files {
        let path = file_path(file);
        if path.exists() && trash::delete(&path).is_err() {
            std::fs::remove_file(&path).map_err(|e| e.to_string())?;
        }
        let _ = std::fs::remove_file(path.with_extension("part"));
    }
    Ok(())
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Progress {
    pub id: String,
    pub received: u64,
    pub total: u64,
    /// downloading, done, failed or cancelled.
    pub state: String,
    pub message: Option<String>,
    pub bytes_per_second: f64,
}

#[derive(Default)]
pub struct Downloads {
    active: Mutex<HashMap<String, Arc<AtomicBool>>>,
}

impl Downloads {
    pub fn cancel(&self, id: &str) {
        if let Some(flag) = self.active.lock().unwrap().get(id) {
            flag.store(true, Ordering::SeqCst);
        }
    }

    pub fn start(self: Arc<Self>, app: AppHandle, id: String, files: Vec<ModelFile>) -> Result<()> {
        let cancel = Arc::new(AtomicBool::new(false));
        {
            let mut active = self.active.lock().unwrap();
            if active.contains_key(&id) {
                return Ok(());
            }
            active.insert(id.clone(), cancel.clone());
        }
        let this = self;
        tauri::async_runtime::spawn(async move {
            let total: u64 = files.iter().map(|f| f.size).sum();
            let result = download_model(&app, &id, &files, total, &cancel).await;
            this.active.lock().unwrap().remove(&id);
            let (state, message) = match result {
                Ok(()) => ("done", None),
                Err(_) if cancel.load(Ordering::SeqCst) => ("cancelled", None),
                Err(error) => ("failed", Some(error.to_string())),
            };
            let received = if state == "done" { total } else { 0 };
            let _ = app.emit("download-progress", Progress { id, received, total, state: state.into(), message, bytes_per_second: 0.0 });
        });
        Ok(())
    }
}

async fn download_model(app: &AppHandle, id: &str, files: &[ModelFile], total: u64, cancel: &AtomicBool) -> Result<()> {
    std::fs::create_dir_all(crate::paths::models())?;
    let client = reqwest::Client::builder().connect_timeout(Duration::from_secs(10)).user_agent("Nomi").build()?;
    let mut done_before = 0u64;
    for file in files {
        let target = file_path(file);
        if std::fs::metadata(&target).is_ok_and(|m| m.len() == file.size) {
            done_before += file.size;
            continue;
        }
        let mut last_error = anyhow!("no source answered");
        let mut finished = false;
        for source in SOURCES {
            match download_file(app, &client, &format!("{source}/{}", file.path), file, id, done_before, total, cancel).await {
                Ok(()) => {
                    finished = true;
                    break;
                }
                Err(error) => {
                    if cancel.load(Ordering::SeqCst) {
                        return Err(error);
                    }
                    last_error = error;
                }
            }
        }
        if !finished {
            return Err(last_error);
        }
        done_before += file.size;
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
async fn download_file(
    app: &AppHandle,
    client: &reqwest::Client,
    url: &str,
    file: &ModelFile,
    id: &str,
    done_before: u64,
    total: u64,
    cancel: &AtomicBool,
) -> Result<()> {
    let target = file_path(file);
    let part = target.with_extension("part");
    let mut have = std::fs::metadata(&part).map(|m| m.len()).unwrap_or(0);
    if have > file.size {
        have = 0;
    }
    let mut request = client.get(url);
    if have > 0 {
        request = request.header("Range", format!("bytes={have}-"));
    }
    let response = request.send().await?;
    let status = response.status();
    if !status.is_success() {
        bail!("{url}: {status}");
    }
    // A server that ignores the range sends the whole file again.
    if status.as_u16() != 206 {
        have = 0;
    }
    let mut out = tokio::fs::OpenOptions::new().create(true).write(true).append(have > 0).truncate(have == 0).open(&part).await?;
    let mut stream = response.bytes_stream();
    let mut received = have;
    let mut last_sent = Instant::now() - Duration::from_secs(1);
    let mut window = (Instant::now(), received);
    let mut speed = 0.0;
    while let Some(chunk) = stream.next().await {
        if cancel.load(Ordering::SeqCst) {
            bail!("cancelled");
        }
        let chunk = chunk?;
        out.write_all(&chunk).await?;
        received += chunk.len() as u64;
        if last_sent.elapsed() >= Duration::from_millis(250) {
            let elapsed = window.0.elapsed().as_secs_f64();
            if elapsed >= 1.0 {
                speed = (received - window.1) as f64 / elapsed;
                window = (Instant::now(), received);
            }
            last_sent = Instant::now();
            let _ = app.emit(
                "download-progress",
                Progress { id: id.into(), received: done_before + received, total, state: "downloading".into(), message: None, bytes_per_second: speed },
            );
        }
    }
    out.flush().await?;
    drop(out);
    if received != file.size {
        bail!("{}: got {received} of {} bytes", file.file, file.size);
    }
    std::fs::rename(&part, &target)?;
    Ok(())
}
