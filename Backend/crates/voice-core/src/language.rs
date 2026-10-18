pub fn asr_language(code: &str) -> String {
    match code.trim().to_lowercase().as_str() {
        "auto" => "auto".to_string(),
        "zh" | "zh-cn" | "zh-hans" | "cn" | "chinese" => "Chinese".to_string(),
        "en" | "en-us" | "en-gb" | "english" => "English".to_string(),
        "ja" | "jp" | "japanese" => "Japanese".to_string(),
        "ko" | "korean" => "Korean".to_string(),
        "de" | "german" => "German".to_string(),
        "fr" | "french" => "French".to_string(),
        "es" | "spanish" => "Spanish".to_string(),
        "ru" | "russian" => "Russian".to_string(),
        "ar" | "arabic" => "Arabic".to_string(),
        other => {
            let mut name = other.to_string();
            if let Some(first) = name.get_mut(..1) {
                first.make_ascii_uppercase();
            }
            name
        }
    }
}

pub fn translation_language(code: &str) -> &'static str {
    match asr_language(code).as_str() {
        "Chinese" => "Chinese",
        "English" => "English",
        "Japanese" => "Japanese",
        "Korean" => "Korean",
        "German" => "German",
        "French" => "French",
        "Spanish" => "Spanish",
        "Russian" => "Russian",
        "Arabic" => "Arabic",
        _ => "English",
    }
}

pub fn uses_spaces(code: &str) -> bool {
    let code = code.trim().to_lowercase();
    !(code == "none" || code.starts_with("zh") || code.starts_with("ja") || code == "chinese" || code == "japanese")
}

pub fn is_low_information(chunk: &str, source_language: &str) -> bool {
    let trimmed = chunk.trim().trim_matches(|c: char| {
        c.is_ascii_punctuation() || c.is_whitespace() || "，。！？；：、“”‘’（）()…".contains(c)
    });
    if trimmed.is_empty() {
        return true;
    }
    if asr_language(source_language) == "Chinese" {
        const FILLERS: &[&str] = &["嗯", "啊", "呃", "额", "唔", "哦", "噢", "哎", "哈", "嗯嗯", "啊啊", "呃呃"];
        if FILLERS.contains(&trimmed) {
            return true;
        }
    }
    false
}
