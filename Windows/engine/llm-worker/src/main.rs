//! Translation and answer worker for Nomi on Windows. Same frames as the Mac's MLX `llm-worker`;
//! the model is a Qwen3.5 GGUF file run by llama.cpp on the CPU or a GPU (Vulkan).
//!
//! llm-worker --model FILE.gguf        serve frames on stdin/stdout (started by moxin-engine)
//! llm-worker devices                  print the devices llama.cpp sees, as JSON
//!
//! NOMI_LLM_DEVICE = auto (default) | cpu | gpu | gpu:N, NOMI_LLM_THREADS = N, NOMI_LLM_CONTEXT = tokens.
//! Stop: the engine creates `%TEMP%\nomi-cancel-<pid>`; the token loop checks for it after each token.

use anyhow::{anyhow, bail, Context, Result};
use llama_cpp_2::context::params::LlamaContextParams;
use llama_cpp_2::context::LlamaContext;
use llama_cpp_2::llama_backend::LlamaBackend;
use llama_cpp_2::llama_batch::LlamaBatch;
use llama_cpp_2::model::params::LlamaModelParams;
use llama_cpp_2::model::LlamaModel;
use llama_cpp_2::sampling::LlamaSampler;
use minijinja::{context, Environment};
use serde::Serialize;
use std::io::{self, BufReader, Write};
use std::num::NonZeroU32;
use std::path::PathBuf;
use std::time::Instant;
use voice_core::{read_frame, write_frame, WorkerEvent, WorkerRequest};

const TRANSLATION_TOKENS: usize = 256;

fn main() -> Result<()> {
    load_backends();
    let args: Vec<String> = std::env::args().skip(1).collect();
    // The backend and model live as long as the process, so a context can borrow them freely.
    let backend: &'static LlamaBackend = Box::leak(Box::new(LlamaBackend::init()?));
    if args.first().map(String::as_str) == Some("devices") {
        println!("{}", serde_json::to_string_pretty(&device_list())?);
        return Ok(());
    }
    let model_path = flag(&args, "--model").ok_or_else(|| anyhow!("llm-worker needs --model"))?;
    let mut stdout = io::stdout().lock();
    let mut worker = match Worker::load(backend, &model_path) {
        Ok(worker) => worker,
        Err(error) => {
            let message = format!("翻译模型加载失败：{error:#}");
            write_frame(&mut stdout, &WorkerEvent::LoadError { message: message.clone() }, &[])?;
            return Err(anyhow!(message));
        }
    };
    write_frame(&mut stdout, &WorkerEvent::Ready, &[])?;

    let mut stdin = BufReader::new(io::stdin());
    loop {
        let (header, _) = match read_frame(&mut stdin) {
            Ok(frame) => frame,
            Err(error) if error.kind() == io::ErrorKind::UnexpectedEof => break,
            Err(error) => return Err(error.into()),
        };
        let request: WorkerRequest = serde_json::from_slice(&header)?;
        // A cancel meant for an earlier reply must not stop this one.
        let _ = std::fs::remove_file(cancel_file());
        match request {
            WorkerRequest::Shutdown => break,
            WorkerRequest::Transcribe { id, .. } => {
                write_frame(&mut stdout, &WorkerEvent::Failed { id, message: "翻译进程不识别".into() }, &[])?;
            }
            WorkerRequest::Translate { id, text, target_language } => {
                let target = voice_core::translation_language(&target_language);
                let system = format!(
                    "/no_think You are a translation engine. Translate the source text into {target}. Output only the translated text. Do not include source/translation labels, do not explain, do not repeat the source."
                );
                let event = match worker.generate(&system, &format!("Source:\n{text}"), TRANSLATION_TOKENS, &mut |_| Ok(())) {
                    Ok(text) => WorkerEvent::Result { id, text },
                    Err(error) => WorkerEvent::Failed { id, message: error.to_string() },
                };
                write_frame(&mut stdout, &event, &[])?;
            }
            WorkerRequest::Generate { id, system, prompt, max_tokens } => {
                let result = worker.generate(&system, &prompt, max_tokens.clamp(1, 4096), &mut |text| {
                    write_frame(&mut stdout, &WorkerEvent::Token { id, text: text.to_string() }, &[])
                });
                let event = match result {
                    Ok(text) => WorkerEvent::Result { id, text },
                    Err(error) => WorkerEvent::Failed { id, message: error.to_string() },
                };
                write_frame(&mut stdout, &event, &[])?;
            }
        }
        stdout.flush()?;
    }
    Ok(())
}

