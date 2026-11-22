//! llm-bench: translates lecture sentences with Nomi's translation prompt and reports how fast
//! this PC does it.
//!
//!     llm-bench devices
//!     llm-bench run --model Qwen3.5-2B-Q4_K_M.gguf --device cpu|gpu[:N] --sentences sentences.txt
//!               [--target zh|en] [--threads N] [--pace SECONDS] [--for SECONDS] [--json out.json]
//!
//! `--pace` starts one sentence every N seconds, as phrases arrive during a lecture, and
//! `--for` keeps going for that long. Run it next to asr-bench to measure both models at once.

use anyhow::{anyhow, bail, Context, Result};
use llama_cpp_2::context::params::LlamaContextParams;
use llama_cpp_2::llama_backend::LlamaBackend;
use llama_cpp_2::llama_batch::LlamaBatch;
use llama_cpp_2::model::params::LlamaModelParams;
use llama_cpp_2::model::LlamaModel;
use llama_cpp_2::sampling::LlamaSampler;
use minijinja::{context, Environment};
use serde::Serialize;
use std::num::NonZeroU32;
use std::path::Path;
use std::time::{Duration, Instant};

/// A translated phrase is short; this only stops a runaway reply.
const MAX_TOKENS: usize = 256;

fn main() -> Result<()> {
    load_backends();
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("devices") => {
            let backend = LlamaBackend::init()?;
            drop(backend);
            println!("{}", serde_json::to_string_pretty(&device_list())?);
            Ok(())
        }
        Some("run") => run(&args[1..]),
        _ => {
            eprintln!("usage: llm-bench devices | llm-bench run --model M --device cpu|gpu[:N] --sentences FILE");
            std::process::exit(2);
        }
    }
}

/// On Windows and Linux the CPU and GPU backends are separate libraries next to the program.
#[cfg(not(target_os = "macos"))]
fn load_backends() {
    if let Some(folder) = std::env::current_exe().ok().and_then(|exe| exe.parent().map(Path::to_path_buf)) {
        llama_cpp_2::llama_backend::load_backends_from_path(&folder);
    }
}

#[cfg(target_os = "macos")]
fn load_backends() {}

#[derive(Serialize)]
struct DeviceInfo {
    index: usize,
    name: String,
    description: String,
    backend: String,
    memory_total_mb: usize,
}

fn device_list() -> Vec<DeviceInfo> {
    llama_cpp_2::list_llama_ggml_backend_devices()
        .into_iter()
        .map(|device| DeviceInfo {
            index: device.index,
            name: device.name,
            description: device.description,
            backend: device.backend,
            memory_total_mb: device.memory_total / 1_048_576,
        })
        .collect()
}

#[derive(Serialize)]
struct Sentence {
    source: String,
    translation: String,
    prompt_tokens: usize,
    output_tokens: usize,
    /// Reading the prompt.
    prompt_ms: f64,
    /// From the start until the whole translation is written: what the student waits for.
    total_ms: f64,
    tokens_per_second: f64,
    /// How long it waited for its turn because the one before was not done (paced runs).
    queued_ms: f64,
}

#[derive(Serialize)]
struct Report {
    tool: &'static str,
    model: String,
    device_requested: String,
    devices_used: Vec<String>,
    threads: i32,
    target: String,
    load_seconds: f64,
    pace_seconds: f64,
    sentences: Vec<Sentence>,
    total_ms_mean: f64,
    total_ms_p90: f64,
    total_ms_max: f64,
    tokens_per_second_mean: f64,
}

