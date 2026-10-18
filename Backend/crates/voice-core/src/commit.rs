use crate::buffer::TranscriptBuffer;
use crate::language::is_low_information;
use std::time::{Duration, Instant};

const COMMIT_CHARS: usize = 10;
const IDLE_FLUSH: Duration = Duration::from_secs(9);

#[derive(Debug, Clone)]
pub struct CommitDraft {
    pub id: u64,
    pub source: String,
    pub start: f64,
    pub end: f64,
}

#[derive(Debug, Clone)]
struct Span {
    end_byte: usize,
    start: f64,
    end: f64,
}

pub struct Committer {
    buffer: TranscriptBuffer,
    spaced: bool,
    source_language: String,
    spans: Vec<Span>,
    active_start: f64,
    active_end: f64,
    next_id: u64,
    last_chunk_at: Option<Instant>,
    flush_requested: bool,
    pending: Option<CommitDraft>,
}

impl Committer {
    pub fn new(source_language: impl Into<String>) -> Self {
        let source_language = source_language.into();
        let spaced = crate::language::uses_spaces(&source_language);
        Self {
            buffer: if source_language == "auto" {
                TranscriptBuffer::with_auto_spacing()
            } else {
                TranscriptBuffer::new()
            },
            spaced,
            source_language,
            spans: Vec::new(),
            active_start: 0.0,
            active_end: 0.0,
            next_id: 1,
            last_chunk_at: None,
            flush_requested: false,
            pending: None,
        }
    }

    pub fn tail(&self) -> String {
        self.buffer.uncommitted_tail()
    }

    pub fn observe(&mut self, burst_id: u64, text: &str, start: f64, end: f64, is_final: bool, hit_limit: bool) {
        let mut chunk = text.trim().to_string();
        if hit_limit {
            chunk = strip_terminal_punctuation(&chunk);
        }
        if chunk.is_empty() || is_low_information(&chunk, &self.source_language) {
            if is_final {
                let _ = self.buffer.seal_active_burst(self.spaced);
            }
            return;
        }
        self.last_chunk_at = Some(Instant::now());
        self.active_start = start;
        self.active_end = end;
        self.buffer.update_from_chunk(Some(burst_id as i64), &chunk);
        if is_final && self.buffer.seal_active_burst(self.spaced) {
            self.spans.push(Span {
                end_byte: self.buffer.stable_buffer().len(),
                start,
                end,
            });
        }
    }

    pub fn request_flush(&mut self) {
        self.flush_requested = true;
        if self.buffer.seal_active_burst(self.spaced) {
            self.spans.push(Span {
                end_byte: self.buffer.stable_buffer().len(),
                start: self.active_start,
                end: self.active_end,
            });
        }
    }

    pub fn poll(&mut self, now: Instant) -> Option<CommitDraft> {
        if self.pending.is_some() {
            return None;
        }
        if self
            .last_chunk_at
            .is_some_and(|at| now.duration_since(at) >= IDLE_FLUSH)
            && !self.buffer.buffer().trim().is_empty()
        {
            self.request_flush();
            self.last_chunk_at = None;
        }
        let source = if self.flush_requested {
            let stable = self.buffer.stable_buffer().trim();
            if stable.is_empty() {
                self.flush_requested = false;
                None
            } else {
                Some(stable.to_string())
            }
        } else if self.buffer.has_stable_text(COMMIT_CHARS) {
            commit_boundary(self.buffer.stable_buffer()).map(|end| self.buffer.stable_buffer()[..end].to_string())
        } else {
            None
        }?;
        let (start, end) = self.times_for_prefix(&source);
        let draft = CommitDraft {
            id: self.next_id,
            source,
            start,
            end,
        };
        self.pending = Some(draft.clone());
        Some(draft)
    }

    pub fn finish_pending(&mut self, id: u64) -> Result<String, String> {
        let draft = self.pending.take().ok_or("no pending commit")?;
        if draft.id != id {
            self.pending = Some(draft);
            return Err("pending commit id does not match".into());
        }
        self.buffer.consume_stable_prefix(&draft.source)?;
        let consumed = draft.source.len();
        self.spans.retain(|span| span.end_byte > consumed);
        for span in &mut self.spans {
            span.end_byte -= consumed;
        }
        if self.flush_requested && self.buffer.stable_buffer().trim().is_empty() {
            self.flush_requested = false;
        }
        self.next_id += 1;
        Ok(self.buffer.uncommitted_tail())
    }

    fn times_for_prefix(&self, prefix: &str) -> (f64, f64) {
        let end_byte = prefix.len();
        let mut start = f64::MAX;
        let mut end = 0.0_f64;
        let mut covered = false;
        for span in &self.spans {
            if span.end_byte == 0 {
                continue;
            }
            start = start.min(span.start);
            end = end.max(span.end);
            covered = true;
            if span.end_byte >= end_byte {
                break;
            }
        }
        if covered {
            (start, end)
        } else {
            (0.0, 0.0)
        }
    }
}

fn commit_boundary(text: &str) -> Option<usize> {
    text.char_indices().rev().find_map(|(index, ch)| match ch {
        '，' | ',' | '。' | '.' | '！' | '!' | '？' | '?' | '；' | ';' => Some(index + ch.len_utf8()),
        _ => None,
    })
}

fn strip_terminal_punctuation(chunk: &str) -> String {
    let mut out = chunk.trim_end().to_string();
    if matches!(out.chars().last(), Some('。' | '.' | '！' | '!' | '？' | '?')) {
        out.pop();
    }
    out
}

#[cfg(test)]
mod tests {
    use super::{commit_boundary, Committer};
    use std::time::Instant;

    #[test]
    fn boundary_prefers_the_last_separator() {
        let text = "今天我们讲注意力，它的";
        let end = commit_boundary(text).unwrap();
        assert_eq!(&text[..end], "今天我们讲注意力，");
    }

    #[test]
    fn a_sealed_sentence_can_be_committed() {
        let mut committer = Committer::new("zh");
        committer.observe(1, "今天我们讲注意力机制，", 1.0, 3.0, true, false);
        let draft = committer.poll(Instant::now()).expect("sentence should commit");
        assert_eq!(draft.source, "今天我们讲注意力机制，");
        assert_eq!(draft.start, 1.0);
        let tail = committer.finish_pending(draft.id).unwrap();
        assert!(tail.is_empty());
    }

    #[test]
    fn english_bursts_do_not_glue_words_together() {
        let mut committer = Committer::new("en");
        committer.observe(1, "attention", 0.0, 1.0, true, false);
        committer.observe(2, "it.", 1.2, 2.0, true, false);
        assert_eq!(committer.tail(), "attention it.");
        let draft = committer.poll(Instant::now()).unwrap();
        assert_eq!(draft.source, "attention it.");
        assert_eq!(draft.start, 0.0);
        assert_eq!(draft.end, 2.0);
    }
}
