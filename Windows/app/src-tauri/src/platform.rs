//! The PC side of the UI's `platform` module: files, settings (prefs.json), secrets (Windows
//! Credential Manager), opening and revealing, the clipboard, the window, and system facts.

use base64::Engine as _;
use serde::Serialize;
use std::path::{Path, PathBuf};
use tauri::{AppHandle, Manager};

pub type Result<T> = std::result::Result<T, String>;
pub fn text<E: std::fmt::Display>(error: E) -> String {
    error.to_string()
}

#[derive(Serialize)]
pub struct PlatformInfo {
    root: String,
    sep: String,
    os: String,
}

#[tauri::command]
pub fn platform_info() -> PlatformInfo {
    let root = crate::paths::root();
    let _ = std::fs::create_dir_all(&root);
    PlatformInfo {
        root: root.display().to_string(),
        sep: std::path::MAIN_SEPARATOR.to_string(),
        os: if cfg!(windows) { "windows".into() } else if cfg!(target_os = "macos") { "macos".into() } else { "linux".into() },
    }
}

// MARK: Settings

fn prefs_file() -> PathBuf {
    crate::paths::root().join("prefs.json")
}

#[tauri::command]
pub fn prefs_load() -> serde_json::Value {
    std::fs::read(prefs_file())
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_else(|| serde_json::json!({}))
}

#[tauri::command]
pub fn prefs_save(values: serde_json::Value) -> Result<()> {
    write_atomic(&prefs_file(), serde_json::to_vec_pretty(&values).map_err(text)?.as_slice())
}

/// Writes through a temporary file and a rename, so a crash never leaves half a file.
pub fn write_atomic(path: &Path, bytes: &[u8]) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(text)?;
    }
    let temp = path.with_extension(format!("{}.tmp", std::process::id()));
    std::fs::write(&temp, bytes).map_err(text)?;
    std::fs::rename(&temp, path).map_err(|e| {
        let _ = std::fs::remove_file(&temp);
        text(e)
    })
}

// MARK: Files

#[tauri::command]
pub fn fs_read_text(path: String) -> Result<Option<String>> {
    match std::fs::read(&path) {
        Ok(bytes) => Ok(Some(String::from_utf8_lossy(&bytes).into_owned())),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(text(e)),
    }
}

#[tauri::command]
pub fn fs_write_text(path: String, text: String) -> Result<()> {
    write_atomic(Path::new(&path), text.as_bytes())
}

#[tauri::command]
pub fn fs_read_base64(path: String) -> Result<String> {
    let bytes = std::fs::read(&path).map_err(text)?;
    Ok(base64::engine::general_purpose::STANDARD.encode(bytes))
}

#[tauri::command]
pub fn fs_write_base64(path: String, data: String) -> Result<()> {
    let bytes = base64::engine::general_purpose::STANDARD.decode(data.trim()).map_err(text)?;
    write_atomic(Path::new(&path), &bytes)
}

fn copy_tree(from: &Path, to: &Path) -> std::io::Result<()> {
    if from.is_dir() {
        std::fs::create_dir_all(to)?;
        for entry in std::fs::read_dir(from)? {
            let entry = entry?;
            copy_tree(&entry.path(), &to.join(entry.file_name()))?;
        }
        Ok(())
    } else {
        if let Some(parent) = to.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::copy(from, to).map(|_| ())
    }
}

#[tauri::command]
pub fn fs_copy(from: String, to: String) -> Result<()> {
    let (from, to) = (PathBuf::from(from), PathBuf::from(to));
    if from == to {
        return Ok(());
    }
    if to.is_file() {
        std::fs::remove_file(&to).map_err(text)?;
    }
    copy_tree(&from, &to).map_err(text)
}

#[tauri::command]
pub fn fs_move(from: String, to: String) -> Result<()> {
    let (from, to) = (PathBuf::from(from), PathBuf::from(to));
    if from == to {
        return Ok(());
    }
    if let Some(parent) = to.parent() {
        std::fs::create_dir_all(parent).map_err(text)?;
    }
    if to.is_file() {
        std::fs::remove_file(&to).map_err(text)?;
    }
    // A rename fails across drives; copy and delete then.
    if std::fs::rename(&from, &to).is_err() {
        copy_tree(&from, &to).map_err(text)?;
        remove(&from).map_err(text)?;
    }
    Ok(())
}

fn remove(path: &Path) -> std::io::Result<()> {
    if path.is_dir() {
        std::fs::remove_dir_all(path)
    } else {
        match std::fs::remove_file(path) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            other => other,
        }
    }
}

