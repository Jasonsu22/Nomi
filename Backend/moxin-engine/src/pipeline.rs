use anyhow::{anyhow, Result};
use serde::Serialize;
use std::io::BufReader;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::time::{Duration, Instant};
use voice_core::{
    pcm_to_bytes, read_frame, write_frame, Committer, Vad, VadConfig, WorkerEvent, WorkerRequest,
};

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum OutEvent {
    State { value: String, asr: String, translator: String },
    Tail { text: String, start: f64, revision: u64 },
    Commit { id: u64, source: String, translation: String, start: f64, end: f64, tail: String },
    Level { rms: f32 },
    Error { code: String, message: String },
}

#[derive(Clone)]
pub struct ModelStatus {
    pub path: PathBuf,
    pub files_ready: bool,
    pub loaded: bool,
    pub error: Option<String>,
}

pub struct Pipeline {
    asr: Option<Worker>,
    llm: Option<Worker>,
    assistant: Option<Worker>,
    asr_status: ModelStatus,
    llm_status: ModelStatus,
    assistant_status: ModelStatus,
    vad: Vad,
    committer: Committer,
    source_language: String,
    target_language: String,
    translate: bool,
    clock: f64,
    last_level: f64,
    revision: u64,
    next_request: u64,
    translation_retry_at: Option<Instant>,
    translation_error_reported: bool,
    commit_error_reported: bool,
}

impl Pipeline {
    pub fn start(asr_path: PathBuf, llm_path: PathBuf, source_language: &str, target_language: &str) -> Result<Self> {
        let asr_status = inspect(&asr_path, &["config.json", "model.safetensors", "tokenizer.json"]);
        let llm_status = inspect(&llm_path, &["config.json", "model.safetensors", "tokenizer.json"]);
        let assistant_status = llm_status.clone();
        let mut pipeline = Self {
            asr: None,
            llm: None,
            assistant: None,
            asr_status,
            llm_status,
            assistant_status,
            vad: Vad::new(VadConfig::default()),
            committer: Committer::new(source_language),
            source_language: source_language.to_string(),
            target_language: target_language.to_string(),
            translate: wants_translation(target_language),
            clock: 0.0,
            last_level: 0.0,
            revision: 0,
            next_request: 1,
            translation_retry_at: None,
            translation_error_reported: false,
            commit_error_reported: false,
        };
        if pipeline.asr_status.files_ready {
            if let Err(error) = pipeline.load_asr() {
                pipeline.asr_status.error = Some(error.to_string());
            }
        }
        if pipeline.translate && pipeline.llm_status.files_ready {
            if let Err(error) = pipeline.load_llm() {
                pipeline.llm_status.error = Some(error.to_string());
            }
        }
        Ok(pipeline)
    }

    pub fn configure(&mut self, source_language: &str, target_language: &str) {
        self.source_language = source_language.to_string();
        self.target_language = target_language.to_string();
        self.translate = wants_translation(target_language);
        self.vad = Vad::new(VadConfig::default());
        self.committer = Committer::new(source_language);
        self.clock = 0.0;
        self.last_level = 0.0;
        self.revision = 0;
        self.translation_retry_at = None;
        self.translation_error_reported = false;
        self.commit_error_reported = false;
    }

    pub fn load_asr(&mut self) -> Result<()> {
        if self.asr.is_some() {
            return Ok(());
        }
        if !self.asr_status.files_ready {
            return Err(anyhow!("识别模型文件不完整：{}", self.asr_status.path.display()));
        }
        self.asr = Some(Worker::spawn("asr-worker", &self.asr_status.path)?);
        self.asr_status.loaded = true;
        self.asr_status.error = None;
        Ok(())
    }

    pub fn unload_asr(&mut self) {
        self.asr = None;
        self.asr_status.loaded = false;
    }

    pub fn load_llm(&mut self) -> Result<()> {
        if self.llm.is_some() {
            return Ok(());
        }
        if !self.llm_status.files_ready {
            return Err(anyhow!("翻译模型文件不完整：{}", self.llm_status.path.display()));
        }
        self.llm = Some(Worker::spawn("llm-worker", &self.llm_status.path)?);
        self.llm_status.loaded = true;
        self.llm_status.error = None;
        Ok(())
    }

