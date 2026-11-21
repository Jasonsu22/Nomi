//! Pictures for chats and cards: check and convert on the way in, shrink for the model, thumbnails.

use base64::Engine as _;
use image::{DynamicImage, GenericImageView, ImageFormat};
use serde::Serialize;
use std::io::Cursor;

use crate::platform::{text, Result};

#[derive(Serialize)]
pub struct Payload {
    mime: String,
    base64: String,
}

#[derive(Serialize)]
pub struct Checked {
    mime: String,
}

fn mime_of(format: ImageFormat) -> Option<&'static str> {
    Some(match format {
        ImageFormat::Png => "image/png",
        ImageFormat::Jpeg => "image/jpeg",
        ImageFormat::Gif => "image/gif",
        ImageFormat::WebP => "image/webp",
        _ => return None,
    })
}

fn encode(picture: &DynamicImage, png: bool) -> Result<Vec<u8>> {
    let mut out = Cursor::new(Vec::new());
    if png {
        picture.write_to(&mut out, ImageFormat::Png).map_err(text)?;
    } else {
        let rgb = DynamicImage::ImageRgb8(picture.to_rgb8());
        let mut encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, 85);
        encoder.encode_image(&rgb).map_err(text)?;
    }
    Ok(out.into_inner())
}

/// Checks the picture; TIFF and BMP become PNG in place (models read PNG, JPEG, GIF and WebP).
#[tauri::command]
pub async fn image_normalize(path: String) -> Option<Checked> {
    tokio::task::spawn_blocking(move || {
        let bytes = std::fs::read(&path).ok()?;
        let format = image::guess_format(&bytes).ok()?;
        if let Some(mime) = mime_of(format) {
            image::load_from_memory_with_format(&bytes, format).ok()?;
            return Some(Checked { mime: mime.into() });
        }
        let picture = image::load_from_memory(&bytes).ok()?;
        let png = encode(&picture, true).ok()?;
        std::fs::write(&path, png).ok()?;
        Some(Checked { mime: "image/png".into() })
    })
    .await
    .ok()
    .flatten()
}

/// At most 2048 px on the long side, as base64 for an API request.
#[tauri::command]
pub async fn image_payload(path: String, mime: String) -> Option<Payload> {
    tokio::task::spawn_blocking(move || {
        let bytes = std::fs::read(&path).ok()?;
        let picture = image::load_from_memory(&bytes).ok()?;
        let (w, h) = picture.dimensions();
        if w.max(h) <= 2048 && (mime == "image/png" || mime == "image/jpeg" || mime == "image/webp" || mime == "image/gif") {
            return Some(Payload { mime, base64: base64::engine::general_purpose::STANDARD.encode(bytes) });
        }
        let smaller = if w.max(h) > 2048 { picture.resize(2048, 2048, image::imageops::FilterType::Lanczos3) } else { picture };
        let png = mime == "image/png" || mime == "image/gif";
        let data = encode(&smaller, png).ok()?;
        Some(Payload { mime: if png { "image/png".into() } else { "image/jpeg".into() }, base64: base64::engine::general_purpose::STANDARD.encode(data) })
    })
    .await
    .ok()
    .flatten()
}

/// A small copy as a data URL, for preview cards.
#[tauri::command]
pub async fn image_thumbnail(path: String, size: u32) -> Option<String> {
    tokio::task::spawn_blocking(move || {
        let picture = image::open(&path).ok()?;
        let thumb = picture.thumbnail(size, size);
        let data = encode(&thumb, false).ok()?;
        Some(format!("data:image/jpeg;base64,{}", base64::engine::general_purpose::STANDARD.encode(data)))
    })
    .await
    .ok()
    .flatten()
}
