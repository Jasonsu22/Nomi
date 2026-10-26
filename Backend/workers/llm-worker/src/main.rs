use anyhow::{anyhow, Result};
use minijinja::{context, Environment};
use minijinja_contrib::pycompat::unknown_method_callback;
use mlx_lm_utils::tokenizer::{
    load_model_chat_template_from_file, ApplyChatTemplateArgs, Conversation, Tokenizer,
};
use mlx_rs::ops::indexing::{IndexOp, NewAxis};
use std::collections::HashSet;
use std::io::{self, BufReader};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Instant;
use tracing_subscriber::EnvFilter;
use voice_core::{read_frame, write_frame, WorkerEvent, WorkerRequest};

const MAX_TOKENS: usize = 256;

/// Set by SIGUSR1, which the engine sends to stop the reply in progress. The token loop checks it
/// after every token and returns the text written so far as a normal result.
static CANCELLED: AtomicBool = AtomicBool::new(false);

extern "C" fn request_cancel(_: libc::c_int) {
    CANCELLED.store(true, Ordering::SeqCst);
}

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_writer(io::stderr)
        .with_env_filter(EnvFilter::from_default_env().add_directive(tracing::Level::INFO.into()))
        .init();

    let model_path = PathBuf::from(argument_value("--model").ok_or_else(|| anyhow!("llm-worker needs --model"))?);
    let mut stdout = io::stdout().lock();
    let mut state = match Worker::load(&model_path) {
        Ok(state) => state,
        Err(error) => {
            let message = format!("翻译模型加载失败：{error:#}");
            write_frame(&mut stdout, &WorkerEvent::LoadError { message: message.clone() }, &[])?;
            return Err(anyhow!(message));
        }
    };
    unsafe {
        libc::signal(libc::SIGUSR1, request_cancel as *const () as libc::sighandler_t);
    }
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
        CANCELLED.store(false, Ordering::SeqCst);
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
                let user = format!("Source:\n{text}");
                match state.generate(&system, &user, MAX_TOKENS) {
                    Ok(text) => write_frame(&mut stdout, &WorkerEvent::Result { id, text }, &[])?,
                    Err(error) => write_frame(&mut stdout, &WorkerEvent::Failed { id, message: error.to_string() }, &[])?,
                }
            }
            WorkerRequest::Generate { id, system, prompt, max_tokens } => {
                let result = state.generate_streaming(&system, &prompt, max_tokens.clamp(1, 4096), &mut |text| {
                    write_frame(&mut stdout, &WorkerEvent::Token { id, text: text.to_string() }, &[])
                });
                match result {
                    Ok(text) => write_frame(&mut stdout, &WorkerEvent::Result { id, text }, &[])?,
                    Err(error) => write_frame(&mut stdout, &WorkerEvent::Failed { id, message: error.to_string() }, &[])?,
                }
            }
        }
    }
    Ok(())
}

struct Worker {
    tokenizer: Tokenizer,
    model: TextModel,
    chat_template: String,
    model_id: String,
    eos_tokens: HashSet<u32>,
}

enum TextModel {
    Qwen3(Box<qwen3_mlx::Model>),
    Qwen35(Box<qwen3_5_35b_mlx::Model>),
}

impl Worker {
    fn load(model_path: &Path) -> Result<Self> {
        let tokenizer = Tokenizer::from_file(model_path.join("tokenizer.json"))
            .map_err(|error| anyhow!("读取分词器失败：{error:?}"))?;
        let chat_template = load_model_chat_template_from_file(&model_path.join("tokenizer_config.json"))?
            .or_else(|| std::fs::read_to_string(model_path.join("chat_template.jinja")).ok())
            .ok_or_else(|| anyhow!("找不到对话模板"))?;
        let config: serde_json::Value = serde_json::from_slice(&std::fs::read(model_path.join("config.json"))?)?;
        let model = match config["model_type"].as_str() {
            Some("qwen3") => TextModel::Qwen3(Box::new(qwen3_mlx::load_model(model_path)?)),
            Some("qwen3_5") => TextModel::Qwen35(Box::new(qwen3_5_35b_mlx::load_model(model_path)?)),
            _ => return Err(anyhow!("当前大模型架构不受支持")),
        };
        let model_id = model_path.file_name().and_then(|name| name.to_str()).unwrap_or("qwen3.5").to_string();
        Ok(Self {
            tokenizer,
            model,
            chat_template,
            model_id,
            eos_tokens: load_eos_tokens(model_path)?,
        })
    }

