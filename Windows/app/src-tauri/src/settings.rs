//! The user's choices, in settings.json next to the meetings.

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Settings {
    /// Set once the first-start guide is finished.
    pub set_up: bool,
    pub asr_model: String,
    pub llm_model: String,
    /// auto, cpu, gpu or gpu:N, per model.
    pub asr_device: String,
    pub llm_device: String,
    /// 0 = let the library choose.
    pub threads: u32,
    /// all, skip-busy or off.
    pub interim: String,
    pub source_language: String,
    pub target_language: String,
    /// The microphone by name; empty = the system default.
    pub input_device: String,
    pub live_speakers: bool,
    /// standard or zh-en.
    pub speaker_model: String,
    /// Your voiceprint, after "This is me".
    pub my_voice: Option<Vec<f32>>,
    /// zh or en; empty = follow the system.
    pub ui_language: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            set_up: false,
            asr_model: "qwen3-asr-0.6b".into(),
            llm_model: "qwen3.5-2b".into(),
            asr_device: "auto".into(),
            llm_device: "cpu".into(),
            threads: 0,
            interim: "skip-busy".into(),
            source_language: "auto".into(),
            target_language: "en".into(),
            input_device: String::new(),
            live_speakers: true,
            speaker_model: "standard".into(),
            my_voice: None,
            ui_language: String::new(),
        }
    }
}

pub fn load() -> Settings {
    std::fs::read(crate::paths::settings_file())
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

pub fn save(settings: &Settings) -> anyhow::Result<()> {
    let file = crate::paths::settings_file();
    if let Some(parent) = file.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(file, serde_json::to_vec_pretty(settings)?)?;
    Ok(())
}
