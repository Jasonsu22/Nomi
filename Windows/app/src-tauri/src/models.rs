//! The model files Nomi can use, and their downloads. Each file comes from the first source that
//! answers: huggingface.co, then hf-mirror.com (huggingface.co is blocked in mainland China).
//! A download resumes from its `.part` file and is checked against its size.

use anyhow::{anyhow, bail, Result};
use futures_util::StreamExt;
use serde::Serialize;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter};
use tokio::io::AsyncWriteExt;

const SOURCES: [&str; 2] = ["https://huggingface.co", "https://hf-mirror.com"];

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelFile {
    pub file: &'static str,
    pub path: &'static str,
    pub size: u64,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelInfo {
    pub id: &'static str,
    /// asr, llm or speakers.
    pub role: &'static str,
    pub name: &'static str,
    /// Which sets it belongs to: Lite, Standard, Full.
    pub sets: &'static [&'static str],
    pub files: Vec<ModelFile>,
}

const SEGMENTATION: ModelFile = ModelFile {
    file: "pyannote-segmentation-3.0.onnx",
    path: "csukuangfj/sherpa-onnx-pyannote-segmentation-3-0/resolve/main/model.onnx",
    size: 5_992_913,
};

pub fn catalogue() -> Vec<ModelInfo> {
    vec![
        ModelInfo {
            id: "qwen3-asr-0.6b", role: "asr", name: "Qwen3-ASR 0.6B", sets: &["Lite", "Standard"],
            files: vec![ModelFile { file: "Qwen3-ASR-0.6B-Q8_0.gguf", path: "handy-computer/Qwen3-ASR-0.6B-gguf/resolve/main/Qwen3-ASR-0.6B-Q8_0.gguf", size: 850_423_456 }],
        },
        ModelInfo {
            id: "qwen3-asr-1.7b", role: "asr", name: "Qwen3-ASR 1.7B", sets: &["Full"],
            files: vec![ModelFile { file: "Qwen3-ASR-1.7B-Q8_0.gguf", path: "handy-computer/Qwen3-ASR-1.7B-gguf/resolve/main/Qwen3-ASR-1.7B-Q8_0.gguf", size: 2_185_030_624 }],
        },
        ModelInfo {
            id: "qwen3.5-0.8b", role: "llm", name: "Qwen3.5 0.8B", sets: &["Lite"],
            files: vec![ModelFile { file: "Qwen3.5-0.8B-Q4_K_M.gguf", path: "unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf", size: 532_517_120 }],
        },
        ModelInfo {
            id: "qwen3.5-2b", role: "llm", name: "Qwen3.5 2B", sets: &["Standard", "Full"],
            files: vec![ModelFile { file: "Qwen3.5-2B-Q4_K_M.gguf", path: "unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-Q4_K_M.gguf", size: 1_280_835_840 }],
        },
        ModelInfo {
            id: "standard", role: "speakers", name: "Standard (pyannote + WeSpeaker)", sets: &["Lite", "Standard", "Full"],
            files: vec![
                SEGMENTATION,
                ModelFile { file: "wespeaker-resnet34.onnx", path: "csukuangfj/speaker-embedding-models/resolve/main/wespeaker_en_voxceleb_resnet34_LM.onnx", size: 26_530_550 },
            ],
        },
        ModelInfo {
            id: "zh-en", role: "speakers", name: "Chinese + English (pyannote + CAM++)", sets: &[],
            files: vec![
                SEGMENTATION,
                ModelFile { file: "campplus-zh-en.onnx", path: "csukuangfj/speaker-embedding-models/resolve/main/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx", size: 28_281_165 },
            ],
        },
    ]
}

pub fn find(id: &str) -> Option<ModelInfo> {
    catalogue().into_iter().find(|model| model.id == id)
}

pub fn file_path(file: &ModelFile) -> PathBuf {
    crate::paths::models().join(file.file)
}

pub fn is_ready(model: &ModelInfo) -> bool {
    model.files.iter().all(|file| std::fs::metadata(file_path(file)).is_ok_and(|m| m.len() == file.size))
}

/// The main file of a model: the GGUF for speech and translation.
pub fn main_path(id: &str) -> Option<PathBuf> {
    find(id).map(|model| file_path(&model.files[model.files.len() - 1]))
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
    pub fn is_active(&self, id: &str) -> bool {
        self.active.lock().unwrap().contains_key(id)
    }

    pub fn cancel(&self, id: &str) {
        if let Some(flag) = self.active.lock().unwrap().get(id) {
            flag.store(true, Ordering::SeqCst);
        }
    }

    pub fn start(self: &Arc<Self>, app: AppHandle, id: String) -> Result<()> {
        let model = find(&id).ok_or_else(|| anyhow!("unknown model {id}"))?;
        let cancel = Arc::new(AtomicBool::new(false));
        {
            let mut active = self.active.lock().unwrap();
            if active.contains_key(&id) {
                return Ok(());
            }
            active.insert(id.clone(), cancel.clone());
        }
        let this = self.clone();
        tauri::async_runtime::spawn(async move {
            let total: u64 = model.files.iter().map(|f| f.size).sum();
            let result = download_model(&app, &model, total, &cancel).await;
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

async fn download_model(app: &AppHandle, model: &ModelInfo, total: u64, cancel: &AtomicBool) -> Result<()> {
    std::fs::create_dir_all(crate::paths::models())?;
    let client = reqwest::Client::builder().connect_timeout(Duration::from_secs(10)).user_agent("Nomi").build()?;
    let mut done_before = 0u64;
    for file in &model.files {
        let target = file_path(file);
        if std::fs::metadata(&target).is_ok_and(|m| m.len() == file.size) {
            done_before += file.size;
            continue;
        }
        let mut last_error = anyhow!("no source answered");
        let mut finished = false;
        for source in SOURCES {
            match download_file(app, &client, &format!("{source}/{}", file.path), file, &model.id, done_before, total, cancel).await {
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
