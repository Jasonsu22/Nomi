//! Where Nomi keeps its files. Windows: %LOCALAPPDATA%\software.nomi.windows, apart from the
//! program itself (%LOCALAPPDATA%\Nomi), so updating or uninstalling never touches recordings or
//! models; the uninstaller's "delete app data" option removes exactly this folder. On a Mac this
//! app is only built for development, so it uses its own folder and never touches the Mac app's.

use std::path::PathBuf;

pub fn root() -> PathBuf {
    if let Ok(dir) = std::env::var("NOMI_DATA_DIR") {
        return PathBuf::from(dir);
    }
    if cfg!(windows) {
        dirs::data_local_dir().unwrap_or_else(|| PathBuf::from(".")).join("software.nomi.windows")
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

/// Test builds kept data beside the program in %LOCALAPPDATA%\Nomi; move it to the data folder.
pub fn migrate() {
    if !cfg!(windows) || std::env::var("NOMI_DATA_DIR").is_ok() {
        return;
    }
    let Some(old) = dirs::data_local_dir().map(|d| d.join("Nomi")) else { return };
    let new = root();
    let program = ["engine", "nomi.exe", "uninstall.exe", "resources"];
    let Ok(entries) = std::fs::read_dir(&old) else { return };
    let _ = std::fs::create_dir_all(&new);
    for entry in entries.flatten() {
        let name = entry.file_name();
        if program.iter().any(|p| name.eq_ignore_ascii_case(p)) {
            continue;
        }
        let target = new.join(&name);
        if !target.exists() {
            let _ = std::fs::rename(entry.path(), target);
        }
    }
}
