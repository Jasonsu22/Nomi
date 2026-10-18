#[derive(Debug, Default, Clone)]
pub struct TranscriptBuffer {
    buffer: String,
    stable_buffer: String,
    active_burst_id: Option<i64>,
    active_burst_text: String,
    auto_spacing: bool,
}

impl TranscriptBuffer {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_auto_spacing() -> Self {
        Self { auto_spacing: true, ..Self::default() }
    }

    pub fn buffer(&self) -> &str {
        &self.buffer
    }

    pub fn stable_buffer(&self) -> &str {
        &self.stable_buffer
    }

    pub fn active_burst_text(&self) -> &str {
        &self.active_burst_text
    }

    pub fn update_from_chunk(&mut self, burst_id: Option<i64>, chunk: &str) -> bool {
        if chunk.is_empty() {
            return false;
        }
        let old_buffer = self.buffer.clone();
        match self.active_burst_id {
            None => {
                self.active_burst_id = burst_id;
                self.active_burst_text = chunk.to_string();
            }
            Some(active_id) if Some(active_id) == burst_id => {
                self.active_burst_text = chunk.to_string();
            }
            Some(_) => {
                self.seal_active_burst(false);
                self.active_burst_id = burst_id;
                self.active_burst_text = chunk.to_string();
            }
        }
        self.rebuild_views();
        self.buffer != old_buffer
    }

    pub fn seal_active_burst(&mut self, spaced: bool) -> bool {
        if self.active_burst_text.is_empty() {
            self.active_burst_id = None;
            self.rebuild_views();
            return false;
        }
        if self.needs_separator(spaced) {
            self.stable_buffer.push(' ');
        }
        self.stable_buffer.push_str(&self.active_burst_text);
        self.active_burst_text.clear();
        self.active_burst_id = None;
        self.rebuild_views();
        true
    }

    pub fn consume_stable_prefix(&mut self, prefix: &str) -> Result<(), String> {
        if prefix.is_empty() {
            return Ok(());
        }
        if !self.stable_buffer.starts_with(prefix) {
            return Err("consumed prefix is not a prefix of stable_buffer".into());
        }
        self.stable_buffer.drain(..prefix.len());
        self.rebuild_views();
        Ok(())
    }

    pub fn uncommitted_tail(&self) -> String {
        self.buffer.trim().to_string()
    }

    pub fn has_stable_text(&self, min_chars: usize) -> bool {
        self.stable_buffer.trim().chars().count() >= min_chars
    }

    fn rebuild_views(&mut self) {
        self.buffer.clear();
        self.buffer.push_str(&self.stable_buffer);
        if self.auto_spacing && self.needs_separator(true) {
            self.buffer.push(' ');
        }
        self.buffer.push_str(&self.active_burst_text);
    }

    fn needs_separator(&self, spaced: bool) -> bool {
        if !self.auto_spacing {
            return spaced && needs_space(&self.stable_buffer, &self.active_burst_text);
        }
        let Some(left) = self.stable_buffer.chars().last() else { return false };
        let Some(right) = self.active_burst_text.chars().next() else { return false };
        !left.is_whitespace() && !right.is_whitespace()
            && !is_cjk(left) && !is_cjk(right)
            && !",.!?;:)]}".contains(right) && !"([{\"".contains(left)
    }
}

fn is_cjk(ch: char) -> bool {
    matches!(ch as u32, 0x3000..=0x30ff | 0x3400..=0x9fff | 0xf900..=0xfaff | 0xff00..=0xffef | 0x20000..=0x323af)
}

fn needs_space(left: &str, right: &str) -> bool {
    let left_open = left.chars().last().is_some_and(|ch| !ch.is_whitespace());
    let right_open = right.chars().next().is_some_and(|ch| !ch.is_whitespace());
    left_open && right_open
}

#[cfg(test)]
mod tests {
    use super::TranscriptBuffer;

    #[test]
    fn same_burst_replaces_active_text() {
        let mut state = TranscriptBuffer::new();
        state.update_from_chunk(Some(7), "今天我们讲");
        state.update_from_chunk(Some(7), "今天我们讲注意力");
        assert_eq!(state.buffer(), "今天我们讲注意力");
        assert_eq!(state.stable_buffer(), "");
    }

    #[test]
    fn chinese_bursts_join_without_a_space() {
        let mut state = TranscriptBuffer::new();
        state.update_from_chunk(Some(1), "大家下午好。");
        state.seal_active_burst(false);
        state.update_from_chunk(Some(2), "我叫鲍月。");
        state.seal_active_burst(false);
        assert_eq!(state.stable_buffer(), "大家下午好。我叫鲍月。");
    }

    #[test]
    fn english_bursts_keep_a_space_between_words() {
        let mut state = TranscriptBuffer::new();
        state.update_from_chunk(Some(1), "attention");
        state.seal_active_burst(true);
        state.update_from_chunk(Some(2), "it");
        state.seal_active_burst(true);
        assert_eq!(state.stable_buffer(), "attention it");
    }
}