/// With dynamic backends (Windows), the CPU and Vulkan libraries sit next to the program.
#[cfg(not(target_os = "macos"))]
fn load_backends() {
    if let Some(folder) = std::env::current_exe().ok().and_then(|exe| exe.parent().map(std::path::Path::to_path_buf)) {
        llama_cpp_2::llama_backend::load_backends_from_path(&folder);
    }
}

#[cfg(target_os = "macos")]
fn load_backends() {}

fn cancel_file() -> PathBuf {
    std::env::temp_dir().join(format!("nomi-cancel-{}", std::process::id()))
}

fn cancelled() -> bool {
    cancel_file().exists()
}

struct Worker {
    backend: &'static LlamaBackend,
    model: &'static LlamaModel,
    context: Option<LlamaContext<'static>>,
    template: String,
    on_cpu: bool,
    threads: i32,
    context_tokens: u32,
}

impl Worker {
    fn load(backend: &'static LlamaBackend, path: &str) -> Result<Self> {
        let choice = std::env::var("NOMI_LLM_DEVICE").unwrap_or_else(|_| "auto".into());
        let threads: i32 = std::env::var("NOMI_LLM_THREADS").ok().and_then(|value| value.parse().ok()).unwrap_or(0);
        let context_tokens: u32 = std::env::var("NOMI_LLM_CONTEXT").ok().and_then(|value| value.parse().ok()).unwrap_or(4096);
        let (model, placed) = if choice == "auto" {
            let gpu = model_params("gpu").ok().and_then(|(params, placed)| match LlamaModel::load_from_file(backend, path, &params) {
                Ok(model) => Some((model, placed)),
                Err(error) => {
                    eprintln!("llm-worker: GPU load failed, using the CPU: {error}");
                    None
                }
            });
            match gpu {
                Some(loaded) => loaded,
                None => {
                    let (params, placed) = model_params("cpu")?;
                    (LlamaModel::load_from_file(backend, path, &params).map_err(|error| anyhow!("{error}"))?, placed)
                }
            }
        } else {
            let (params, placed) = model_params(&choice)?;
            (LlamaModel::load_from_file(backend, path, &params).map_err(|error| anyhow!("{error}"))?, placed)
        };
        let template = model
            .chat_template(None)
            .map_err(|error| anyhow!("the model has no chat template: {error}"))?
            .to_string()?;
        eprintln!("llm-worker: {path} on {placed}, threads {threads}");
        let on_cpu = placed == "CPU";
        let model: &'static LlamaModel = Box::leak(Box::new(model));
        let mut worker = Self { backend, model, context: None, template, on_cpu, threads, context_tokens };
        worker.ensure_context(512)?;
        Ok(worker)
    }

    /// One context reused across requests; it grows when a longer prompt arrives.
    fn ensure_context(&mut self, needed: usize) -> Result<()> {
        let size = self.context.as_ref().map_or(0, |context| context.n_ctx() as usize);
        if size >= needed && size > 0 {
            return Ok(());
        }
        let tokens = (needed.max(self.context_tokens as usize)).next_power_of_two().min(32_768) as u32;
        let mut params = LlamaContextParams::default().with_n_ctx(NonZeroU32::new(tokens)).with_n_batch(512);
        if self.threads > 0 {
            params = params.with_n_threads(self.threads).with_n_threads_batch(self.threads);
        }
        if self.on_cpu {
            params = params.with_op_offload(false).with_offload_kqv(false);
        }
        self.context = None;
        self.context = Some(self.model.new_context(self.backend, params).map_err(|error| anyhow!("creating a context: {error}"))?);
        Ok(())
    }

