//! Who speaks in a recording. Ported from the Mac's `Models/MeetingVoices.swift` (0.10) with the
//! same thresholds and JSON, so a meeting's speakers read the same on both systems.
//!
//! The voice heard most is Speaker 1 (often the teacher). Lines get a voice only when that voice says
//! at least 70% of their speech. "This is me" saves your voiceprint and finds it in other lectures.

use crate::transcript::{Commit, Paragraph};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap, HashSet};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MeetingVoices {
    /// The teacher's voice: the one heard most, unless the student chose another.
    pub teacher: String,
    /// How long each voice speaks, in seconds.
    pub seconds: BTreeMap<String, f64>,
    /// Seconds since 2001-01-01, as the Mac's JSON stores dates.
    pub checked_at: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prints: Option<BTreeMap<String, Vec<f32>>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub me: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub me_chosen: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub names: Option<BTreeMap<String, String>>,
}

/// How the app should name a voice; the words themselves come from the UI's language.
#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum VoiceName {
    Named { name: String },
    Me,
    Several,
    Number { number: usize },
}

impl MeetingVoices {
    fn blends(&self) -> HashSet<String> {
        my_voice::blends(&self.prints.clone().unwrap_or_default())
    }

    /// The voices other than the teacher, most heard first.
    pub fn others(&self) -> Vec<String> {
        let blends = self.blends();
        let mut others: Vec<String> =
            self.seconds.keys().filter(|key| **key != self.teacher && !blends.contains(*key)).cloned().collect();
        others.sort_by(|a, b| {
            let (x, y) = (self.seconds[a], self.seconds[b]);
            if x == y { a.cmp(b) } else { y.total_cmp(&x) }
        });
        others
    }

    pub fn number(&self, speaker: &str) -> usize {
        if speaker == self.teacher {
            return 1;
        }
        let others = self.others();
        others.iter().position(|other| other == speaker).unwrap_or(others.len()) + 2
    }

    pub fn name(&self, speaker: &str) -> VoiceName {
        if let Some(given) = self.names.as_ref().and_then(|names| names.get(speaker)).map(|name| name.trim()) {
            if !given.is_empty() {
                return VoiceName::Named { name: given.to_string() };
            }
        }
        if self.me.as_deref() == Some(speaker) {
            return VoiceName::Me;
        }
        if self.blends().contains(speaker) {
            return VoiceName::Several;
        }
        VoiceName::Number { number: self.number(speaker) }
    }

    /// Every voice with its name, for the transcript and the speaker filter.
    pub fn all_names(&self) -> BTreeMap<String, VoiceName> {
        self.seconds.keys().map(|speaker| (speaker.clone(), self.name(speaker))).collect()
    }

    pub fn most_heard(seconds: &HashMap<String, f64>) -> Option<String> {
        seconds
            .iter()
            .max_by(|a, b| if a.1 == b.1 { b.0.cmp(a.0) } else { a.1.total_cmp(b.1) })
            .map(|(key, _)| key.clone())
    }
}

/// One stretch of speech by one voice, in seconds on the meeting's clock.
#[derive(Clone, Debug, PartialEq)]
pub struct VoiceSpan {
    pub start: f64,
    pub end: f64,
    pub speaker: String,
}

pub mod labels {
    use super::*;

    /// A line gets a voice only when that voice says at least this share of its speech.
    pub const SHARE: f64 = 0.7;
    /// Less speech than this is too little to tell voices apart.
    pub const MINIMUM_SPEECH: f64 = 0.4;

    pub fn speaker_of(commit: &Commit, spans: &[VoiceSpan]) -> Option<String> {
        let mut heard: HashMap<String, f64> = HashMap::new();
        for span in spans.iter().filter(|span| span.end > commit.start && span.start < commit.end) {
            *heard.entry(span.speaker.clone()).or_default() += span.end.min(commit.end) - span.start.max(commit.start);
        }
        let total: f64 = heard.values().sum();
        let top = MeetingVoices::most_heard(&heard)?;
        (total >= MINIMUM_SPEECH && heard[&top] / total >= SHARE).then_some(top)
    }

    /// Labels the lines these spans cover; lines outside them keep their labels (earlier runs).
    pub fn apply(spans: &[VoiceSpan], paragraphs: &mut [Paragraph]) {
        let (Some(first), Some(last)) = (
            spans.iter().map(|s| s.start).min_by(f64::total_cmp),
            spans.iter().map(|s| s.end).max_by(f64::total_cmp),
        ) else {
            return;
        };
        for paragraph in paragraphs.iter_mut() {
            for commit in paragraph.commits.iter_mut().filter(|c| c.end > first && c.start < last) {
                commit.speaker = speaker_of(commit, spans);
            }
        }
    }

