//! The text inside imported files, in the pieces Sources/LectureNoteApp/Models/SourceText.swift
//! reads: PDF pages, slides, sheets, EPUB chapters, Word and OpenDocument text, web pages, plain
//! text, and pictures (through Windows' own text recognition).

use quick_xml::events::Event;
use quick_xml::Reader;
use serde::Serialize;
use std::collections::BTreeMap;
use std::io::Read;
use std::path::Path;

use crate::platform::{text, Result};

#[derive(Serialize, Clone)]
pub struct Segment {
    kind: &'static str,
    index: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    name: Option<String>,
    text: String,
}

fn seg(kind: &'static str, index: usize, text: String) -> Segment {
    Segment { kind, index, name: None, text }
}

const PLAIN: &[&str] = &[
    "txt", "text", "md", "markdown", "csv", "tsv", "json", "xml", "yaml", "yml", "tex", "bib", "srt", "vtt", "log", "py", "swift", "js", "mjs", "ts", "tsx",
    "jsx", "java", "kt", "c", "cc", "cpp", "h", "hpp", "m", "mm", "cs", "go", "rs", "rb", "php", "sh", "zsh", "sql", "r", "scala", "lua", "css", "scss",
];
const PICTURES: &[&str] = &["png", "jpg", "jpeg", "heic", "gif", "webp", "tif", "tiff", "bmp"];

#[tauri::command]
pub async fn document_segments(path: String) -> Result<Vec<Segment>> {
    tokio::task::spawn_blocking(move || segments(Path::new(&path))).await.map_err(text)?
}

#[tauri::command]
pub async fn document_page_count(path: String) -> Option<usize> {
    tokio::task::spawn_blocking(move || lopdf::Document::load(&path).ok().map(|d| d.get_pages().len())).await.ok().flatten()
}

#[tauri::command]
pub fn ocr_available() -> bool {
    crate::ocr::available()
}

pub fn segments(path: &Path) -> Result<Vec<Segment>> {
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase();
    let ext = ext.as_str();
    if PLAIN.contains(&ext) {
        return Ok(vec![seg("text", 1, read_text(path)?)]);
    }
    if PICTURES.contains(&ext) {
        return Ok(crate::ocr::recognize(path).map(|t| vec![seg("text", 1, t)]).unwrap_or_default());
    }
    match ext {
        "ipynb" => Ok(vec![seg("text", 1, notebook(&read_text(path)?))]),
        "html" | "htm" | "xhtml" => Ok(vec![seg("text", 1, html_text(&read_text(path)?))]),
        "rtf" => Ok(vec![seg("text", 1, rtf_text(&read_text(path)?))]),
        "pdf" => pdf(path),
        "docx" => docx(path),
        "odt" => odt(path),
        "pptx" => pptx(path),
        "xlsx" => xlsx(path),
        "epub" => epub(path),
        _ => Err(format!("cannot read .{ext}")),
    }
}

fn read_text(path: &Path) -> Result<String> {
    let bytes = std::fs::read(path).map_err(text)?;
    // UTF-16 files from Notepad start with a byte-order mark.
    if bytes.starts_with(&[0xFF, 0xFE]) {
        let units: Vec<u16> = bytes[2..].chunks_exact(2).map(|c| u16::from_le_bytes([c[0], c[1]])).collect();
        return Ok(String::from_utf16_lossy(&units));
    }
    let start = if bytes.starts_with(&[0xEF, 0xBB, 0xBF]) { 3 } else { 0 };
    Ok(String::from_utf8_lossy(&bytes[start..]).into_owned())
}

fn notebook(json: &str) -> String {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(json) else { return json.to_string() };
    let mut out = Vec::new();
    for cell in value["cells"].as_array().into_iter().flatten() {
        let source = match &cell["source"] {
            serde_json::Value::Array(lines) => lines.iter().filter_map(|l| l.as_str()).collect::<String>(),
            serde_json::Value::String(s) => s.clone(),
            _ => continue,
        };
        if !source.trim().is_empty() {
            out.push(source);
        }
    }
    out.join("\n\n")
}

