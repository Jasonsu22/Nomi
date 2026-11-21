//! The live transcript: finished lines (commits) grouped into paragraphs, plus the grey line still
//! being spoken (tail). Ported from the Mac's `Live/Transcript.swift`, with the same rules and the
//! same JSON field names, so a saved meeting reads the same on both systems.

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Commit {
    pub id: i64,
    pub source: String,
    pub translation: String,
    pub start: f64,
    pub end: f64,
    /// Whose voice this is ("S1", "R2-S1"…); none when unchecked, too short, or mixed.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub speaker: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Paragraph {
    pub id: i64,
    pub opened_at: f64,
    pub commits: Vec<Commit>,
    pub tail: String,
    pub closed: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_language: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub target_language: Option<String>,
}

pub const AUTOMATIC: &str = "auto";

/// True for languages written with spaces between words.
pub fn uses_spaces(language: &str) -> bool {
    let code = language.to_lowercase();
    !(code == "none" || code.starts_with("zh") || code.starts_with("ja"))
}

fn is_cjk(c: char) -> bool {
    matches!(c as u32, 0x3000..=0x30ff | 0x3400..=0x9fff | 0xf900..=0xfaff | 0xff00..=0xffef | 0x20000..=0x323af)
}

fn needs_separator(left: &str, right: &str, language: &str) -> bool {
    let (Some(last), Some(first)) = (left.chars().last(), right.chars().next()) else { return false };
    if !uses_spaces(language) {
        return false;
    }
    if language != AUTOMATIC {
        return true;
    }
    !last.is_whitespace() && !first.is_whitespace() && !is_cjk(last) && !is_cjk(first)
        && !",.!?;:)]}".contains(first) && !"([{\"".contains(last)
}

/// Joins pieces of one paragraph: with spaces in English, without in Chinese, by character in Auto.
pub fn join(parts: &[&str], language: &str) -> String {
    let pieces: Vec<&str> = parts.iter().map(|p| p.trim()).filter(|p| !p.is_empty()).collect();
    if language == AUTOMATIC {
        let mut result = String::new();
        for piece in pieces {
            if needs_separator(&result, piece, language) {
                result.push(' ');
            }
            result.push_str(piece);
        }
        return result;
    }
    if !uses_spaces(language) {
        return pieces.concat();
    }
    pieces.join(" ")
}

pub struct TranscriptBuilder {
    pub source_language: String,
    pub paragraphs: Vec<Paragraph>,
    next_paragraph_id: i64,
}

impl TranscriptBuilder {
    const MAX_CHARACTERS: usize = 200;
    const SPACED_CHARACTER_LIMIT: usize = 600;
    const PAUSE_GAP: f64 = 2.0;

    pub fn new(source_language: &str, existing: Vec<Paragraph>) -> Self {
        let next_paragraph_id = existing.iter().map(|p| p.id).max().unwrap_or(0) + 1;
        let paragraphs = existing
            .into_iter()
            .map(|mut p| {
                p.closed = true;
                p.tail.clear();
                p
            })
            .collect();
        Self { source_language: source_language.to_string(), paragraphs, next_paragraph_id }
    }

    pub fn apply_tail(&mut self, text: &str, start: f64) {
        let index = self.index_for_incoming(start);
        self.paragraphs[index].tail = text.to_string();
    }

    pub fn apply_commit(&mut self, commit: Commit, tail: &str) {
        let index = self.index_for_incoming(commit.start);
        let end = commit.end;
        self.paragraphs[index].commits.push(commit);
        if self.should_close(index) {
            self.paragraphs[index].tail.clear();
            self.paragraphs[index].closed = true;
            if !tail.is_empty() {
                let next = self.open_paragraph(end);
                self.paragraphs[next].tail = tail.to_string();
            }
        } else {
            self.paragraphs[index].tail = tail.to_string();
        }
    }

