//! asr-bench: runs a speech model on recorded lectures the way Nomi does live, and reports
//! whether this PC keeps up.
//!
//!     asr-bench devices
//!     asr-bench run --model qwen3-asr-0.6b-Q8_0.gguf --device cpu --audio lecture.wav [--audio …]
//!               [--threads N] [--language zh|en|auto] [--json out.json]
//!
//! Each WAV goes through Nomi's own phrase cutter (`voice-core`), as in the engine. Every
//! phrase is transcribed when it ends, and long phrases also get a pass every 1.5 s of speech
//! while they grow (the grey interim text). The engine skips an interim pass when the model is
//! still busy; this tool runs them all, so its numbers are a safe upper bound.

use anyhow::{anyhow, bail, Context, Result};
use serde::Serialize;
use std::path::{Path, PathBuf};
use std::time::Instant;
use transcribe_cpp::{devices, init_backends_default, Backend, DeviceType, Feature, Model, ModelOptions, RunOptions, SessionOptions};
use voice_core::{Vad, VadConfig};

const RATE: u32 = 16_000;
/// The engine feeds the phrase cutter in 0.1 s pieces.
const CHUNK: usize = 1_600;
/// Context handed to the model: the end of what was already said, as the engine does.
const CONTEXT_CHARS: usize = 200;

fn main() -> Result<()> {
    init_backends_default().map_err(|error| anyhow!("loading compute backends: {error}"))?;
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("devices") => print_devices(),
        Some("run") => run(&args[1..]),
        _ => {
            eprintln!("usage: asr-bench devices | asr-bench run --model M --device cpu|gpu[:N] --audio WAV …");
            std::process::exit(2);
        }
    }
}

#[derive(Serialize)]
struct DeviceInfo {
    index: usize,
    name: String,
    description: String,
    kind: String,
    device_type: String,
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
            kind: device.kind,
            device_type: format!("{:?}", device.device_type).to_lowercase(),
            memory_total_mb: device.memory_total / 1_048_576,
            memory_free_mb: device.memory_free / 1_048_576,
        })
        .collect()
}

fn print_devices() -> Result<()> {
    println!("{}", serde_json::to_string_pretty(&device_list())?);
    Ok(())
}

/// `cpu`, `gpu` (the first GPU) or `gpu:N` (the Nth GPU, counting from 0).
fn model_options(choice: &str) -> Result<ModelOptions> {
    if choice == "cpu" {
        return Ok(ModelOptions { backend: Backend::Cpu, ..Default::default() });
    }
    let wanted: usize = match choice.strip_prefix("gpu") {
        Some("") => 0,
        Some(rest) => rest.trim_start_matches(':').parse().context("--device gpu:N needs a number")?,
        None => bail!("--device must be cpu, gpu or gpu:N"),
    };
    let gpus: Vec<_> = devices()
        .into_iter()
        .filter(|device| matches!(device.device_type, DeviceType::Gpu | DeviceType::Igpu))
        .collect();
    let device = gpus.get(wanted).cloned().ok_or_else(|| anyhow!("no GPU number {wanted}; this PC has {}", gpus.len()))?;
    let backend = match device.kind.to_lowercase().as_str() {
        "metal" => Backend::Metal,
        "vulkan" => Backend::Vulkan,
        "cuda" => Backend::Cuda,
        "rocm" | "hip" => Backend::Rocm,
        other => bail!("GPU backend {other} is not handled"),
    };
    Ok(ModelOptions { backend, device: Some(device), ..Default::default() })
}

#[derive(Serialize)]
struct Call {
    final_pass: bool,
    audio_seconds: f64,
    compute_ms: f64,
}

#[derive(Serialize)]
struct ClipReport {
    file: String,
    audio_seconds: f64,
    phrases: usize,
    interim_passes: usize,
    /// All model time divided by the clip's length. Under 1.0 keeps up; under 0.5 leaves room
    /// for translation and the rest of the PC.
    load: f64,
    /// Same, counting only the end-of-phrase passes (interim text turned off).
    load_without_interim: f64,
    final_latency_ms_mean: f64,
    final_latency_ms_p90: f64,
    final_latency_ms_max: f64,
    transcript: String,
}