    pub fn unload_llm(&mut self) {
        self.llm = None;
        self.llm_status.loaded = false;
    }

    pub fn select_model(&mut self, role: &str, path: PathBuf) -> Result<()> {
        let status = inspect(&path, &["config.json", "model.safetensors", "tokenizer.json"]);
        if !status.files_ready {
            return Err(anyhow!("模型文件不完整：{}", path.display()));
        }
        let config: serde_json::Value = serde_json::from_slice(&std::fs::read(path.join("config.json"))?)?;
        if role == "assistant" {
            if !matches!(config["model_type"].as_str(), Some("qwen3" | "qwen3_5")) {
                return Err(anyhow!("当前大模型架构不受支持"));
            }
            let previous = self.assistant_status();
            self.assistant = None;
            self.assistant_status = status;
            if let Err(error) = self.load_assistant() {
                let was_loaded = previous.loaded;
                self.assistant_status = ModelStatus { loaded: false, ..previous };
                if was_loaded {
                    if let Err(rollback) = self.load_assistant() {
                        self.assistant_status.error = Some(rollback.to_string());
                    }
                }
                return Err(error);
            }
            return Ok(());
        }
        let expected = match role {
            "asr" => "qwen3_asr",
            "translator" => "qwen3_5",
            _ => return Err(anyhow!("未知的模型类型")),
        };
        if config.get("model_type").and_then(|value| value.as_str()) != Some(expected) {
            return Err(anyhow!("当前引擎不支持这个模型架构"));
        }
        let previous = if role == "asr" {
            let previous = self.asr_status.clone();
            self.unload_asr();
            self.asr_status = status;
            previous
        } else {
            let previous = self.llm_status.clone();
            if path == self.assistant_status.path {
                self.assistant = None;
                self.assistant_status.loaded = false;
            }
            self.unload_llm();
            self.llm_status = status;
            previous
        };
        let result = if role == "asr" { self.load_asr() } else { self.load_llm() };
        if let Err(error) = result {
            let was_loaded = previous.loaded;
            if role == "asr" {
                self.asr_status = ModelStatus { loaded: false, ..previous };
                if was_loaded {
                    if let Err(rollback) = self.load_asr() {
                        self.asr_status.error = Some(rollback.to_string());
                    }
                }
            } else {
                self.llm_status = ModelStatus { loaded: false, ..previous };
                if was_loaded {
                    if let Err(rollback) = self.load_llm() {
                        self.llm_status.error = Some(rollback.to_string());
                    }
                }
            }
            return Err(error);
        }
        Ok(())
    }

    pub fn configure_assistant(&mut self, path: PathBuf) {
        self.assistant = None;
        self.assistant_status = inspect(&path, &["config.json", "model.safetensors", "tokenizer.json"]);
    }

    fn assistant_status(&self) -> ModelStatus {
        if self.assistant_status.path == self.llm_status.path {
            self.llm_status.clone()
        } else {
            ModelStatus { loaded: self.assistant.is_some(), ..self.assistant_status.clone() }
        }
    }

    fn load_assistant(&mut self) -> Result<()> {
        if self.assistant_status.path == self.llm_status.path {
            return self.load_llm();
        }
        if self.assistant.is_none() {
            self.assistant = Some(Worker::spawn("llm-worker", &self.assistant_status.path)?);
        }
        self.assistant_status.loaded = true;
        self.assistant_status.error = None;
        Ok(())
    }

    pub fn generate_assistant(&mut self, system: String, prompt: String, max_tokens: usize, on_text: &mut dyn FnMut(&str)) -> Result<String> {
        self.load_assistant()?;
        let id = self.next_request;
        self.next_request += 1;
        let worker = if self.assistant_status.path == self.llm_status.path {
            self.llm.as_mut().unwrap()
        } else {
            self.assistant.as_mut().unwrap()
        };
        write_frame(
            &mut worker.stdin,
            &WorkerRequest::Generate { id, system, prompt, max_tokens: max_tokens.clamp(1, 4096) },
            &[],
        )?;
        loop {
            let (header, _) = read_frame(&mut worker.stdout)?;
            match serde_json::from_slice::<WorkerEvent>(&header)? {
                WorkerEvent::Token { text, .. } => on_text(&text),
                WorkerEvent::Result { text, .. } => {
                    on_text(&text);
                    return Ok(text);
                }
                WorkerEvent::Failed { message, .. } => return Err(anyhow!(message)),
                other => return Err(anyhow!("大模型返回了无效结果：{other:?}")),
            }
        }
    }