    /// Ends the recording: a leftover grey line becomes a line of its own, and every paragraph closes.
    pub fn flush(&mut self, end: f64) {
        if let Some(index) = self.paragraphs.len().checked_sub(1) {
            if !self.paragraphs[index].tail.is_empty() {
                let tail = self.paragraphs[index].tail.clone();
                let start = self.paragraphs[index].commits.last().map(|c| c.end).unwrap_or(self.paragraphs[index].opened_at);
                let id = self.paragraphs.iter().flat_map(|p| p.commits.iter().map(|c| c.id)).max().unwrap_or(0) + 1;
                self.apply_commit(
                    Commit { id, source: tail, translation: String::new(), start, end: end.max(start), speaker: None },
                    "",
                );
            }
        }
        for paragraph in &mut self.paragraphs {
            paragraph.closed = true;
            paragraph.tail.clear();
        }
    }

    fn index_for_incoming(&mut self, start: f64) -> usize {
        let Some(last) = self.paragraphs.len().checked_sub(1) else { return self.open_paragraph(start) };
        if self.paragraphs[last].closed {
            return self.open_paragraph(start);
        }
        let paragraph = &self.paragraphs[last];
        let anchor = paragraph.commits.last().map(|c| c.end).unwrap_or(paragraph.opened_at);
        let has_content = !paragraph.commits.is_empty() || !paragraph.tail.is_empty();
        if has_content && start - anchor > Self::PAUSE_GAP {
            // The grey line belonged to speech that is now being finished in the new paragraph;
            // left here, it would show twice.
            self.paragraphs[last].closed = true;
            self.paragraphs[last].tail.clear();
            return self.open_paragraph(start);
        }
        last
    }

    fn open_paragraph(&mut self, start: f64) -> usize {
        self.paragraphs.push(Paragraph {
            id: self.next_paragraph_id,
            opened_at: start,
            commits: Vec::new(),
            tail: String::new(),
            closed: false,
            source_language: Some(self.source_language.clone()),
            target_language: None,
        });
        self.next_paragraph_id += 1;
        self.paragraphs.len() - 1
    }

    fn should_close(&self, index: usize) -> bool {
        let language = &self.source_language;
        let parts: Vec<&str> = self.paragraphs[index].commits.iter().map(|c| c.source.as_str()).collect();
        let language_of = self.paragraphs[index].source_language.as_deref().unwrap_or(language);
        let text = join(&parts, language_of);
        let limit = if uses_spaces(language) { Self::SPACED_CHARACTER_LIMIT } else { Self::MAX_CHARACTERS };
        let Some(last) = text.chars().last() else { return false };
        if text.chars().count() < limit {
            return false;
        }
        let endings = if language == AUTOMATIC { "。！？.!?" } else if uses_spaces(language) { ".!?" } else { "。！？!?" };
        endings.contains(last)
    }
}

/// A recording run on the meeting's clock: a resumed meeting continues after its earlier runs.
pub struct LiveTranscript {
    pub builder: TranscriptBuilder,
    time_offset: f64,
    commit_id_offset: i64,
}

impl LiveTranscript {
    pub fn new(source_language: &str, existing: Vec<Paragraph>, offset: f64) -> Self {
        let commit_id_offset = existing.iter().flat_map(|p| p.commits.iter().map(|c| c.id)).max().unwrap_or(0);
        Self { builder: TranscriptBuilder::new(source_language, existing), time_offset: offset.max(0.0), commit_id_offset }
    }

    pub fn apply_tail(&mut self, text: &str, start: f64) {
        self.builder.apply_tail(text, start + self.time_offset);
    }

    pub fn apply_commit(&mut self, mut commit: Commit, tail: &str) {
        commit.id += self.commit_id_offset;
        commit.start += self.time_offset;
        commit.end += self.time_offset;
        self.builder.apply_commit(commit, tail);
    }

    pub fn flush(&mut self, end: f64) {
        self.builder.flush(end + self.time_offset);
    }

