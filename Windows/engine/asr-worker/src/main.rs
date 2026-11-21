//! Speech worker for Nomi on Windows. Same frames as the Mac's MLX `asr-worker`; the model is a
//! Qwen3-ASR GGUF file run by transcribe.cpp on the CPU or a GPU (Vulkan).
//!
//! asr-worker --model FILE.gguf          serve frames on stdin/stdout (started by moxin-engine)
//! asr-worker devices                    print the CPU and GPUs as JSON (used by the app's device check)
//!
//! Placement comes from the environment, which moxin-engine passes on from the app:
//! NOMI_ASR_DEVICE = auto (default) | cpu | gpu | gpu:N, NOMI_ASR_THREADS = N (0 = library default).

use anyhow::{anyhow, bail, Context, Result};
use serde::Serialize;
use std::io::{self, BufReader, Write};
use transcribe_cpp::{devices, init_backends_default, Backend, DeviceType, Feature, Model, ModelOptions, RunOptions, SessionOptions};
use voice_core::{pcm_from_bytes, read_frame, write_frame, WorkerEvent, WorkerRequest};

/// Phrases shorter than this (3 s) that come back far too long hold no real speech (as on the Mac).
const SHORT_PHRASE_SAMPLES: usize = 3 * 16_000;

fn main() -> Result<()> {
    init_backends_default().map_err(|error| anyhow!("loading compute backends: {error}"))?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(String::as_str) == Some("devices") {
        println!("{}", serde_json::to_string_pretty(&device_list())?);
        return Ok(());
    }
    let model_path = flag(&args, "--model").ok_or_else(|| anyhow!("asr-worker needs --model"))?;
    let mut stdout = io::stdout().lock();

    let (model, placed) = match load(&model_path) {
        Ok(loaded) => loaded,
        Err(error) => {
            let message = format!("识别模型加载失败：{error:#}");
            write_frame(&mut stdout, &WorkerEvent::LoadError { message: message.clone() }, &[])?;
            return Err(anyhow!(message));
        }
    };
    let threads: i32 = std::env::var("NOMI_ASR_THREADS").ok().and_then(|value| value.parse().ok()).unwrap_or(0);
    let mut session = match model.session_with(&SessionOptions { n_threads: threads, ..Default::default() }) {
        Ok(session) => session,
        Err(error) => {
            let message = format!("识别模型加载失败：{error}");
            write_frame(&mut stdout, &WorkerEvent::LoadError { message: message.clone() }, &[])?;
            return Err(anyhow!(message));
        }
    };
    let context_prompt = model.supports(Feature::ContextPrompt);
    eprintln!("asr-worker: {model_path} on {placed}, threads {threads}, context prompt {context_prompt}");
    // A short first pass so a GPU compiles its shaders before the first real phrase.
    let _ = session.run(&vec![0.0f32; 16_000], &RunOptions::default());
    write_frame(&mut stdout, &WorkerEvent::Ready, &[])?;

    let mut stdin = BufReader::new(io::stdin());
    loop {
        let (header, payload) = match read_frame(&mut stdin) {
            Ok(frame) => frame,
            Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => break,
            Err(error) => return Err(error.into()),
        };
        let request: WorkerRequest = serde_json::from_slice(&header)?;
        match request {
            WorkerRequest::Shutdown => break,
            WorkerRequest::Translate { id, .. } | WorkerRequest::Generate { id, .. } => {
                write_frame(&mut stdout, &WorkerEvent::Failed { id, message: "识别进程不翻译".into() }, &[])?;
            }
            WorkerRequest::Transcribe { id, language, context } => {
                let samples = pcm_from_bytes(&payload);
                let mut options = RunOptions::default();
                options.language = iso_language(&language);
                if context_prompt && !context.trim().is_empty() {
                    options.prompt = Some(context);
                }
                let event = match session.run(&samples, &options) {
                    Ok(transcript) => {
                        let mut text = transcript.text.trim().to_string();
                        // More text than a short phrase can hold is the model repeating its context.
                        let seconds = samples.len() as f64 / 16_000.0;
                        if samples.len() < SHORT_PHRASE_SAMPLES && text.chars().count() as f64 > 12.0 + seconds * 14.0 {
                            text.clear();
                        }
                        let named = transcript.language.as_deref().map(language_name).or_else(|| {
                            options.language.as_deref().map(language_name)
                        });
                        WorkerEvent::Transcript { id, text, language: named }
                    }
                    Err(error) => WorkerEvent::Failed { id, message: error.to_string() },
                };
                write_frame(&mut stdout, &event, &[])?;
            }
        }
        stdout.flush()?;
    }
    Ok(())
}