    pub fn unload_path(&mut self, path: &Path) {
        if self.asr_status.path == path {
            self.unload_asr();
            self.asr_status.files_ready = false;
            self.asr_status.error = None;
        }
        if self.llm_status.path == path {
            self.unload_llm();
            self.llm_status.files_ready = false;
            self.llm_status.error = None;
        }
        if self.assistant_status.path == path {
            self.assistant = None;
            self.assistant_status.loaded = false;
            self.assistant_status.files_ready = false;
            self.assistant_status.error = None;
        }
    }

    pub fn asr_label(&self) -> &'static str {
        if self.asr_status.loaded {
            "ready"
        } else if self.asr_status.files_ready {
            "error"
        } else {
            "missing"
        }
    }

    pub fn translator_label(&self) -> &'static str {
        if !self.translate {
            "off"
        } else if self.llm_status.loaded {
            "ready"
        } else if self.llm_status.files_ready {
            "error"
        } else {
            "missing"
        }
    }

    pub fn status_json(&self) -> serde_json::Value {
        serde_json::json!({
            "asr": model_json(&self.asr_status),
            "translator": model_json(&self.llm_status),
            "assistant": model_json(&self.assistant_status()),
        })
    }

    pub fn push_audio(&mut self, samples: &[f32]) -> Vec<OutEvent> {
        let mut events = Vec::new();
        self.clock += samples.len() as f64 / 16_000.0;
        if self.clock - self.last_level >= 0.05 {
            self.last_level = self.clock;
            events.push(OutEvent::Level { rms: rms(samples) });
        }
        let segments = self.vad.push(samples);
        events.extend(self.consume(segments));
        events
    }

    pub fn finish(&mut self) -> Vec<OutEvent> {
        let mut segments = Vec::new();
        if let Some(segment) = self.vad.finish() {
            segments.push(segment);
        }
        let mut events = self.consume(segments);
        self.committer.request_flush();
        self.translation_retry_at = None;
        events.extend(self.drain_commits());
        events
    }

    pub fn poll_clock(&mut self) -> Vec<OutEvent> {
        self.drain_commits()
    }

    fn consume(&mut self, segments: Vec<voice_core::VadOutput>) -> Vec<OutEvent> {
        let mut events = Vec::new();
        if segments.is_empty() {
            return self.drain_commits();
        }
        for segment in segments {
            if self.asr.is_none() {
                events.push(OutEvent::Error {
                    code: "asr_missing".into(),
                    message: format!("找不到识别模型：{}", self.asr_status.path.display()),
                });
                continue;
            }
            let id = self.next_request;
            self.next_request += 1;
            let language = voice_core::asr_language(&self.source_language);
            let response = self.asr.as_mut().unwrap().request(
                WorkerRequest::Transcribe { id, language },
                &pcm_to_bytes(&segment.samples),
            );
            let text = match response {
                Ok(WorkerEvent::Result { text, .. }) => text,
                Ok(WorkerEvent::Failed { message, .. }) => {
                    events.push(OutEvent::Error { code: "asr_failed".into(), message });
                    continue;
                }
                Ok(other) => {
                    events.push(OutEvent::Error { code: "asr_failed".into(), message: format!("{other:?}") });
                    continue;
                }
                Err(error) => {
                    events.push(OutEvent::Error { code: "asr_failed".into(), message: error.to_string() });
                    continue;
                }
            };
            // Idle is decided from the previous chunk's clock. Refreshing it first
            // would hide a fragment that has already been sitting for 9 seconds.
            events.extend(self.drain_commits());
            self.committer.observe(segment.burst_id, &text, segment.start, segment.end, segment.is_final, segment.hit_limit);
            self.revision += 1;
            events.push(OutEvent::Tail {
                text: self.committer.tail(),
                start: segment.start,
                revision: self.revision,
            });
            events.extend(self.drain_commits());
        }
        events
    }

    fn drain_commits(&mut self) -> Vec<OutEvent> {
        let mut events = Vec::new();
        loop {
            if self.committer.pending_draft().is_some()
                && self.translation_retry_at.is_some_and(|at| Instant::now() < at)
            {
                break;
            }
            let Some(draft) = self.committer.pending_draft().or_else(|| self.committer.poll(Instant::now())) else {
                break;
            };
            let translation = if self.translate {
                match self.translate_draft(&draft.source) {
                    Ok(text) => {
                        self.translation_retry_at = None;
                        self.translation_error_reported = false;
                        text
                    }
                    Err(message) => {
                        // One attempt per drain. The draft stays pending and is tried again
                        // a second later, instead of committing the source with an empty translation.
                        self.translation_retry_at = Some(Instant::now() + Duration::from_secs(1));
                        if !self.translation_error_reported {
                            self.translation_error_reported = true;
                            events.push(OutEvent::Error { code: "translator_failed".into(), message });
                        }
                        break;
                    }
                }
            } else {
                String::new()
            };
            match self.committer.finish_pending(draft.id) {
                Ok(tail) => {
                    self.commit_error_reported = false;
                    events.push(OutEvent::Commit {
                        id: draft.id,
                        source: draft.source,
                        translation,
                        start: draft.start,
                        end: draft.end,
                        tail,
                    })
                }
                Err(message) => {
                    if !self.commit_error_reported {
                        self.commit_error_reported = true;
                        events.push(OutEvent::Error { code: "commit_failed".into(), message });
                    }
                    break;
                }
            }
        }
        events
    }

    fn translate_draft(&mut self, source: &str) -> Result<String, String> {
        let Some(llm) = self.llm.as_mut() else {
            return Err("翻译模型没有加载".into());
        };
        let id = self.next_request;
        self.next_request += 1;
        match llm.request(
            WorkerRequest::Translate {
                id,
                text: source.to_string(),
                target_language: self.target_language.clone(),
            },
            &[],
        ) {
            Ok(WorkerEvent::Result { text, .. }) => Ok(text),
            Ok(WorkerEvent::Failed { message, .. }) => Err(message),
            Err(error) => Err(error.to_string()),
            Ok(other) => Err(format!("{other:?}")),
        }
    }
}