fn run(args: &[String]) -> Result<()> {
    let model_path = flag(args, "--model").ok_or_else(|| anyhow!("--model is required"))?;
    let device = flag(args, "--device").unwrap_or_else(|| "cpu".into());
    let threads: i32 = flag(args, "--threads").map(|value| value.parse()).transpose()?.unwrap_or(0);
    let target = flag(args, "--target").unwrap_or_else(|| "zh".into());
    let pace: f64 = flag(args, "--pace").map(|value| value.parse()).transpose()?.unwrap_or(0.0);
    let run_for: f64 = flag(args, "--for").map(|value| value.parse()).transpose()?.unwrap_or(0.0);
    let sentences_path = flag(args, "--sentences").ok_or_else(|| anyhow!("--sentences is required"))?;
    let sentences: Vec<String> = std::fs::read_to_string(&sentences_path)
        .with_context(|| format!("reading {sentences_path}"))?
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .map(String::from)
        .collect();
    if sentences.is_empty() {
        bail!("{sentences_path} has no sentences");
    }

    let backend = LlamaBackend::init()?;
    let started = Instant::now();
    let (params, devices_used) = model_params(&device)?;
    let model = LlamaModel::load_from_file(&backend, &model_path, &params).map_err(|error| anyhow!("loading the model: {error}"))?;
    let mut context_params = LlamaContextParams::default().with_n_ctx(NonZeroU32::new(2048));
    if threads > 0 {
        context_params = context_params.with_n_threads(threads).with_n_threads_batch(threads);
    }
    if device == "cpu" {
        // Keep everything on the CPU, including the large prompt batches llama.cpp would
        // otherwise hand to a GPU.
        context_params = context_params.with_op_offload(false).with_offload_kqv(false);
    }
    let mut ctx = model.new_context(&backend, context_params).map_err(|error| anyhow!("creating a context: {error}"))?;
    let load_seconds = started.elapsed().as_secs_f64();
    let template = model
        .chat_template(None)
        .map_err(|error| anyhow!("the model has no chat template: {error}"))?
        .to_string()?;
    eprintln!("loaded {model_path} on {} in {load_seconds:.1} s", devices_used.join(", "));

    let language = translation_language(&target);
    let system = format!(
        "/no_think You are a translation engine. Translate the source text into {language}. Output only the translated text. Do not include source/translation labels, do not explain, do not repeat the source."
    );

    // One untimed sentence so a GPU compiles its shaders first.
    let _ = translate(&model, &mut ctx, &template, &system, &sentences[0]);

    let mut results = Vec::new();
    let clock = Instant::now();
    let mut next_start = 0.0f64;
    let mut index = 0usize;
    loop {
        let elapsed = clock.elapsed().as_secs_f64();
        let more = if run_for > 0.0 { elapsed < run_for } else { index < sentences.len() };
        if !more {
            break;
        }
        let mut queued_ms = 0.0;
        if pace > 0.0 {
            if elapsed < next_start {
                std::thread::sleep(Duration::from_secs_f64(next_start - elapsed));
            } else {
                queued_ms = (elapsed - next_start) * 1000.0;
            }
            next_start += pace;
        }
        let source = &sentences[index % sentences.len()];
        let mut sentence = translate(&model, &mut ctx, &template, &system, source)?;
        sentence.queued_ms = queued_ms;
        eprintln!("  {:>5.0} ms  {:>5.1} tok/s  {}", sentence.total_ms, sentence.tokens_per_second, sentence.translation.replace('\n', " "));
        results.push(sentence);
        index += 1;
    }

    let mut totals: Vec<f64> = results.iter().map(|sentence| sentence.total_ms).collect();
    totals.sort_by(|a, b| a.total_cmp(b));
    let speeds: Vec<f64> = results.iter().map(|sentence| sentence.tokens_per_second).collect();
    let report = Report {
        tool: "llm-bench",
        model: Path::new(&model_path).file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default(),
        device_requested: device,
        devices_used,
        threads,
        target,
        load_seconds,
        pace_seconds: pace,
        total_ms_mean: mean(&totals),
        total_ms_p90: percentile(&totals, 0.9),
        total_ms_max: totals.last().copied().unwrap_or(0.0),
        tokens_per_second_mean: mean(&speeds),
        sentences: results,
    };
    let json = serde_json::to_string_pretty(&report)?;
    match flag(args, "--json") {
        Some(path) => std::fs::write(&path, json)?,
        None => println!("{json}"),
    }
    Ok(())
}

/// `cpu`, `gpu` (the first GPU) or `gpu:N`.
fn model_params(choice: &str) -> Result<(LlamaModelParams, Vec<String>)> {
    let devices = llama_cpp_2::list_llama_ggml_backend_devices();
    if choice == "cpu" {
        return Ok((LlamaModelParams::default().with_n_gpu_layers(0), vec!["CPU".into()]));
    }
    let wanted: usize = match choice.strip_prefix("gpu") {
        Some("") => 0,
        Some(rest) => rest.trim_start_matches(':').parse().context("--device gpu:N needs a number")?,
        None => bail!("--device must be cpu, gpu or gpu:N"),
    };
    let gpus: Vec<_> = devices.iter().filter(|device| !device.backend.eq_ignore_ascii_case("cpu")).collect();
    let gpu = gpus.get(wanted).ok_or_else(|| anyhow!("no GPU number {wanted}; this PC has {}", gpus.len()))?;
    let params = LlamaModelParams::default()
        .with_n_gpu_layers(999)
        .with_devices(&[gpu.index])
        .map_err(|error| anyhow!("choosing the GPU: {error}"))?;
    Ok((params, vec![format!("{} ({})", gpu.description, gpu.backend)]))
}