/// Loads on the requested device. With `auto`, the first GPU is tried and the CPU is the fallback,
/// so a PC whose GPU driver refuses the model still records.
fn load(path: &str) -> Result<(Model, String)> {
    let choice = std::env::var("NOMI_ASR_DEVICE").unwrap_or_else(|_| "auto".into());
    if choice == "auto" {
        if let Ok(options) = model_options("gpu") {
            match Model::load_with(path, &options) {
                Ok(model) => {
                    let placed = describe(&model);
                    return Ok((model, placed));
                }
                Err(error) => eprintln!("asr-worker: GPU load failed, using the CPU: {error}"),
            }
        }
        let model = Model::load_with(path, &model_options("cpu")?).map_err(|error| anyhow!("{error}"))?;
        let placed = describe(&model);
        return Ok((model, placed));
    }
    let model = Model::load_with(path, &model_options(&choice)?).map_err(|error| anyhow!("{error}"))?;
    let placed = describe(&model);
    Ok((model, placed))
}

fn describe(model: &Model) -> String {
    let device = model.device().map(|device| device.description).unwrap_or_else(|_| "CPU".into());
    format!("{} ({device})", model.backend())
}

/// `cpu`, `gpu` (the first GPU) or `gpu:N`.
fn model_options(choice: &str) -> Result<ModelOptions> {
    if choice == "cpu" {
        return Ok(ModelOptions { backend: Backend::Cpu, ..Default::default() });
    }
    let wanted: usize = match choice.strip_prefix("gpu") {
        Some("") => 0,
        Some(rest) => rest.trim_start_matches(':').parse().context("gpu:N needs a number")?,
        None => bail!("the device must be auto, cpu, gpu or gpu:N"),
    };
    let device = gpus().get(wanted).cloned().ok_or_else(|| anyhow!("no GPU number {wanted}"))?;
    let backend = match device.kind.to_lowercase().as_str() {
        "metal" => Backend::Metal,
        "vulkan" => Backend::Vulkan,
        "cuda" => Backend::Cuda,
        "rocm" | "hip" => Backend::Rocm,
        other => bail!("GPU backend {other} is not handled"),
    };
    Ok(ModelOptions { backend, device: Some(device), ..Default::default() })
}

fn gpus() -> Vec<transcribe_cpp::Device> {
    devices().into_iter().filter(|device| matches!(device.device_type, DeviceType::Gpu | DeviceType::Igpu)).collect()
}

#[derive(Serialize)]
struct DeviceInfo {
    index: usize,
    name: String,
    description: String,
    backend: String,
    /// cpu, gpu (discrete) or igpu (integrated).
    kind: String,
    memory_total_mb: u64,
    memory_free_mb: u64,
}

fn device_list() -> Vec<DeviceInfo> {
    devices()
        .into_iter()
        .enumerate()
        .map(|(index, device)| DeviceInfo {
            index,
            name: device.name,
            description: device.description,
            backend: device.kind,
            kind: format!("{:?}", device.device_type).to_lowercase(),
            memory_total_mb: device.memory_total / 1_048_576,
            memory_free_mb: device.memory_free / 1_048_576,
        })
        .collect()
}

/// The engine names languages ("Chinese", "auto"); transcribe.cpp wants ISO codes.
fn iso_language(name: &str) -> Option<String> {
    let lower = name.trim().to_lowercase();
    let code = match lower.as_str() {
        "" | "auto" => return None,
        "chinese" => "zh",
        "english" => "en",
        "japanese" => "ja",
        "korean" => "ko",
        "german" => "de",
        "french" => "fr",
        "spanish" => "es",
        "russian" => "ru",
        "arabic" => "ar",
        "cantonese" => "yue",
        other if other.len() <= 3 => other,
        _ => return None,
    };
    Some(code.to_string())
}

/// The engine's language lock compares names, as the Mac worker returns them.
fn language_name(code: &str) -> String {
    match code.trim().to_lowercase().as_str() {
        "zh" | "chinese" => "Chinese",
        "en" | "english" => "English",
        "ja" | "japanese" => "Japanese",
        "ko" | "korean" => "Korean",
        "de" | "german" => "German",
        "fr" | "french" => "French",
        "es" | "spanish" => "Spanish",
        "ru" | "russian" => "Russian",
        "ar" | "arabic" => "Arabic",
        "yue" | "cantonese" => "Cantonese",
        other => return other.to_string(),
    }
    .to_string()
}

fn flag(args: &[String], name: &str) -> Option<String> {
    args.iter().position(|arg| arg == name).and_then(|index| args.get(index + 1)).cloned().or_else(|| {
        args.iter().find_map(|arg| arg.strip_prefix(&format!("{name}=")).map(str::to_string))
    })
}

#[cfg(test)]
mod tests {
    use super::{iso_language, language_name};

    #[test]
    fn languages_go_both_ways() {
        assert_eq!(iso_language("Chinese").as_deref(), Some("zh"));
        assert_eq!(iso_language("auto"), None);
        assert_eq!(language_name("zh"), "Chinese");
        assert_eq!(language_name("en"), "English");
    }
}