    pub fn paragraphs(&self) -> &[Paragraph] {
        &self.builder.paragraphs
    }

    pub fn paragraphs_mut(&mut self) -> &mut Vec<Paragraph> {
        &mut self.builder.paragraphs
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn commit(id: i64, source: &str, start: f64, end: f64) -> Commit {
        Commit { id, source: source.into(), translation: String::new(), start, end, speaker: None }
    }

    #[test]
    fn chinese_joins_without_spaces_and_english_with() {
        assert_eq!(join(&["你好", "世界"], "zh"), "你好世界");
        assert_eq!(join(&["Hello", "world"], "en"), "Hello world");
        assert_eq!(join(&["我们用", "transformer", "做"], "auto"), "我们用transformer做");
        assert_eq!(join(&["attention", "is", "all"], "auto"), "attention is all");
    }

    #[test]
    fn a_pause_over_two_seconds_opens_a_paragraph() {
        let mut builder = TranscriptBuilder::new("zh", vec![]);
        builder.apply_commit(commit(1, "第一句。", 0.0, 2.0), "");
        builder.apply_commit(commit(2, "第二句。", 3.0, 4.0), "");
        assert_eq!(builder.paragraphs.len(), 1);
        builder.apply_commit(commit(3, "隔了很久。", 7.0, 8.0), "");
        assert_eq!(builder.paragraphs.len(), 2);
        assert!(builder.paragraphs[0].closed);
    }

    #[test]
    fn a_long_paragraph_closes_at_a_sentence_end() {
        let mut builder = TranscriptBuilder::new("zh", vec![]);
        let long = "很".repeat(199) + "。";
        builder.apply_commit(commit(1, &long, 0.0, 10.0), "下一句");
        assert_eq!(builder.paragraphs.len(), 2);
        assert_eq!(builder.paragraphs[1].tail, "下一句");
    }

    #[test]
    fn a_closed_paragraph_keeps_no_grey_line() {
        let mut builder = TranscriptBuilder::new("en", vec![]);
        builder.apply_commit(commit(1, "One.", 0.0, 1.0), "and th");
        builder.apply_commit(commit(2, "And then two.", 5.0, 6.0), "");
        assert!(builder.paragraphs[0].tail.is_empty());
        assert_eq!(builder.paragraphs.len(), 2);
    }

    #[test]
    fn flush_keeps_the_grey_line() {
        let mut live = LiveTranscript::new("en", vec![], 0.0);
        live.apply_commit(commit(1, "Hello.", 0.0, 1.0), "and then");
        live.flush(2.5);
        let last = live.paragraphs().last().unwrap();
        assert_eq!(last.commits.last().unwrap().source, "and then");
        assert!(last.closed && last.tail.is_empty());
    }

    #[test]
    fn a_resumed_run_continues_the_clock_and_the_ids() {
        let mut first = LiveTranscript::new("en", vec![], 0.0);
        first.apply_commit(commit(1, "One.", 0.0, 1.0), "");
        first.flush(1.0);
        let mut second = LiveTranscript::new("en", first.paragraphs().to_vec(), 60.0);
        second.apply_commit(commit(1, "Two.", 0.0, 1.0), "");
        let last = second.paragraphs().last().unwrap().commits.last().unwrap();
        assert_eq!((last.id, last.start), (2, 60.0));
    }

    #[test]
    fn saved_json_uses_the_mac_field_names() {
        let paragraph = Paragraph {
            id: 1, opened_at: 0.5, commits: vec![commit(1, "a", 0.5, 1.0)], tail: String::new(), closed: true,
            source_language: Some("zh".into()), target_language: None,
        };
        let json = serde_json::to_string(&paragraph).unwrap();
        assert!(json.contains("\"openedAt\":0.5") && json.contains("\"sourceLanguage\":\"zh\""));
        assert!(!json.contains("speaker"));
    }
}
