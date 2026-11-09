use anyhow::{anyhow, Result};
use qwen3_asr_mlx::{Qwen3ASR, SamplingConfig};
use std::io::{self, BufReader};
use std::path::PathBuf;
use tracing_subscriber::EnvFilter;
use voice_core::{pcm_from_bytes, read_frame, write_frame, WorkerEvent, WorkerRequest};

const MAX_TOKENS: usize = 1024;

/// Phrases shorter than this (3 s) that reach the token limit hold no real speech worth keeping.
const SHORT_PHRASE_SAMPLES: usize = 3 * 16_000;

/// Text tokens a phrase of this length can need. Fast speech is about 8 tokens a second in Chinese
/// and fewer in English; 12 a second plus room for the language header leaves margin, and a loop
/// on a 15 s phrase now stops at about 200 tokens instead of 1024.
fn token_budget(samples: usize) -> usize {
    let seconds = samples as f64 / 16_000.0;
    (32 + (seconds * 12.0).ceil() as usize).min(MAX_TOKENS)
}

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_writer(io::stderr)
        .with_env_filter(EnvFilter::from_default_env().add_directive(tracing::Level::INFO.into()))
        .init();

    let model_path = argument_value("--model").ok_or_else(|| anyhow!("asr-worker needs --model"))?;
    let mut stdout = io::stdout().lock();
    let mut model = match Qwen3ASR::load(PathBuf::from(&model_path)) {
        Ok(model) => model,
        Err(error) => {
            let message = format!("识别模型加载失败：{error:#}");
            write_frame(&mut stdout, &WorkerEvent::LoadError { message: message.clone() }, &[])?;
            return Err(anyhow!(message));
        }
    };
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
                write_frame(
                    &mut stdout,
                    &WorkerEvent::Failed { id, message: "识别进程不翻译".into() },
                    &[],
                )?;
            }
            WorkerRequest::Transcribe { id, language, context } => {
                let samples = pcm_from_bytes(&payload);
                let config = SamplingConfig { temperature: 0.0, max_tokens: token_budget(samples.len()) };
                let mut result = model.transcribe_samples_with_context(&samples, &language, &context, &config);
                // More text than a short phrase can hold is the model repeating its context
                // ("…fifty-two percent is visible" again from half a second of noise); drop it.
                if model.last_hit_token_limit && samples.len() < SHORT_PHRASE_SAMPLES {
                    if let Ok((text, _)) = &mut result {
                        text.clear();
                    }
                }
                unsafe {
                    mlx_sys::mlx_clear_cache();
                }
                match result {
                    Ok((text, language)) => write_frame(&mut stdout, &WorkerEvent::Transcript { id, text, language }, &[])?,
                    Err(error) => write_frame(
                        &mut stdout,
                        &WorkerEvent::Failed { id, message: error.to_string() },
                        &[],
                    )?,
                }
            }
        }
    }
    Ok(())
}

fn argument_value(name: &str) -> Option<String> {
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        if arg == name {
            return args.next();
        }
        if let Some(value) = arg.strip_prefix(&format!("{name}=")) {
            return Some(value.to_string());
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::token_budget;

    #[test]
    fn the_budget_follows_the_phrase_length() {
        assert_eq!(token_budget(16_000), 44);
        assert_eq!(token_budget(15 * 16_000), 212);
        assert_eq!(token_budget(600 * 16_000), 1024);
    }
}