fn wants_translation(target_language: &str) -> bool {
    !matches!(target_language, "none" | "off" | "")
}

fn model_json(status: &ModelStatus) -> serde_json::Value {
    serde_json::json!({
        "path": status.path,
        "files": if status.files_ready { "complete" } else { "missing" },
        "loaded": status.loaded,
        "memoryBytes": null,
        "error": status.error,
    })
}

fn inspect(path: &Path, required: &[&str]) -> ModelStatus {
    ModelStatus {
        path: path.to_path_buf(),
        files_ready: required.iter().filter(|name| **name != "model.safetensors" && **name != "tokenizer.json")
            .all(|name| nonempty_file(&path.join(name))) && tokenizer_ready(path) && weights_ready(path),
        loaded: false,
        error: None,
    }
}

fn nonempty_file(path: &Path) -> bool {
    std::fs::metadata(path).is_ok_and(|metadata| metadata.is_file() && metadata.len() > 0)
}

fn tokenizer_ready(path: &Path) -> bool {
    if nonempty_file(&path.join("tokenizer.json")) {
        return true;
    }
    let config = std::fs::read(path.join("config.json")).ok()
        .and_then(|data| serde_json::from_slice::<serde_json::Value>(&data).ok());
    config.as_ref().and_then(|value| value.get("model_type")).and_then(|value| value.as_str()) == Some("qwen3_asr")
        && nonempty_file(&path.join("vocab.json")) && nonempty_file(&path.join("merges.txt"))
}