    fn generate(&mut self, system: &str, user: &str, max_tokens: usize, emit: &mut dyn FnMut(&str) -> io::Result<()>) -> Result<String> {
        let prompt = render_no_think(&self.template, system, user)?;
        let tokens = self.model.vocab().tokenize(prompt.as_bytes(), false, true);
        if tokens.len() > 16_384 {
            bail!("会议内容过长，请选择较短的会议或使用支持更长上下文的 API 模型");
        }
        self.ensure_context(tokens.len() + max_tokens + 8)?;
        let model = self.model;
        let ctx = self.context.as_mut().ok_or_else(|| anyhow!("no context"))?;
        ctx.clear_kv_cache();
        let mut batch = LlamaBatch::new(512, 1);
        // The prompt goes in 512-token pieces, the batch size of the context.
        let last = tokens.len() - 1;
        for (start, piece) in tokens.chunks(512).enumerate() {
            batch.clear();
            for (offset, token) in piece.iter().enumerate() {
                let position = start * 512 + offset;
                batch.add(*token, position as i32, &[0], position == last)?;
            }
            ctx.decode(&mut batch).map_err(|error| anyhow!("reading the prompt: {error}"))?;
        }
        let mut sampler = LlamaSampler::greedy();
        let mut output: Vec<u8> = Vec::new();
        let mut position = tokens.len() as i32;
        let mut sent = String::new();
        let started = Instant::now();
        for _ in 0..max_tokens {
            if started.elapsed().as_secs_f32() >= 120.0 || cancelled() {
                break;
            }
            let token = sampler.sample(ctx, batch.n_tokens() - 1);
            sampler.accept(token);
            if model.vocab().is_eog(token) {
                break;
            }
            output.extend(model.vocab().token_to_piece(token, false, None));
            let visible = visible_answer(&complete_utf8(&output));
            if visible != sent {
                emit(&visible).map_err(|error| anyhow!("writing text: {error}"))?;
                sent = visible;
            }
            batch.clear();
            batch.add(token, position, &[0], true)?;
            position += 1;
            ctx.decode(&mut batch).map_err(|error| anyhow!("writing: {error}"))?;
        }
        let text = visible_answer(&String::from_utf8_lossy(&output));
        Ok(text.trim().to_string())
    }
}

/// The text decoded so far, without a character cut in half at the end.
fn complete_utf8(bytes: &[u8]) -> String {
    match std::str::from_utf8(bytes) {
        Ok(text) => text.to_string(),
        Err(error) => String::from_utf8_lossy(&bytes[..error.valid_up_to()]).into_owned(),
    }
}

fn visible_answer(text: &str) -> String {
    if let Some((_, answer)) = text.rsplit_once("</think>") {
        return answer.trim_start().to_string();
    }
    let trimmed = text.trim_start();
    if trimmed.starts_with("<think") || matches!(trimmed, "<" | "<t" | "<th" | "<thi" | "<thin") {
        return String::new();
    }
    text.to_string()
}

fn model_params(choice: &str) -> Result<(LlamaModelParams, String)> {
    if choice == "cpu" {
        return Ok((LlamaModelParams::default().with_n_gpu_layers(0), "CPU".into()));
    }
    let wanted: usize = match choice.strip_prefix("gpu") {
        Some("") => 0,
        Some(rest) => rest.trim_start_matches(':').parse().context("gpu:N needs a number")?,
        None => bail!("the device must be auto, cpu, gpu or gpu:N"),
    };
    let devices = llama_cpp_2::list_llama_ggml_backend_devices();
    let gpus: Vec<_> = devices.iter().filter(|device| !device.backend.eq_ignore_ascii_case("cpu") && !device.backend.eq_ignore_ascii_case("blas")).collect();
    let gpu = gpus.get(wanted).ok_or_else(|| anyhow!("no GPU number {wanted}"))?;
    let params = LlamaModelParams::default()
        .with_n_gpu_layers(999)
        .with_devices(&[gpu.index])
        .map_err(|error| anyhow!("choosing the GPU: {error}"))?;
    Ok((params, format!("{} ({})", gpu.description, gpu.backend)))
}

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
struct Message<'a> {
    role: &'a str,
    content: &'a str,
}

/// The GGUF file's own chat template, with thinking off, as the Mac worker renders it.
fn render_no_think(template: &str, system: &str, user: &str) -> Result<String> {
    let mut env = Environment::new();
    env.set_unknown_method_callback(minijinja_contrib::pycompat::unknown_method_callback);
    env.add_template_owned("chat".to_string(), template.to_string())?;
    let messages = vec![Message { role: "system", content: system }, Message { role: "user", content: user }];
    Ok(env.get_template("chat")?.render(context! { messages => messages, add_generation_prompt => true, enable_thinking => false })?)
}

fn flag(args: &[String], name: &str) -> Option<String> {
    args.iter().position(|arg| arg == name).and_then(|index| args.get(index + 1)).cloned().or_else(|| {
        args.iter().find_map(|arg| arg.strip_prefix(&format!("{name}=")).map(str::to_string))
    })
}

#[cfg(test)]
mod tests {
    use super::{complete_utf8, visible_answer};

    #[test]
    fn a_split_character_waits_for_its_last_byte() {
        let bytes = "你好".as_bytes();
        assert_eq!(complete_utf8(&bytes[..4]), "你");
        assert_eq!(complete_utf8(bytes), "你好");
    }

    #[test]
    fn thinking_is_hidden() {
        assert_eq!(visible_answer("<think>\n\n</think>\n\n好的"), "好的");
        assert_eq!(visible_answer("<thi"), "");
    }
}