fn translate(model: &LlamaModel, ctx: &mut llama_cpp_2::context::LlamaContext, template: &str, system: &str, source: &str) -> Result<Sentence> {
    let started = Instant::now();
    let prompt = render_no_think(template, system, &format!("Source:\n{source}"))?;
    let vocab = model.vocab();
    let tokens = vocab.tokenize(prompt.as_bytes(), false, true);
    ctx.clear_kv_cache();
    let mut batch = LlamaBatch::new(tokens.len().max(512), 1);
    let last = tokens.len() as i32 - 1;
    for (position, token) in tokens.iter().enumerate() {
        batch.add(*token, position as i32, &[0], position as i32 == last)?;
    }
    ctx.decode(&mut batch).map_err(|error| anyhow!("reading the prompt: {error}"))?;
    let prompt_ms = started.elapsed().as_secs_f64() * 1000.0;

    let mut sampler = LlamaSampler::greedy();
    let mut output = Vec::new();
    let mut position = tokens.len() as i32;
    let generating = Instant::now();
    let mut produced = 0usize;
    while produced < MAX_TOKENS {
        let token = sampler.sample(ctx, batch.n_tokens() - 1);
        sampler.accept(token);
        if vocab.is_eog(token) {
            break;
        }
        output.extend(vocab.token_to_piece(token, false, None));
        produced += 1;
        batch.clear();
        batch.add(token, position, &[0], true)?;
        position += 1;
        ctx.decode(&mut batch).map_err(|error| anyhow!("writing the translation: {error}"))?;
    }
    let generate_seconds = generating.elapsed().as_secs_f64();
    let text = String::from_utf8_lossy(&output).into_owned();
    Ok(Sentence {
        source: source.to_string(),
        translation: strip_thinking(&text),
        prompt_tokens: tokens.len(),
        output_tokens: produced,
        prompt_ms,
        total_ms: started.elapsed().as_secs_f64() * 1000.0,
        tokens_per_second: if generate_seconds > 0.0 { produced as f64 / generate_seconds } else { 0.0 },
        queued_ms: 0.0,
    })
}

#[derive(Serialize)]
struct Message<'a> {
    role: &'a str,
    content: &'a str,
}

/// The model's own template, rendered with thinking off, as on the Mac.
fn render_no_think(template: &str, system: &str, user: &str) -> Result<String> {
    let mut env = Environment::new();
    env.set_unknown_method_callback(minijinja_contrib::pycompat::unknown_method_callback);
    env.add_template_owned("chat".to_string(), template.to_string())?;
    let messages = vec![Message { role: "system", content: system }, Message { role: "user", content: user }];
    Ok(env.get_template("chat")?.render(context! { messages => messages, add_generation_prompt => true, enable_thinking => false })?)
}

fn strip_thinking(text: &str) -> String {
    let mut text = text.to_string();
    while let (Some(start), Some(end)) = (text.find("<think>"), text.find("</think>")) {
        if end < start {
            break;
        }
        text.replace_range(start..end + "</think>".len(), "");
    }
    text.trim().to_string()
}

fn translation_language(code: &str) -> &'static str {
    match code.to_lowercase().as_str() {
        "zh" | "chinese" => "Chinese",
        "ja" => "Japanese",
        "ko" => "Korean",
        "de" => "German",
        "fr" => "French",
        "es" => "Spanish",
        "ru" => "Russian",
        _ => "English",
    }
}

fn mean(values: &[f64]) -> f64 {
    if values.is_empty() { 0.0 } else { values.iter().sum::<f64>() / values.len() as f64 }
}

fn percentile(values: &[f64], fraction: f64) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    values[((values.len() - 1) as f64 * fraction).round() as usize]
}

fn flag(args: &[String], name: &str) -> Option<String> {
    let mut index = 0;
    while index < args.len() {
        if args[index] == name {
            return args.get(index + 1).cloned();
        }
        if let Some(value) = args[index].strip_prefix(&format!("{name}=")) {
            return Some(value.to_string());
        }
        index += 1;
    }
    None
}
