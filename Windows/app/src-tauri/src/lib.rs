//! Nomi for Windows: the Tauri core. The UI (a one-to-one port of the Mac app's SwiftUI and
//! models) runs the app; this side does what needs the PC: files, the engine, the microphone,
//! downloads, documents, pictures, playback and secrets.

mod audio;
mod device;
mod documents;
mod engine;
mod images;
mod models;
mod ocr;
mod paths;
mod platform;
mod playback;
mod recording;
mod speakers;

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tauri::Manager;

#[derive(Default)]
pub struct AppState {
    engine: Mutex<Option<engine::EngineProcess>>,
    engine_dir: Mutex<Option<PathBuf>>,
    recordings: Mutex<HashMap<String, recording::Recording>>,
    downloads: Arc<models::Downloads>,
    player: playback::Player,
    /// The window's frame before the compact meeting card: x, y, width, height.
    saved_frame: Mutex<Option<(f64, f64, f64, f64)>>,
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // One copy at a time: opening Nomi again brings the running window forward instead.
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| platform::show_main_window(app)))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_http::init())
        .manage(AppState::default())
        .setup(|app| {
            paths::migrate();
            let state = app.state::<AppState>();
            *state.engine_dir.lock().unwrap() = engine::engine_dir(app.path().resource_dir().ok());
            open_main_window(app)?;
            platform::install_tray(app)?;
            Ok(())
        })
        .on_window_event(|window, event| {
            if window.label() == "tray-menu" {
                // The tray menu closes when it loses focus, and is never destroyed by the user.
                match event {
                    tauri::WindowEvent::Focused(false) => {
                        let _ = window.hide();
                    }
                    tauri::WindowEvent::CloseRequested { api, .. } => {
                        api.prevent_close();
                        let _ = window.hide();
                    }
                    _ => {}
                }
            } else if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                platform::close_requested(window, api);
            } else if let tauri::WindowEvent::Destroyed = event {
                if window.label() == "main" {
                    let state = window.state::<AppState>();
                    state.recordings.lock().unwrap().clear();
                    drop(state.engine.lock().unwrap().take());
                    // The tray menu window would keep the app alive; the main window is the app.
                    window.app_handle().exit(0);
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            platform::platform_info,
            platform::prefs_load,
            platform::prefs_save,
            platform::fs_read_text,
            platform::fs_write_text,
            platform::fs_read_base64,
            platform::fs_write_base64,
            platform::fs_copy,
            platform::fs_move,
            platform::fs_remove,
            platform::fs_exists,
            platform::fs_list,
            platform::fs_mkdir,
            platform::fs_stat,
            platform::fs_temp_dir,
            platform::open_url,
            platform::open_path,
            platform::reveal_path,
            platform::secret_get,
            platform::secret_set,
            platform::secret_delete,
            platform::clipboard_copy_image,
            platform::window_set_compact,
            platform::app_version,
            platform::app_quit,
            platform::window_close_choice,
            platform::tray_show_main,
            platform::diagnostics,
            platform::microphone_access,
            platform::log_line,
            device::device_report,
            images::image_payload,
            images::image_normalize,
            images::image_thumbnail,
            documents::document_segments,
            documents::document_page_count,
            documents::ocr_available,
            engine::engine_launch,
            engine::engine_shutdown,
            recording::audio_inputs,
            recording::recording_open,
            recording::recording_gate,
            recording::recording_send,
            recording::recording_stop_mic,
            recording::recording_close,
            recording::speakers_finish,
            recording::voices_analyze,
            models::models_installed,
            models::model_download,
            models::model_cancel_download,
            models::model_delete,
            playback::moment_play,
            playback::moment_stop,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Nomi");
}

/// Opens the window. Like the Mac app it paints its own solid canvas; the Liquid Glass pieces (the
/// recording capsule, menus, the jump pill) blur what is under them inside the window.
fn open_main_window(app: &tauri::App) -> tauri::Result<()> {
    let builder = tauri::WebviewWindowBuilder::new(app, "main", tauri::WebviewUrl::default())
        .title("Nomi")
        .inner_size(1240.0, 820.0)
        .min_inner_size(960.0, 640.0)
        // On Windows Nomi draws its own title bar (logo, name and window buttons in the top bar);
        // the system keeps the shadow, rounded corners and resizing edges.
        .decorations(!cfg!(windows))
        .shadow(true)
        .center();
    builder.build()?;
    Ok(())
}

