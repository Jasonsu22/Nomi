use serde::{Deserialize, Serialize};
use std::io::{Read, Write};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum WorkerRequest {
    Transcribe { id: u64, language: String },
    Translate { id: u64, text: String, target_language: String },
    Generate { id: u64, system: String, prompt: String, max_tokens: usize },
    Shutdown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum WorkerEvent {
    Ready,
    LoadError { message: String },
    Result { id: u64, text: String },
    Failed { id: u64, message: String },
}

pub fn write_frame(mut writer: impl Write, header: &impl Serialize, payload: &[u8]) -> std::io::Result<()> {
    let header = serde_json::to_vec(header).map_err(std::io::Error::other)?;
    writer.write_all(&(header.len() as u32).to_le_bytes())?;
    writer.write_all(&header)?;
    writer.write_all(&(payload.len() as u32).to_le_bytes())?;
    writer.write_all(payload)?;
    writer.flush()
}

pub fn read_frame(mut reader: impl Read) -> std::io::Result<(Vec<u8>, Vec<u8>)> {
    let mut len = [0u8; 4];
    reader.read_exact(&mut len)?;
    let header_len = u32::from_le_bytes(len) as usize;
    if header_len > 8 * 1024 * 1024 {
        return Err(std::io::Error::other("frame header is too large"));
    }
    let mut header = vec![0u8; header_len];
    reader.read_exact(&mut header)?;
    reader.read_exact(&mut len)?;
    let payload_len = u32::from_le_bytes(len) as usize;
    if payload_len > 64 * 1024 * 1024 {
        return Err(std::io::Error::other("frame payload is too large"));
    }
    let mut payload = vec![0u8; payload_len];
    if payload_len > 0 {
        reader.read_exact(&mut payload)?;
    }
    Ok((header, payload))
}

pub fn pcm_from_bytes(bytes: &[u8]) -> Vec<f32> {
    bytes
        .chunks_exact(4)
        .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
        .collect()
}

pub fn pcm_to_bytes(samples: &[f32]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(samples.len() * 4);
    for sample in samples {
        bytes.extend_from_slice(&sample.to_le_bytes());
    }
    bytes
}