fn weights_ready(path: &Path) -> bool {
    let index = path.join("model.safetensors.index.json");
    if index.is_file() {
        let files = std::fs::read(index).ok()
            .and_then(|data| serde_json::from_slice::<serde_json::Value>(&data).ok());
        return files.as_ref().and_then(|value| value.get("weight_map"))
            .and_then(|value| value.as_object()).is_some_and(|weights| {
                !weights.is_empty() && weights.values().all(|value| {
                    value.as_str().is_some_and(|name| {
                        !name.contains('/') && !name.contains('\\') && nonempty_file(&path.join(name))
                    })
                })
            });
    }
    nonempty_file(&path.join("model.safetensors"))
}

fn rms(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    (samples.iter().map(|sample| sample * sample).sum::<f32>() / samples.len() as f32).sqrt()
}

struct Worker {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<std::process::ChildStdout>,
}

impl Worker {
    fn spawn(name: &str, model: &Path) -> Result<Self> {
        let binary = worker_binary(name)?;
        let mut child = Command::new(binary)
            .arg("--model")
            .arg(model)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()?;
        let stdin = child.stdin.take().ok_or_else(|| anyhow!("{name} 没有标准输入"))?;
        let stdout = BufReader::new(child.stdout.take().ok_or_else(|| anyhow!("{name} 没有标准输出"))?);
        let mut worker = Self { child, stdin, stdout };
        match read_frame(&mut worker.stdout) {
            Ok((header, _)) => match serde_json::from_slice::<WorkerEvent>(&header)? {
                WorkerEvent::Ready => Ok(worker),
                WorkerEvent::LoadError { message } => Err(anyhow!(message)),
                other => Err(anyhow!("{name} 的第一帧不是就绪：{other:?}")),
            },
            Err(error) => Err(anyhow!("{name} 在就绪前退出：{error}")),
        }
    }

    fn request(&mut self, request: WorkerRequest, payload: &[u8]) -> Result<WorkerEvent> {
        write_frame(&mut self.stdin, &request, payload)?;
        let (header, _) = read_frame(&mut self.stdout)?;
        Ok(serde_json::from_slice(&header)?)
    }
}

impl Drop for Worker {
    fn drop(&mut self) {
        let _ = write_frame(&mut self.stdin, &WorkerRequest::Shutdown, &[]);
        let _ = self.child.wait();
    }
}

fn worker_binary(name: &str) -> Result<PathBuf> {
    if let Ok(path) = std::env::var(format!("{}_BIN", name.replace('-', "_").to_uppercase())) {
        return Ok(PathBuf::from(path));
    }
    let sibling = std::env::current_exe()?.parent().unwrap_or(Path::new(".")).join(name);
    if sibling.is_file() {
        return Ok(sibling);
    }
    Err(anyhow!("找不到 {name}，它应该和 moxin-engine 放在同一个目录"))
}

pub fn read_wav(path: &Path) -> Result<Vec<f32>> {
    let mut reader = hound::WavReader::open(path)?;
    let spec = reader.spec();
    let samples: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Float => reader.samples::<f32>().collect::<std::result::Result<Vec<_>, _>>()?,
        hound::SampleFormat::Int => reader
            .samples::<i32>()
            .map(|sample| sample.map(|sample| sample as f32 / 2f32.powi(spec.bits_per_sample.min(31) as i32 - 1)))
            .collect::<std::result::Result<Vec<_>, _>>()?,
    };
    let mono = if spec.channels <= 1 {
        samples
    } else {
        samples.chunks(spec.channels as usize).map(|frame| frame.iter().sum::<f32>() / frame.len() as f32).collect()
    };
    Ok(resample(mono, spec.sample_rate, 16_000))
}

fn resample(samples: Vec<f32>, from: u32, to: u32) -> Vec<f32> {
    if from == to || samples.is_empty() {
        return samples;
    }
    let ratio = from as f64 / to as f64;
    let output_len = (samples.len() as f64 / ratio) as usize;
    (0..output_len)
        .map(|index| {
            let position = index as f64 * ratio;
            let left = position.floor() as usize;
            let right = (left + 1).min(samples.len() - 1);
            let mix = (position - left as f64) as f32;
            samples[left] * (1.0 - mix) + samples[right] * mix
        })
        .collect()
}