fn decode_entities(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(i) = rest.find('&') {
        out.push_str(&rest[..i]);
        rest = &rest[i..];
        let Some(end) = rest.find(';').filter(|e| *e < 10) else {
            out.push('&');
            rest = &rest[1..];
            continue;
        };
        let name = &rest[1..end];
        let ch = match name {
            "amp" => Some('&'),
            "lt" => Some('<'),
            "gt" => Some('>'),
            "quot" => Some('"'),
            "apos" => Some('\''),
            "nbsp" => Some(' '),
            _ if name.starts_with("#x") || name.starts_with("#X") => u32::from_str_radix(&name[2..], 16).ok().and_then(char::from_u32),
            _ if name.starts_with('#') => name[1..].parse().ok().and_then(char::from_u32),
            _ => None,
        };
        match ch {
            Some(c) => {
                out.push(c);
                rest = &rest[end + 1..];
            }
            None => {
                out.push('&');
                rest = &rest[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

/// Visible text of a web page: no scripts or styles, one line per block.
pub fn html_text(html: &str) -> String {
    let lower = html.to_ascii_lowercase();
    let mut out = String::new();
    let mut i = 0;
    let bytes = html.as_bytes();
    while i < bytes.len() {
        if bytes[i] == b'<' {
            let Some(close) = html[i..].find('>') else { break };
            let tag = &lower[i + 1..i + close];
            let name: String = tag.trim_start_matches('/').chars().take_while(|c| c.is_ascii_alphanumeric()).collect();
            if !tag.starts_with('/') && (name == "script" || name == "style" || name == "noscript" || name == "head") {
                if let Some(end) = lower[i..].find(&format!("</{name}")) {
                    i += end;
                    continue;
                }
            }
            if ["p", "div", "br", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "section", "article", "table", "blockquote", "pre"].contains(&name.as_str()) {
                out.push('\n');
            }
            i += close + 1;
        } else {
            let next = html[i..].find('<').map(|n| i + n).unwrap_or(html.len());
            out.push_str(&html[i..next]);
            i = next;
        }
    }
    tidy(&decode_entities(&out))
}

fn tidy(text: &str) -> String {
    let mut lines: Vec<String> = Vec::new();
    for line in text.lines() {
        let line = line.split_whitespace().collect::<Vec<_>>().join(" ");
        if line.is_empty() && lines.last().is_some_and(|l| l.is_empty()) {
            continue;
        }
        lines.push(line);
    }
    lines.join("\n").trim().to_string()
}

/// RTF without its control words and groups like fonts and colours.
fn rtf_text(rtf: &str) -> String {
    let mut out = String::new();
    let chars: Vec<char> = rtf.chars().collect();
    let mut i = 0;
    let mut skip_depth: Option<usize> = None;
    let mut depth = 0usize;
    while i < chars.len() {
        let c = chars[i];
        match c {
            '{' => {
                depth += 1;
                let ahead: String = chars[i + 1..chars.len().min(i + 13)].iter().collect();
                if skip_depth.is_none() && ["\\*", "\\fonttbl", "\\colortbl", "\\stylesheet", "\\info", "\\pict"].iter().any(|p| ahead.starts_with(p)) {
                    skip_depth = Some(depth);
                }
                i += 1;
            }
            '}' => {
                if skip_depth == Some(depth) {
                    skip_depth = None;
                }
                depth = depth.saturating_sub(1);
                i += 1;
            }
            '\\' => {
                i += 1;
                if i >= chars.len() {
                    break;
                }
                let n = chars[i];
                if n == '\\' || n == '{' || n == '}' {
                    if skip_depth.is_none() {
                        out.push(n);
                    }
                    i += 1;
                } else if n == '\'' && i + 2 < chars.len() {
                    let hex: String = chars[i + 1..i + 3].iter().collect();
                    if let (Ok(b), None) = (u8::from_str_radix(&hex, 16), skip_depth) {
                        out.push(b as char);
                    }
                    i += 3;
                } else {
                    let mut word = String::new();
                    while i < chars.len() && chars[i].is_ascii_alphabetic() {
                        word.push(chars[i]);
                        i += 1;
                    }
                    let mut number = String::new();
                    while i < chars.len() && (chars[i].is_ascii_digit() || chars[i] == '-') {
                        number.push(chars[i]);
                        i += 1;
                    }
                    if i < chars.len() && chars[i] == ' ' {
                        i += 1;
                    }
                    if skip_depth.is_some() {
                        continue;
                    }
                    match word.as_str() {
                        "par" | "line" | "row" => out.push('\n'),
                        "tab" | "cell" => out.push('\t'),
                        "u" => {
                            if let Some(ch) = number.parse::<i32>().ok().map(|v| if v < 0 { v + 65536 } else { v }).and_then(|v| char::from_u32(v as u32)) {
                                out.push(ch);
                            }
                            if i < chars.len() && chars[i] == '?' {
                                i += 1;
                            }
                        }
                        _ => {}
                    }
                }
            }
            '\r' | '\n' => i += 1,
            _ => {
                if skip_depth.is_none() {
                    out.push(c);
                }
                i += 1;
            }
        }
    }
    tidy(&out)
}

fn pdf(path: &Path) -> Result<Vec<Segment>> {
    let bytes = std::fs::read(path).map_err(text)?;
    let pages = pdf_extract::extract_text_from_mem_by_pages(&bytes).map_err(text)?;
    Ok(pages.into_iter().enumerate().map(|(i, t)| seg("page", i + 1, tidy(&t))).collect())
}

fn archive(path: &Path) -> Result<zip::ZipArchive<std::fs::File>> {
    zip::ZipArchive::new(std::fs::File::open(path).map_err(text)?).map_err(text)
}

fn entry_text(zip: &mut zip::ZipArchive<std::fs::File>, name: &str) -> Option<String> {
    let mut file = zip.by_name(name).ok()?;
    let mut s = String::new();
    file.read_to_string(&mut s).ok()?;
    Some(s)
}

/// The text of an XML part: each `text_tag` element's text, a line break after each `para_tag`.
fn xml_text(xml: &str, text_tags: &[&[u8]], para_tags: &[&[u8]], tab_tags: &[&[u8]]) -> String {
    let mut reader = Reader::from_str(xml);
    let mut out = String::new();
    let mut inside = 0usize;
    loop {
        match reader.read_event() {
            Ok(Event::Start(e)) => {
                if text_tags.contains(&e.local_name().as_ref()) {
                    inside += 1;
                }
            }
            Ok(Event::Empty(e)) => {
                let n = e.local_name();
                if tab_tags.contains(&n.as_ref()) {
                    out.push('\t');
                } else if n.as_ref() == b"br" || n.as_ref() == b"line-break" {
                    out.push('\n');
                } else if n.as_ref() == b"s" {
                    out.push(' ');
                }
            }
            Ok(Event::End(e)) => {
                let n = e.local_name();
                if text_tags.contains(&n.as_ref()) {
                    inside = inside.saturating_sub(1);
                }
                if para_tags.contains(&n.as_ref()) {
                    out.push('\n');
                }
            }
            Ok(Event::Text(t)) if inside > 0 => {
                if let Ok(s) = t.unescape() {
                    out.push_str(&s);
                }
            }
            Ok(Event::Eof) | Err(_) => break,
            _ => {}
        }
    }
    tidy(&out)
}

/// Pictures inside an Office file, read by OCR, each as a `picture` segment.
fn media_pictures(zip: &mut zip::ZipArchive<std::fs::File>, prefix: &str) -> Vec<Segment> {
    if !crate::ocr::available() {
        return Vec::new();
    }
    let names: Vec<String> = zip.file_names().filter(|n| n.starts_with(prefix)).map(String::from).collect();
    let mut out = Vec::new();
    for (i, name) in names.iter().enumerate().take(40) {
        let ext = name.rsplit('.').next().unwrap_or("").to_ascii_lowercase();
        if !["png", "jpg", "jpeg", "bmp", "gif", "tif", "tiff"].contains(&ext.as_str()) {
            continue;
        }
        let Ok(mut file) = zip.by_name(name) else { continue };
        if file.size() < 8_000 {
            continue;
        }
        let mut bytes = Vec::new();
        if file.read_to_end(&mut bytes).is_err() {
            continue;
        }
        let temp = std::env::temp_dir().join(format!("nomi-ocr-{}-{i}.{ext}", std::process::id()));
        if std::fs::write(&temp, &bytes).is_ok() {
            if let Some(t) = crate::ocr::recognize(&temp).filter(|t| t.trim().chars().count() >= 8) {
                out.push(seg("picture", out.len() + 1, t));
            }
            let _ = std::fs::remove_file(&temp);
        }
    }
    out
}

fn docx(path: &Path) -> Result<Vec<Segment>> {
    let mut zip = archive(path)?;
    let body = entry_text(&mut zip, "word/document.xml").ok_or("not a Word document")?;
    let mut out = vec![seg("text", 1, xml_text(&body, &[b"t"], &[b"p", b"tr"], &[b"tab"]))];
    out.extend(media_pictures(&mut zip, "word/media/"));
    Ok(out)
}

fn odt(path: &Path) -> Result<Vec<Segment>> {
    let mut zip = archive(path)?;
    let body = entry_text(&mut zip, "content.xml").ok_or("not an OpenDocument file")?;
    Ok(vec![seg("text", 1, xml_text(&body, &[b"p", b"h", b"span"], &[b"p", b"h"], &[b"tab"]))])
}

fn number_in(name: &str, prefix: &str) -> Option<usize> {
    name.strip_prefix(prefix)?.strip_suffix(".xml")?.parse().ok()
}

fn pptx(path: &Path) -> Result<Vec<Segment>> {
    let mut zip = archive(path)?;
    let mut slides: Vec<(usize, String)> = zip.file_names().filter_map(|n| number_in(n, "ppt/slides/slide").map(|i| (i, n.to_string()))).collect();
    slides.sort();
    let mut out = Vec::new();
    for (index, name) in slides {
        let xml = entry_text(&mut zip, &name).unwrap_or_default();
        let mut body = xml_text(&xml, &[b"t"], &[b"p"], &[]);
        if let Some(notes) = entry_text(&mut zip, &format!("ppt/notesSlides/notesSlide{index}.xml")) {
            let notes = xml_text(&notes, &[b"t"], &[b"p"], &[]);
            if !notes.is_empty() {
                body.push_str("\n\n");
                body.push_str(&notes);
            }
        }
        out.push(seg("slide", index, body));
    }
    out.extend(media_pictures(&mut zip, "ppt/media/"));
    Ok(out)
}

fn xlsx(path: &Path) -> Result<Vec<Segment>> {
    let mut zip = archive(path)?;
    let mut shared: Vec<String> = Vec::new();
    if let Some(xml) = entry_text(&mut zip, "xl/sharedStrings.xml") {
        let mut reader = Reader::from_str(&xml);
        let mut current = String::new();
        let mut inside = false;
        loop {
            match reader.read_event() {
                Ok(Event::Start(e)) if e.local_name().as_ref() == b"t" => inside = true,
                Ok(Event::End(e)) if e.local_name().as_ref() == b"t" => inside = false,
                Ok(Event::End(e)) if e.local_name().as_ref() == b"si" => shared.push(std::mem::take(&mut current)),
                Ok(Event::Text(t)) if inside => current.push_str(&t.unescape().unwrap_or_default()),
                Ok(Event::Eof) | Err(_) => break,
                _ => {}
            }
        }
    }
    let mut names: Vec<String> = Vec::new();
    if let Some(xml) = entry_text(&mut zip, "xl/workbook.xml") {
        let mut reader = Reader::from_str(&xml);
        loop {
            match reader.read_event() {
                Ok(Event::Empty(e)) | Ok(Event::Start(e)) if e.local_name().as_ref() == b"sheet" => {
                    if let Some(a) = e.attributes().flatten().find(|a| a.key.as_ref() == b"name") {
                        names.push(a.unescape_value().unwrap_or_default().into_owned());
                    }
                }
                Ok(Event::Eof) | Err(_) => break,
                _ => {}
            }
        }
    }
    let mut sheets: Vec<(usize, String)> = zip.file_names().filter_map(|n| number_in(n, "xl/worksheets/sheet").map(|i| (i, n.to_string()))).collect();
    sheets.sort();
    let mut out = Vec::new();
    for (index, name) in sheets {
        let xml = entry_text(&mut zip, &name).unwrap_or_default();
        let mut reader = Reader::from_str(&xml);
        let mut rows: BTreeMap<usize, Vec<String>> = BTreeMap::new();
        let mut row = 0usize;
        let mut kind = String::new();
        let mut in_value = false;
        let mut value = String::new();
        loop {
            match reader.read_event() {
                Ok(Event::Start(e)) => match e.local_name().as_ref() {
                    b"row" => row += 1,
                    b"c" => kind = e.attributes().flatten().find(|a| a.key.as_ref() == b"t").map(|a| a.unescape_value().unwrap_or_default().into_owned()).unwrap_or_default(),
                    b"v" | b"t" => {
                        in_value = true;
                        value.clear();
                    }
                    _ => {}
                },
                Ok(Event::Text(t)) if in_value => value.push_str(&t.unescape().unwrap_or_default()),
                Ok(Event::End(e)) => match e.local_name().as_ref() {
                    b"v" | b"t" => {
                        in_value = false;
                        let cell = if kind == "s" { value.trim().parse::<usize>().ok().and_then(|i| shared.get(i).cloned()).unwrap_or_default() } else { value.clone() };
                        if !cell.trim().is_empty() {
                            rows.entry(row).or_default().push(cell);
                        }
                    }
                    _ => {}
                },
                Ok(Event::Eof) | Err(_) => break,
                _ => {}
            }
        }
        let body = rows.values().map(|cells| cells.join("\t")).collect::<Vec<_>>().join("\n");
        out.push(Segment { kind: "sheet", index, name: names.get(index - 1).cloned(), text: body });
    }
    Ok(out)
}

fn epub(path: &Path) -> Result<Vec<Segment>> {
    let mut zip = archive(path)?;
    let container = entry_text(&mut zip, "META-INF/container.xml").ok_or("not an EPUB")?;
    let opf_path = container.split("full-path=\"").nth(1).and_then(|s| s.split('"').next()).ok_or("not an EPUB")?.to_string();
    let opf = entry_text(&mut zip, &opf_path).unwrap_or_default();
    let base = opf_path.rsplit_once('/').map(|(b, _)| format!("{b}/")).unwrap_or_default();
    let mut manifest: BTreeMap<String, String> = BTreeMap::new();
    let mut spine: Vec<String> = Vec::new();
    let mut reader = Reader::from_str(&opf);
    loop {
        match reader.read_event() {
            Ok(Event::Empty(e)) | Ok(Event::Start(e)) => {
                let attr = |key: &[u8]| e.attributes().flatten().find(|a| a.key.as_ref() == key).map(|a| a.unescape_value().unwrap_or_default().into_owned());
                match e.local_name().as_ref() {
                    b"item" => {
                        if let (Some(id), Some(href)) = (attr(b"id"), attr(b"href")) {
                            manifest.insert(id, href);
                        }
                    }
                    b"itemref" => {
                        if let Some(id) = attr(b"idref") {
                            spine.push(id);
                        }
                    }
                    _ => {}
                }
            }
            Ok(Event::Eof) | Err(_) => break,
            _ => {}
        }
    }
    let mut out = Vec::new();
    for id in spine {
        let Some(href) = manifest.get(&id) else { continue };
        let name = format!("{base}{}", href.split('#').next().unwrap_or(href));
        let Some(html) = entry_text(&mut zip, &name) else { continue };
        let body = html_text(&html);
        if !body.is_empty() {
            out.push(seg("chapter", out.len() + 1, body));
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn web_pages_lose_scripts_and_tags() {
        let page = "<html><head><title>x</title></head><body><script>var a=1;</script><p>Hello&nbsp;<b>world</b></p><div>Second &amp; line</div></body></html>";
        assert_eq!(html_text(page), "Hello world\n\nSecond & line");
    }

    #[test]
    fn rtf_keeps_words_and_unicode() {
        let rtf = r"{\rtf1\ansi{\fonttbl\f0 Helvetica;}\f0 Hello \b world\b0\par \u20013?\u25991?}";
        assert_eq!(rtf_text(rtf), "Hello world\n中文");
    }

    #[test]
    fn notebooks_give_their_cells() {
        let nb = r##"{"cells":[{"source":["a = 1\n","b = 2"]},{"source":"# Title"}]}"##;
        assert_eq!(notebook(nb), "a = 1\nb = 2\n\n# Title");
    }
}

#[cfg(test)]
mod real_files {
    /// NOMI_DOCS=path1:path2 cargo test real_files -- --nocapture
    #[test]
    fn reads_real_files() {
        let Ok(list) = std::env::var("NOMI_DOCS") else { return };
        for path in list.split(':').filter(|p| !p.is_empty()) {
            let segments = super::segments(std::path::Path::new(path)).unwrap_or_else(|e| panic!("{path}: {e}"));
            let chars: usize = segments.iter().map(|s| s.text.chars().count()).sum();
            let first = segments.iter().find(|s| !s.text.trim().is_empty()).map(|s| s.text.chars().take(80).collect::<String>()).unwrap_or_default();
            println!("{path}: {} segments ({}), {chars} chars: {first:?}", segments.len(), segments.first().map(|s| s.kind).unwrap_or("-"));
            assert!(chars > 0, "{path} gave no text");
        }
    }
}