    /// The voices after a live run, merged with earlier runs': this run's most heard voice is taken
    /// to be the same teacher as before. Returns the spans renamed to match.
    pub fn merging(
        prior: Option<MeetingVoices>,
        spans: Vec<VoiceSpan>,
        prints: BTreeMap<String, Vec<f32>>,
        now: f64,
    ) -> Option<(MeetingVoices, Vec<VoiceSpan>)> {
        let mut seconds: HashMap<String, f64> = HashMap::new();
        for span in &spans {
            *seconds.entry(span.speaker.clone()).or_default() += (span.end - span.start).max(0.0);
        }
        let Some(top) = MeetingVoices::most_heard(&seconds) else { return prior.map(|voices| (voices, spans)) };
        let Some(mut voices) = prior else {
            let fresh = MeetingVoices {
                teacher: top,
                seconds: seconds.into_iter().collect(),
                checked_at: now,
                prints: (!prints.is_empty()).then_some(prints),
                me: None,
                me_chosen: None,
                names: None,
            };
            return Some((fresh, spans));
        };
        let renamed = spans
            .into_iter()
            .map(|span| if span.speaker == top { VoiceSpan { speaker: voices.teacher.clone(), ..span } } else { span })
            .collect();
        for (speaker, time) in seconds {
            let key = if speaker == top { voices.teacher.clone() } else { speaker };
            *voices.seconds.entry(key).or_default() += time;
        }
        let mut all = voices.prints.take().unwrap_or_default();
        for (speaker, print) in prints {
            if speaker != top {
                all.insert(speaker, print);
            }
        }
        voices.prints = (!all.is_empty()).then_some(all);
        voices.checked_at = now;
        Some((voices, renamed))
    }
}

pub mod my_voice {
    use super::*;

    /// A voice matches yours at this cosine similarity or more, and clearly ahead of the next one.
    pub const THRESHOLD: f32 = 0.65;
    pub const LEAD: f32 = 0.1;
    /// A group this close to two or more other voices is a blend of people, not one person.
    pub const BLEND_BAR: f32 = 0.6;

    pub fn cosine(a: &[f32], b: &[f32]) -> f32 {
        if a.len() != b.len() || a.is_empty() {
            return 0.0;
        }
        let (mut dot, mut na, mut nb) = (0f32, 0f32, 0f32);
        for i in 0..a.len() {
            dot += a[i] * b[i];
            na += a[i] * a[i];
            nb += b[i] * b[i];
        }
        if na > 0.0 && nb > 0.0 { dot / (na.sqrt() * nb.sqrt()) } else { 0.0 }
    }

    fn unit(v: &[f32]) -> Vec<f32> {
        let n = v.iter().map(|x| x * x).sum::<f32>().sqrt();
        if n > 0.0 { v.iter().map(|x| x / n).collect() } else { v.to_vec() }
    }

    /// Your saved voice blended with a new sample of it, so it holds up across rooms and days.
    pub fn blended(old: Option<&[f32]>, new: &[f32]) -> Vec<f32> {
        match old {
            Some(old) if old.len() == new.len() => {
                let (a, b) = (unit(old), unit(new));
                unit(&a.iter().zip(&b).map(|(x, y)| 0.7 * x + 0.3 * y).collect::<Vec<_>>())
            }
            _ => unit(new),
        }
    }

    pub fn blends(prints: &BTreeMap<String, Vec<f32>>) -> HashSet<String> {
        prints
            .iter()
            .filter(|(key, print)| prints.iter().filter(|(other, value)| other != key && cosine(value, print) >= BLEND_BAR).count() >= 2)
            .map(|(key, _)| key.clone())
            .collect()
    }

