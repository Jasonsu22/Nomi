use anyhow::{anyhow, Result};
use qwen3_asr_mlx::{Qwen3ASR, SamplingConfig};
use std::io::{self, BufReader};
use std::path::PathBuf;
use tracing_subscriber::EnvFilter;
use voice_core::{pcm_from_bytes, read_frame, write_frame, WorkerEvent, WorkerRequest};

const MAX_TOKENS: usize = 1024;

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
            WorkerRequest::Transcribe { id, language } => {
                let samples = pcm_from_bytes(&payload);
                let config = SamplingConfig { temperature: 0.0, max_tokens: MAX_TOKENS };
                let result = model.transcribe_samples_with_config(&samples, &language, &config);
                unsafe {
                    mlx_sys::mlx_clear_cache();
                }
                match result {
                    Ok(text) => write_frame(&mut stdout, &WorkerEvent::Result { id, text }, &[])?,
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