#[tauri::command]
pub fn fs_remove(path: String) -> Result<()> {
    remove(Path::new(&path)).map_err(text)
}

#[tauri::command]
pub fn fs_exists(path: String) -> bool {
    Path::new(&path).exists()
}

#[tauri::command]
pub fn fs_list(path: String) -> Vec<String> {
    std::fs::read_dir(&path)
        .map(|entries| entries.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect())
        .unwrap_or_default()
}

#[tauri::command]
pub fn fs_mkdir(path: String) -> Result<()> {
    std::fs::create_dir_all(&path).map_err(text)
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FileStat {
    size: u64,
    /// Seconds since 1970.
    modified: f64,
    is_dir: bool,
}

#[tauri::command]
pub fn fs_stat(path: String) -> Option<FileStat> {
    let meta = std::fs::metadata(&path).ok()?;
    let modified = meta.modified().ok().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_secs_f64()).unwrap_or(0.0);
    Some(FileStat { size: meta.len(), modified, is_dir: meta.is_dir() })
}

#[tauri::command]
pub fn fs_temp_dir() -> String {
    std::env::temp_dir().display().to_string()
}

// MARK: Opening

#[tauri::command]
pub fn open_url(url: String) -> Result<()> {
    let lower = url.to_ascii_lowercase();
    let allowed = ["http://", "https://", "mailto:", "ms-settings:"].iter().any(|p| lower.starts_with(p));
    if !allowed {
        return Err("unsupported link".into());
    }
    open::that_detached(&url).map_err(text)
}

#[tauri::command]
pub fn open_path(path: String) -> Result<()> {
    let p = Path::new(&path);
    if p.is_dir() || !p.exists() {
        std::fs::create_dir_all(p).map_err(text)?;
    }
    open::that_detached(&path).map_err(text)
}

#[tauri::command]
pub fn reveal_path(path: String) -> Result<()> {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        std::process::Command::new("explorer").raw_arg(format!("/select,\"{path}\"")).spawn().map_err(text)?;
    }
    #[cfg(target_os = "macos")]
    std::process::Command::new("open").arg("-R").arg(&path).spawn().map_err(text)?;
    #[cfg(all(not(windows), not(target_os = "macos")))]
    open::that_detached(Path::new(&path).parent().unwrap_or(Path::new("."))).map_err(text)?;
    Ok(())
}

// MARK: Secrets

fn entry(service: &str, account: &str) -> Result<keyring::Entry> {
    keyring::Entry::new(service, account).map_err(text)
}

#[tauri::command]
pub fn secret_get(service: String, account: String) -> Result<Option<String>> {
    match entry(&service, &account)?.get_password() {
        Ok(value) => Ok(Some(value)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(text(e)),
    }
}

#[tauri::command]
pub fn secret_set(service: String, account: String, secret: String) -> Result<()> {
    entry(&service, &account)?.set_password(&secret).map_err(text)
}

#[tauri::command]
pub fn secret_delete(service: String, account: String) -> Result<()> {
    match entry(&service, &account)?.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(text(e)),
    }
}

// MARK: Clipboard

#[tauri::command]
pub fn clipboard_copy_image(path: String) -> Result<()> {
    let picture = image::open(&path).map_err(text)?.to_rgba8();
    let (width, height) = picture.dimensions();
    let data = arboard::ImageData { width: width as usize, height: height as usize, bytes: std::borrow::Cow::Owned(picture.into_raw()) };
    arboard::Clipboard::new().and_then(|mut c| c.set_image(data)).map_err(text)
}

// MARK: Window and app

/// The compact meeting card (MeetingWindowFrame.swift): 420×740 and back to the saved frame.
#[tauri::command]
pub fn window_set_compact(app: AppHandle, compact: bool, state: tauri::State<'_, crate::AppState>) -> Result<()> {
    let window = app.get_webview_window("main").ok_or("no window")?;
    let mut saved = state.saved_frame.lock().unwrap();
    if compact {
        if saved.is_some() {
            return Ok(());
        }
        let scale = window.scale_factor().map_err(text)?;
        let position = window.outer_position().map_err(text)?.to_logical::<f64>(scale);
        let size = window.inner_size().map_err(text)?.to_logical::<f64>(scale);
        *saved = Some((position.x, position.y, size.width, size.height));
        let maximized = window.is_maximized().unwrap_or(false);
        if maximized {
            let _ = window.unmaximize();
        }
        window.set_min_size(Some(tauri::LogicalSize::new(360.0, 560.0))).map_err(text)?;
        let x = position.x + (size.width - 420.0) / 2.0;
        window.set_size(tauri::LogicalSize::new(420.0, 740.0)).map_err(text)?;
        window.set_position(tauri::LogicalPosition::new(x.max(0.0), position.y)).map_err(text)?;
    } else if let Some((x, y, w, h)) = saved.take() {
        window.set_size(tauri::LogicalSize::new(w, h)).map_err(text)?;
        window.set_position(tauri::LogicalPosition::new(x, y)).map_err(text)?;
        window.set_min_size(Some(tauri::LogicalSize::new(960.0, 640.0))).map_err(text)?;
    }
    Ok(())
}

