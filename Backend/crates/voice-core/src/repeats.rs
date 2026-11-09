//! Speech models sometimes fall into a loop on silence or noise and write the same word or phrase
//! hundreds of times ("Okay. Okay. Okay. …", "对对对对…"). This keeps the first one of such a run.
//! Ordinary emphasis ("very very very", "no, no, no") is shorter than the limits and is kept.

/// The longest repeating phrase looked for, in words (or characters for Chinese and Japanese).
const LONGEST_PHRASE: usize = 12;

/// Whether a phrase of this many words appearing this many times in a row is a loop: one word 8
/// times, or a longer phrase 4 times covering 12 words or more. A teacher saying "雅思，雅思，雅思，
/// 雅思" or "no, no, no, no" stays.
fn is_loop(phrase_units: usize, count: usize) -> bool {
    if phrase_units == 1 { count >= 8 } else { count >= 4 && count * phrase_units >= 12 }
}

/// One word, or one Chinese or Japanese character, with the punctuation and space after it.
struct Unit<'a> {
    text: &'a str,
    key: String,
}

fn is_cjk(c: char) -> bool {
    matches!(c as u32, 0x3040..=0x30ff | 0x3400..=0x9fff | 0xac00..=0xd7af | 0xf900..=0xfaff | 0x20000..=0x323af)
}

fn units(text: &str) -> Vec<Unit<'_>> {
    let mut result = Vec::new();
    let mut start = 0;
    let mut in_core = false;
    let mut core_done = false;
    let mut key = String::new();
    for (index, c) in text.char_indices() {
        let word_char = c.is_alphanumeric() || c == '\'' || c == '’';
        // A new unit starts at the next word character after a finished core, and at every
        // Chinese or Japanese character.
        let starts_new = word_char && (core_done || (in_core && (is_cjk(c) || key.chars().last().is_some_and(is_cjk))));
        if starts_new && index > start {
            result.push(Unit { text: &text[start..index], key: std::mem::take(&mut key) });
            start = index;
            core_done = false;
        }
        if word_char {
            in_core = true;
            key.extend(c.to_lowercase());
        } else if in_core {
            core_done = true;
        }
    }
    if start < text.len() {
        result.push(Unit { text: &text[start..], key });
    }
    result
}

fn same(units: &[Unit<'_>], a: usize, b: usize, length: usize) -> bool {
    (0..length).all(|offset| {
        let (x, y) = (&units[a + offset].key, &units[b + offset].key);
        !x.is_empty() && x == y
    })
}

/// The text with every loop of a repeated word or phrase cut back to its first time.
pub fn collapse_repeats(text: &str) -> String {
    let units = units(text);
    let mut kept = String::with_capacity(text.len());
    let mut index = 0;
    while index < units.len() {
        // The phrase length whose run covers the most text from here.
        let mut best: Option<(usize, usize)> = None;
        for length in 1..=LONGEST_PHRASE {
            if index + length * 2 > units.len() {
                break;
            }
            let mut count = 1;
            while index + (count + 1) * length <= units.len() && same(&units, index, index + count * length, length) {
                count += 1;
            }
            if is_loop(length, count) && best.is_none_or(|(l, c)| count * length > l * c) {
                best = Some((length, count));
            }
        }
        match best {
            Some((length, count)) => {
                for unit in &units[index..index + length] {
                    kept.push_str(unit.text);
                }
                index += length * count;
            }
            None => {
                kept.push_str(units[index].text);
                index += 1;
            }
        }
    }
    let trimmed = kept.trim_end();
    if trimmed.len() == text.trim_end().len() {
        text.to_string()
    } else {
        trimmed.to_string()
    }
}

/// Whether the text holds a loop that `collapse_repeats` would cut.
pub fn has_repeat_loop(text: &str) -> bool {
    collapse_repeats(text) != text
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_word_said_hundreds_of_times_is_kept_once() {
        let looped = format!("Can you tell the first thing? {}", "Okay. ".repeat(300));
        assert_eq!(collapse_repeats(&looped), "Can you tell the first thing? Okay.");
    }

    #[test]
    fn a_looping_phrase_is_kept_once_and_what_follows_stays() {
        let looped = format!("{}and then we start.", "you can see the summary, ".repeat(8));
        assert_eq!(collapse_repeats(&looped), "you can see the summary, and then we start.");
    }

    #[test]
    fn chinese_loops_are_cut_too() {
        assert_eq!(collapse_repeats(&format!("好的，{}下一题", "对".repeat(40))), "好的，对下一题");
        assert_eq!(collapse_repeats(&"我们看一下。".repeat(20)), "我们看一下。");
    }

    #[test]
    fn ordinary_emphasis_is_left_alone() {
        for text in [
            "It is very very very important.",
            "No, no, no, that's not it.",
            "Okay. Okay. Let's start.",
            "对对对，就是这个。",
            "哈哈哈",
            "啊，Ielts，雅思，雅思，雅思，雅思，那种文科音。",
            "到到到，到到到，",
            "1 2 3 4 5 6 7 8",
            "The the cat.",
        ] {
            assert_eq!(collapse_repeats(text), text, "{text:?}");
        }
    }

    #[test]
    fn case_and_punctuation_do_not_hide_a_loop() {
        assert_eq!(collapse_repeats("okay, Okay. OKAY! okay okay. okay Okay okay."), "okay,");
        assert!(has_repeat_loop(&"Thank you. ".repeat(10)));
        assert!(!has_repeat_loop("Thank you."));
    }
}
