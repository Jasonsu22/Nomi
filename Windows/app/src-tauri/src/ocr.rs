//! Text in pictures, through Windows' built-in recognizer (Windows.Media.Ocr), in the languages the
//! student has installed. Elsewhere (development on a Mac) there is none.

use std::path::Path;

#[cfg(windows)]
pub fn available() -> bool {
    windows::Media::Ocr::OcrEngine::TryCreateFromUserProfileLanguages().is_ok()
}

#[cfg(not(windows))]
pub fn available() -> bool {
    false
}

#[cfg(windows)]
pub fn recognize(path: &Path) -> Option<String> {
    use windows::core::HSTRING;
    use windows::Graphics::Imaging::BitmapDecoder;
    use windows::Media::Ocr::OcrEngine;
    use windows::Storage::{FileAccessMode, StorageFile};
    let full = std::fs::canonicalize(path).ok()?;
    let text = full.display().to_string();
    let text = text.strip_prefix(r"\\?\").unwrap_or(&text).to_string();
    let file = StorageFile::GetFileFromPathAsync(&HSTRING::from(text)).ok()?.get().ok()?;
    let stream = file.OpenAsync(FileAccessMode::Read).ok()?.get().ok()?;
    let decoder = BitmapDecoder::CreateAsync(&stream).ok()?.get().ok()?;
    let max = OcrEngine::MaxImageDimension().unwrap_or(10_000);
    let (w, h) = (decoder.PixelWidth().ok()?, decoder.PixelHeight().ok()?);
    if w > max || h > max {
        return None;
    }
    let bitmap = decoder.GetSoftwareBitmapAsync().ok()?.get().ok()?;
    let engine = OcrEngine::TryCreateFromUserProfileLanguages().ok()?;
    let result = engine.RecognizeAsync(&bitmap).ok()?.get().ok()?;
    let mut lines = Vec::new();
    for line in result.Lines().ok()? {
        let text = line.Text().ok()?.to_string_lossy();
        if !text.trim().is_empty() {
            lines.push(text);
        }
    }
    let joined = lines.join("\n");
    (!joined.trim().is_empty()).then_some(joined)
}

#[cfg(not(windows))]
pub fn recognize(_path: &Path) -> Option<String> {
    None
}
