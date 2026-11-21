//! Meetings, saved as `meetings.json` in the Mac app's schema (Meeting, Paragraph, Commit, voices),
//! so a folder of meetings reads on both systems. Dates are seconds since 2001-01-01, as Swift's
//! JSONEncoder writes them.

use crate::transcript::Paragraph;
use crate::voices::MeetingVoices;
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

/// Seconds from 1970 to 2001-01-01, Apple's reference date.
const REFERENCE_OFFSET: f64 = 978_307_200.0;

pub fn now_reference() -> f64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs_f64()).unwrap_or(0.0) - REFERENCE_OFFSET
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Meeting {
    /// Upper-case UUID, as Swift writes it.
    pub id: String,
    pub title: String,
    pub started_at: f64,
    pub duration: f64,
    /// "microphone" or "system".
    pub source: String,
    pub source_language: String,
    pub target_language: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub category_id: Option<String>,
    pub paragraphs: Vec<Paragraph>,
    pub is_live: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_device_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub audio_files: Option<Vec<String>>,
    /// The Mac's summary and questions; kept as they are so nothing is lost on a round trip.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub assistant: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub voices: Option<MeetingVoices>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hidden_speakers: Option<Vec<String>>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Snapshot {
    pub meetings: Vec<Meeting>,
    #[serde(default)]
    pub categories: Vec<serde_json::Value>,
}

pub fn load() -> Snapshot {
    std::fs::read(crate::paths::meetings_file())
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default()
}

/// Writes to a temporary file first, so a crash mid-write never leaves a broken meetings.json.
pub fn save(snapshot: &Snapshot) -> Result<()> {
    let file = crate::paths::meetings_file();
    if let Some(parent) = file.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let temporary = file.with_extension("json.tmp");
    std::fs::write(&temporary, serde_json::to_vec(snapshot)?)?;
    std::fs::rename(temporary, file)?;
    Ok(())
}

pub fn new_id() -> String {
    uuid::Uuid::new_v4().to_string().to_uppercase()
}

/// The meeting's lines without the hidden speakers', as the Mac's `shownParagraphs` does.
pub fn shown_paragraphs(meeting: &Meeting) -> Vec<Paragraph> {
    let hidden = meeting.hidden_speakers.clone().unwrap_or_default();
    if hidden.is_empty() {
        return meeting.paragraphs.clone();
    }
    meeting
        .paragraphs
        .iter()
        .filter_map(|paragraph| {
            let mut kept = paragraph.clone();
            kept.commits.retain(|c| !c.speaker.as_ref().is_some_and(|s| hidden.contains(s)));
            (!(kept.commits.is_empty() && kept.tail.is_empty())).then_some(kept)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_mac_meeting_reads_and_writes_back() {
        let json = r#"{"id":"6F1C2D2E-1111-4222-8333-944455556666","title":"NLP","startedAt":785000000.5,"duration":3600,
            "source":"microphone","sourceLanguage":"auto","targetLanguage":"en","paragraphs":[{"id":1,"openedAt":0,"commits":[
            {"id":1,"source":"你好","translation":"Hello","start":0,"end":1,"speaker":"S1"}],"tail":"","closed":true}],
            "isLive":false,"audioFiles":["audio-1.aac"],"assistant":{"summary":"x","answers":[]}}"#;
        let meeting: Meeting = serde_json::from_str(json).unwrap();
        assert_eq!(meeting.paragraphs[0].commits[0].speaker.as_deref(), Some("S1"));
        let back = serde_json::to_value(&meeting).unwrap();
        assert_eq!(back["assistant"]["summary"], "x");
        assert_eq!(back["startedAt"], 785000000.5);
    }
}