#[derive(Serialize)]
struct Report {
    tool: &'static str,
    model: String,
    device_requested: String,
    backend: String,
    device: String,
    threads: i32,
    language: String,
    load_seconds: f64,
    context_prompt: bool,
    clips: Vec<ClipReport>,
    load: f64,
    load_without_interim: f64,
}

fn run(args: &[String]) -> Result<()> {
    let model_path = flag(args, "--model").ok_or_else(|| anyhow!("--model is required"))?;
    let device = flag(args, "--device").unwrap_or_else(|| "cpu".into());
    let threads: i32 = flag(args, "--threads").map(|value| value.parse()).transpose()?.unwrap_or(0);
    let language = flag(args, "--language").unwrap_or_else(|| "auto".into());
    let audio: Vec<PathBuf> = flags(args, "--audio").into_iter().map(PathBuf::from).collect();
    if audio.is_empty() {
        bail!("give at least one --audio file");
    }

    let started = Instant::now();
    let model = Model::load_with(&model_path, &model_options(&device)?).map_err(|error| anyhow!("loading the model: {error}"))?;
    let mut session = model
        .session_with(&SessionOptions { n_threads: threads, ..Default::default() })
        .map_err(|error| anyhow!("opening a session: {error}"))?;
    let load_seconds = started.elapsed().as_secs_f64();
    let context_prompt = model.supports(Feature::ContextPrompt);
    let bound = model.device().map(|device| device.description).unwrap_or_default();
    eprintln!("loaded {model_path} on {} ({bound}) in {load_seconds:.1} s", model.backend());

    // A first, short pass so the GPU compiles its shaders before anything is timed.
    let _ = session.run(&vec![0.0f32; RATE as usize], &RunOptions::default());

    let mut clips = Vec::new();
    for path in &audio {
        let pcm = read_wav(path)?;
        let audio_seconds = pcm.len() as f64 / RATE as f64;
        eprintln!("{}: {:.0} s of audio", path.display(), audio_seconds);
        let mut vad = Vad::new(VadConfig::default());
        let mut segments = Vec::new();
        for chunk in pcm.chunks(CHUNK) {
            segments.extend(vad.push(chunk));
        }
        segments.extend(vad.finish());

        let mut calls = Vec::new();
        let mut finals: Vec<String> = Vec::new();
        for segment in segments {
            let mut options = RunOptions::default();
            if language != "auto" {
                options.language = Some(language.clone());
            }
            if context_prompt {
                let said = finals.join(" ");
                let tail: String = said.chars().rev().take(CONTEXT_CHARS).collect::<Vec<_>>().into_iter().rev().collect();
                if !tail.trim().is_empty() {
                    options.prompt = Some(tail);
                }
            }
            let clock = Instant::now();
            let result = session.run(&segment.samples, &options);
            let compute_ms = clock.elapsed().as_secs_f64() * 1000.0;
            calls.push(Call { final_pass: segment.is_final, audio_seconds: segment.samples.len() as f64 / RATE as f64, compute_ms });
            match result {
                Ok(transcript) if segment.is_final => finals.push(transcript.text.trim().to_string()),
                Ok(_) => {}
                Err(error) => eprintln!("  a phrase failed: {error}"),
            }
        }

        let total: f64 = calls.iter().map(|call| call.compute_ms).sum::<f64>() / 1000.0;
        let mut final_ms: Vec<f64> = calls.iter().filter(|call| call.final_pass).map(|call| call.compute_ms).collect();
        let final_total: f64 = final_ms.iter().sum::<f64>() / 1000.0;
        final_ms.sort_by(|a, b| a.total_cmp(b));
        let report = ClipReport {
            file: path.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default(),
            audio_seconds,
            phrases: final_ms.len(),
            interim_passes: calls.iter().filter(|call| !call.final_pass).count(),
            load: total / audio_seconds,
            load_without_interim: final_total / audio_seconds,
            final_latency_ms_mean: mean(&final_ms),
            final_latency_ms_p90: percentile(&final_ms, 0.9),
            final_latency_ms_max: final_ms.last().copied().unwrap_or(0.0),
            transcript: finals.join("\n"),
        };
        eprintln!(
            "  {} phrases, load {:.2} (without interim {:.2}), phrase latency mean {:.0} ms, p90 {:.0} ms",
            report.phrases, report.load, report.load_without_interim, report.final_latency_ms_mean, report.final_latency_ms_p90
        );
        clips.push(report);
    }

    let audio_total: f64 = clips.iter().map(|clip| clip.audio_seconds).sum();
    let load = clips.iter().map(|clip| clip.load * clip.audio_seconds).sum::<f64>() / audio_total;
    let load_without_interim = clips.iter().map(|clip| clip.load_without_interim * clip.audio_seconds).sum::<f64>() / audio_total;
    let report = Report {
        tool: "asr-bench",
        model: Path::new(&model_path).file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default(),
        device_requested: device,
        backend: model.backend(),
        device: bound,
        threads,
        language,
        load_seconds,
        context_prompt,
        clips,
        load,
        load_without_interim,
    };
    let json = serde_json::to_string_pretty(&report)?;
    match flag(args, "--json") {
        Some(path) => std::fs::write(&path, json)?,
        None => println!("{json}"),
    }
    Ok(())
}