    fn generate(&mut self, system_prompt: &str, user_text: &str, max_tokens: usize) -> Result<String> {
        self.generate_streaming(system_prompt, user_text, max_tokens, &mut |_| Ok(()))
    }

    fn generate_streaming(
        &mut self,
        system_prompt: &str,
        user_text: &str,
        max_tokens: usize,
        emit: &mut dyn FnMut(&str) -> io::Result<()>,
    ) -> Result<String> {
        let prompt_ids = prompt_tokens(&mut self.tokenizer, &self.chat_template, &self.model_id, system_prompt, user_text)?;
        if prompt_ids.len() > 16_384 {
            return Err(anyhow!("会议内容过长，请选择较短的会议或使用支持更长上下文的 API 模型"));
        }
        let prompt = mlx_rs::Array::from(&prompt_ids[..]).index(NewAxis);
        let result = match &mut self.model {
            TextModel::Qwen3(model) => {
                let mut cache = Vec::new();
                let generator = qwen3_mlx::Generate::<qwen3_mlx::KVCache>::new(model, &mut cache, 0.0, &prompt);
                collect_response(generator, &mut self.tokenizer, &self.eos_tokens, max_tokens, emit)
            }
            TextModel::Qwen35(model) => {
                let generator = qwen3_5_35b_mlx::Generate::new(model, 0.0, &prompt);
                collect_response(generator, &mut self.tokenizer, &self.eos_tokens, max_tokens, emit)
            }
        };
        unsafe { mlx_sys::mlx_clear_cache(); }
        result
    }
}

fn collect_response<E: std::fmt::Display>(
    generator: impl Iterator<Item = std::result::Result<mlx_rs::Array, E>>,
    tokenizer: &mut Tokenizer,
    eos_tokens: &HashSet<u32>,
    max_tokens: usize,
    emit: &mut dyn FnMut(&str) -> io::Result<()>,
) -> Result<String> {
    let mut ids = Vec::new();
    let mut sent = String::new();
    let started = Instant::now();
    for token_result in generator.take(max_tokens) {
        if started.elapsed().as_secs_f32() >= 120.0 || CANCELLED.load(Ordering::SeqCst) { break; }
        let token = token_result.map_err(|error| anyhow!("生成失败：{error}"))?;
        let id = token.item::<u32>();
        if eos_tokens.contains(&id) { break; }
        ids.push(id);
        // Decode the whole sequence so a token boundary cannot split a character, then send the new visible text.
        let decoded = tokenizer.decode(&ids, true).map_err(|error| anyhow!("解码失败：{error:?}"))?;
        let mut visible = visible_answer(&decoded);
        // Greedy decoding can fall into a loop that repeats one block until the token limit.
        // Every few tokens, look for it; keep the text up to the first copy and stop.
        let looped = ids.len() % 16 == 0 && trim_loop(&mut visible);
        if visible != sent {
            emit(&visible).map_err(|error| anyhow!("写出文字失败：{error}"))?;
            sent = visible;
        }
        if looped { return Ok(sent.trim().to_string()); }
    }
    let decoded = tokenizer.decode(&ids, true).map_err(|error| anyhow!("解码失败：{error:?}"))?;
    let mut visible = visible_answer(&decoded);
    trim_loop(&mut visible);
    let visible = visible.trim().to_string();
    if visible.is_empty() { Ok(decoded.trim().to_string()) } else { Ok(visible) }
}

