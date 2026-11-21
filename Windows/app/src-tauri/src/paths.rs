//! Where Nomi keeps its files. Windows: %LOCALAPPDATA%\Nomi. On a Mac this app is only built for
//! development, so it uses its own folder and never touches the Mac app's data.

use std::path::PathBuf;

pub fn root() -> PathBuf {
    if let Ok(dir) = std::env::var("NOMI_DATA_DIR") {
        return PathBuf::from(dir);
    }
    if cfg!(windows) {
        dirs::data_local_dir().unwrap_or_else(|| PathBuf::from(".")).join("Nomi")
    } else {
        dirs::data_dir().unwrap_or_else(|| PathBuf::from(".")).join("Nomi-Windows-dev")
    }
}

pub fn models() -> PathBuf {
    std::env::var("NOMI_MODELS_DIR").map(PathBuf::from).unwrap_or_else(|_| root().join("models"))
}

pub fn engine_log() -> PathBuf {
    root().join("engine.log")
}