/// 16 kHz mono f32. Other rates are resampled linearly and channels are averaged, which is
/// enough for a speed test; the app itself will resample properly.
fn read_wav(path: &Path) -> Result<Vec<f32>> {
    let mut reader = hound::WavReader::open(path).with_context(|| format!("opening {}", path.display()))?;
    let spec = reader.spec();
    let channels = spec.channels.max(1) as usize;
    let samples: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Float => reader.samples::<f32>().collect::<Result<_, _>>()?,
        hound::SampleFormat::Int => {
            let scale = (1i64 << (spec.bits_per_sample - 1)) as f32;
            reader.samples::<i32>().map(|sample| sample.map(|value| value as f32 / scale)).collect::<Result<_, _>>()?
        }
    };
    let mono: Vec<f32> = samples.chunks(channels).map(|frame| frame.iter().sum::<f32>() / channels as f32).collect();
    if spec.sample_rate == RATE {
        return Ok(mono);
    }
    let ratio = spec.sample_rate as f64 / RATE as f64;
    let length = (mono.len() as f64 / ratio) as usize;
    Ok((0..length)
        .map(|index| {
            let position = index as f64 * ratio;
            let left = position.floor() as usize;
            let right = (left + 1).min(mono.len() - 1);
            let fraction = (position - left as f64) as f32;
            mono[left] * (1.0 - fraction) + mono[right] * fraction
        })
        .collect())
}

fn mean(values: &[f64]) -> f64 {
    if values.is_empty() { 0.0 } else { values.iter().sum::<f64>() / values.len() as f64 }
}

/// `values` must be sorted.
fn percentile(values: &[f64], fraction: f64) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    values[((values.len() - 1) as f64 * fraction).round() as usize]
}

fn flag(args: &[String], name: &str) -> Option<String> {
    flags(args, name).into_iter().next()
}

fn flags(args: &[String], name: &str) -> Vec<String> {
    let mut found = Vec::new();
    let mut index = 0;
    while index < args.len() {
        if args[index] == name {
            if let Some(value) = args.get(index + 1) {
                found.push(value.clone());
            }
            index += 2;
        } else if let Some(value) = args[index].strip_prefix(&format!("{name}=")) {
            found.push(value.to_string());
            index += 1;
        } else {
            index += 1;
        }
    }
    found
}