    /// Which voice in a recording is yours, if one clearly is. Never the teacher, never a blend.
    pub fn find(mine: &[f32], prints: &BTreeMap<String, Vec<f32>>, teacher: &str) -> Option<String> {
        let blends = blends(prints);
        let mut scored: Vec<(String, f32)> = prints
            .iter()
            .filter(|(key, _)| key.as_str() != teacher && !blends.contains(*key))
            .map(|(key, print)| (key.clone(), cosine(mine, print)))
            .collect();
        scored.sort_by(|a, b| b.1.total_cmp(&a.1));
        let best = scored.first()?;
        if best.1 < THRESHOLD || (scored.len() > 1 && best.1 - scored[1].1 < LEAD) {
            return None;
        }
        Some(best.0.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn span(start: f64, end: f64, speaker: &str) -> VoiceSpan {
        VoiceSpan { start, end, speaker: speaker.into() }
    }

    fn commit(start: f64, end: f64) -> Commit {
        Commit { id: 1, source: "x".into(), translation: String::new(), start, end, speaker: None }
    }

    fn voices(seconds: &[(&str, f64)]) -> MeetingVoices {
        MeetingVoices {
            teacher: "S1".into(),
            seconds: seconds.iter().map(|(k, v)| (k.to_string(), *v)).collect(),
            checked_at: 0.0,
            prints: None,
            me: None,
            me_chosen: None,
            names: None,
        }
    }

    #[test]
    fn a_line_takes_the_voice_that_says_most_of_it() {
        assert_eq!(labels::speaker_of(&commit(0.0, 10.0), &[span(0.0, 8.0, "S1"), span(8.0, 10.0, "S2")]).as_deref(), Some("S1"));
        // 60/40 is too mixed to call.
        assert_eq!(labels::speaker_of(&commit(0.0, 10.0), &[span(0.0, 6.0, "S1"), span(6.0, 10.0, "S2")]), None);
        // Too little speech.
        assert_eq!(labels::speaker_of(&commit(0.0, 10.0), &[span(0.0, 0.3, "S2")]), None);
    }

    #[test]
    fn speakers_are_numbered_by_time_heard() {
        let mut v = voices(&[("S1", 100.0), ("S2", 5.0), ("S3", 20.0)]);
        assert_eq!(v.number("S1"), 1);
        assert_eq!(v.number("S3"), 2);
        assert_eq!(v.number("S2"), 3);
        v.names = Some([("S2".to_string(), "Jenny".to_string())].into_iter().collect());
        assert_eq!(v.name("S2"), VoiceName::Named { name: "Jenny".into() });
        v.me = Some("S3".into());
        assert_eq!(v.name("S3"), VoiceName::Me);
    }

    #[test]
    fn a_later_run_keeps_the_same_teacher() {
        let prior = voices(&[("S1", 100.0), ("S2", 5.0)]);
        let (merged, spans) =
            labels::merging(Some(prior), vec![span(0.0, 30.0, "R2-S1"), span(30.0, 32.0, "R2-S2")], BTreeMap::new(), 1.0).unwrap();
        assert_eq!(merged.teacher, "S1");
        assert_eq!(merged.seconds["S1"], 130.0);
        assert_eq!(spans[0].speaker, "S1");
        assert_eq!(spans[1].speaker, "R2-S2");
    }

    #[test]
    fn your_voice_is_found_only_when_clearly_ahead() {
        let prints: BTreeMap<String, Vec<f32>> =
            [("S1".into(), vec![1.0, 0.0, 0.0]), ("S2".into(), vec![0.0, 1.0, 0.0]), ("S3".into(), vec![0.0, 0.0, 1.0])].into_iter().collect();
        assert_eq!(my_voice::find(&[0.0, 0.95, 0.1], &prints, "S1").as_deref(), Some("S2"));
        assert_eq!(my_voice::find(&[0.0, 0.7, 0.7], &prints, "S1"), None, "two voices are equally close");
        assert_eq!(my_voice::find(&[1.0, 0.0, 0.0], &prints, "S1"), None, "the teacher is never you");
    }

    #[test]
    fn a_group_close_to_two_others_is_a_blend() {
        let prints: BTreeMap<String, Vec<f32>> = [
            ("A".into(), vec![1.0, 0.0]),
            ("B".into(), vec![0.0, 1.0]),
            ("AB".into(), vec![0.7, 0.7]),
        ]
        .into_iter()
        .collect();
        assert_eq!(my_voice::blends(&prints), ["AB".to_string()].into_iter().collect());
    }

    #[test]
    fn mac_json_reads_back() {
        let json = r#"{"teacher":"S1","seconds":{"S1":757,"S2":50},"checkedAt":785000000,"names":{"S2":"Students"}}"#;
        let voices: MeetingVoices = serde_json::from_str(json).unwrap();
        assert_eq!(voices.name("S2"), VoiceName::Named { name: "Students".into() });
    }
}