/// True when the text ends in one block repeated at least three times over 240+ characters.
/// Digits are compared as equal, so "step 19, step 20, …" counts as a loop too.
/// The repeats are cut, leaving the first copy.
fn trim_loop(text: &mut String) -> bool {
    let chars: Vec<char> = text.chars().collect();
    let shape: Vec<char> = chars.iter().map(|c| if c.is_ascii_digit() { '0' } else { *c }).collect();
    let n = chars.len();
    for unit in 4..=400.min(n / 3) {
        let mut copies = 1;
        while (copies + 1) * unit <= n && shape[n - (copies + 1) * unit..n - copies * unit] == shape[n - unit..] {
            copies += 1;
        }
        if copies >= 3 && copies * unit >= 240 {
            *text = chars[..n - (copies - 1) * unit].iter().collect();
            return true;
        }
    }
    false
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

fn prompt_tokens(tokenizer: &mut Tokenizer, chat_template: &str, model_id: &str, system_prompt: &str, user_text: &str) -> Result<Vec<u32>> {
    if chat_template.contains("enable_thinking") {
        if let Ok(rendered) = render_no_think(chat_template, system_prompt, user_text) {
            let encoding = tokenizer.encode(rendered.as_str(), false).map_err(|error| anyhow!("{error:?}"))?;
            return Ok(encoding.get_ids().to_vec());
        }
    }
    let conversations = vec![
        Conversation { role: "system", content: system_prompt },
        Conversation { role: "user", content: user_text },
    ];
    let args = ApplyChatTemplateArgs {
        conversations: vec![conversations.into()],
        documents: None,
        model_id,
        chat_template_id: None,
        add_generation_prompt: Some(true),
        continue_final_message: None,
    };
    let encodings = tokenizer
        .apply_chat_template_and_encode(chat_template.to_string(), args)
        .map_err(|error| anyhow!("分词失败：{error:?}"))?;
    Ok(encodings.iter().flat_map(|encoding| encoding.get_ids().iter().copied()).collect())
}

fn render_no_think(chat_template: &str, system_prompt: &str, user_text: &str) -> Result<String> {
    let mut env = Environment::new();
    env.set_unknown_method_callback(unknown_method_callback);
    env.add_template_owned("chat".to_string(), chat_template.to_string())
        .map_err(|error| anyhow!("{error}"))?;
    let template = env.get_template("chat").map_err(|error| anyhow!("{error}"))?;
    let messages = vec![
        Conversation { role: "system", content: system_prompt },
        Conversation { role: "user", content: user_text },
    ];
    template
        .render(context! { messages => messages, add_generation_prompt => true, enable_thinking => false })
        .map_err(|error| anyhow!("{error}"))
}

fn load_eos_tokens(model_path: &Path) -> Result<HashSet<u32>> {
    let config: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(model_path.join("config.json"))?)?;
    let value = config.get("eos_token_id").or_else(|| config.get("text_config").and_then(|item| item.get("eos_token_id")));
    let mut tokens = HashSet::new();
    match value {
        Some(serde_json::Value::Array(ids)) => {
            tokens.extend(ids.iter().filter_map(|id| id.as_u64().map(|id| id as u32)));
        }
        Some(serde_json::Value::Number(id)) => {
            tokens.insert(id.as_u64().unwrap_or(248044) as u32);
        }
        _ => {
            tokens.insert(248044);
        }
    }
    Ok(tokens)
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
mod loop_tests {
    use super::trim_loop;

    #[test]
    fn cuts_a_repeating_block() {
        let block = "       +----+\n       |    |\n       |    v\n";
        let mut text = format!("结构图\n{}", block.repeat(12));
        assert!(trim_loop(&mut text));
        assert_eq!(text, format!("结构图\n{block}"));
    }

    #[test]
    fn cuts_a_counting_loop() {
        let mut text = String::from("迭代过程：\n");
        for step in 10..30 {
            text += &format!("- **第 {step} 步**：\n  - 梯度：$(0, 0)$\n  - 结果：$(0, 0)$\n");
        }
        assert!(trim_loop(&mut text));
        assert!(text.ends_with("- **第 10 步**：\n  - 梯度：$(0, 0)$\n  - 结果：$(0, 0)$\n"));
    }

    #[test]
    fn leaves_normal_text_alone() {
        let mut text = "梯度下降沿负梯度方向更新参数。\n\n1. 计算梯度\n2. 更新参数\n3. 重复直到收敛\n".to_string();
        assert!(!trim_loop(&mut text));
        let mut table = "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n".to_string();
        assert!(!trim_loop(&mut table));
    }
}