#[tauri::command]
pub fn app_version(app: AppHandle) -> String {
    app.package_info().version.to_string()
}

/// Quits by closing the window for good, so the window's clean-up (the engine, open
/// recordings) runs; the app ends with its last window.
#[tauri::command]
pub fn app_quit(app: AppHandle) {
    match app.get_webview_window("main") {
        Some(window) => {
            let _ = window.destroy();
        }
        None => app.exit(0),
    }
}

/// What the close button does, from Settings: "minimize", "quit", or (not chosen yet) ask.
pub const CLOSE_ACTION_KEY: &str = "nomi.closeAction";

/// The close button (or Alt+F4): minimizes or quits as chosen; the first time, the window asks.
pub fn close_requested(window: &tauri::Window, api: &tauri::CloseRequestApi) {
    if window.label() != "main" {
        return;
    }
    let choice = prefs_load().get(CLOSE_ACTION_KEY).and_then(|v| v.as_str()).map(str::to_string);
    match choice.as_deref() {
        Some("quit") => {}
        Some("minimize") => {
            api.prevent_close();
            let _ = window.minimize();
        }
        _ => {
            api.prevent_close();
            let _ = tauri::Emitter::emit(window, "nomi://close-asked", ());
        }
    }
}

/// The answer to the first-close question (already saved in prefs by the window).
#[tauri::command]
pub fn window_close_choice(app: AppHandle, choice: String) -> Result<()> {
    let window = app.get_webview_window("main").ok_or("no window")?;
    if choice == "quit" {
        window.destroy().map_err(text)
    } else {
        window.minimize().map_err(text)
    }
}

/// Brings the window back: from the taskbar, from behind other windows, or when Nomi is
/// opened a second time.
pub fn show_main_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

/// One line for a bug report: the system and the processor.
#[tauri::command]
pub fn diagnostics() -> String {
    let mut system = sysinfo::System::new();
    system.refresh_memory();
    system.refresh_cpu_all();
    let cpu = system.cpus().first().map(|c| c.brand().trim().to_string()).unwrap_or_default();
    format!(
        "{} {} · {} · {:.0} GB",
        sysinfo::System::name().unwrap_or_default(),
        sysinfo::System::os_version().unwrap_or_default(),
        cpu,
        system.total_memory() as f64 / 1_073_741_824.0
    )
}

/// Windows › Privacy › Microphone: whether desktop apps may use it. granted, denied or unknown.
#[tauri::command]
pub fn microphone_access() -> String {
    #[cfg(windows)]
    {
        use windows::core::w;
        use windows::Win32::System::Registry::{RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_SZ};
        let mut buffer = [0u16; 32];
        let mut size = (buffer.len() * 2) as u32;
        let status = unsafe {
            RegGetValueW(
                HKEY_CURRENT_USER,
                w!("Software\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\microphone"),
                w!("Value"),
                RRF_RT_REG_SZ,
                None,
                Some(buffer.as_mut_ptr() as *mut _),
                Some(&mut size),
            )
        };
        if status.is_err() {
            return if crate::audio::input_devices().is_empty() { "unknown".into() } else { "granted".into() };
        }
        let len = buffer.iter().position(|c| *c == 0).unwrap_or(buffer.len());
        let value = String::from_utf16_lossy(&buffer[..len]);
        return if value.eq_ignore_ascii_case("Deny") { "denied".into() } else { "granted".into() };
    }
    #[allow(unreachable_code)]
    if crate::audio::input_devices().is_empty() { "unknown".into() } else { "granted".into() }
}

/// The UI's warnings and errors, kept in ui.log beside engine.log for bug reports.
#[tauri::command]
pub fn log_line(level: String, message: String) {
    use std::io::Write;
    let path = crate::paths::root().join("ui.log");
    if std::fs::metadata(&path).is_ok_and(|m| m.len() > 2_000_000) {
        let _ = std::fs::remove_file(&path);
    }
    if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
        let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        let _ = writeln!(file, "{now} {level}: {message}");
    }
}
