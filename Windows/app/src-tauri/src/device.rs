//! What this PC has, and which model set to suggest. The rule follows docs/windows-plan.md §5.3 and
//! the Phase 0 findings: a strong CPU alone keeps up with the 0.6B speech model and the 2B
//! translator, the 1.7B speech model wants a GPU, and 8 GB machines get the Lite set.

use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Gpu {
    pub index: usize,
    pub name: String,
    pub description: String,
    pub backend: String,
    /// gpu (discrete) or igpu (integrated).
    pub kind: String,
    #[serde(alias = "memory_total_mb")]
    pub memory_total_mb: u64,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceReport {
    pub cpu: String,
    pub cores: usize,
    pub threads: usize,
    pub memory_gb: f64,
    pub gpus: Vec<Gpu>,
    pub os: String,
    pub suggested_set: String,
    pub reason: String,
}

pub fn read(engine_dir: Option<&std::path::Path>) -> DeviceReport {
    let engine_dir = engine_dir.map(|d| d.to_path_buf());
    let engine_dir = engine_dir.as_deref();
    let mut system = sysinfo::System::new();
    system.refresh_memory();
    system.refresh_cpu_all();
    let cpu = system.cpus().first().map(|c| c.brand().trim().to_string()).unwrap_or_default();
    let threads = system.cpus().len();
    let cores = system.physical_core_count().unwrap_or(threads);
    let memory_gb = system.total_memory() as f64 / 1_073_741_824.0;
    let gpus = engine_dir.map(list_gpus).unwrap_or_default();
    let os = format!("{} {}", sysinfo::System::name().unwrap_or_default(), sysinfo::System::os_version().unwrap_or_default());
    let (suggested_set, reason) = suggest(cores, memory_gb, &gpus);
    DeviceReport { cpu, cores, threads, memory_gb, gpus, os, suggested_set, reason }
}

pub fn suggest(cores: usize, memory_gb: f64, gpus: &[Gpu]) -> (String, String) {
    let discrete = gpus.iter().find(|g| g.kind == "gpu" && g.memory_total_mb >= 6_000);
    if let Some(gpu) = discrete {
        if memory_gb >= 15.0 {
            return ("Full".into(), format!("gpu:{}", gpu.name));
        }
    }
    if memory_gb >= 15.0 && cores >= 6 {
        return ("Standard".into(), "cpu".into());
    }
    if memory_gb >= 15.0 && gpus.iter().any(|g| g.kind == "igpu") {
        return ("Standard".into(), "igpu".into());
    }
    ("Lite".into(), "small".into())
}

/// The speech worker lists what transcribe.cpp can run on (CPU, Vulkan or Metal devices).
fn list_gpus(engine_dir: &std::path::Path) -> Vec<Gpu> {
    let worker = crate::engine::exe(engine_dir, "asr", "asr-worker");
    let mut command = std::process::Command::new(worker);
    command.arg("devices");
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
    let Ok(output) = command.output() else { return Vec::new() };
    let devices: Vec<Gpu> = serde_json::from_slice(&output.stdout).unwrap_or_default();
    devices
        .into_iter()
        .filter(|d| d.kind == "gpu" || d.kind == "igpu")
        // Apple's GPU shares the system's memory, like an integrated one.
        .map(|d| if d.backend.eq_ignore_ascii_case("metal") { Gpu { kind: "igpu".into(), ..d } } else { d })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn gpu(kind: &str, mb: u64) -> Gpu {
        Gpu { index: 0, name: "G".into(), description: "G".into(), backend: "Vulkan".into(), kind: kind.into(), memory_total_mb: mb }
    }

    #[test]
    fn sets_follow_the_hardware() {
        assert_eq!(suggest(8, 32.0, &[gpu("gpu", 8_000)]).0, "Full");
        assert_eq!(suggest(8, 16.0, &[]).0, "Standard");
        assert_eq!(suggest(4, 16.0, &[gpu("igpu", 0)]).0, "Standard");
        assert_eq!(suggest(4, 8.0, &[]).0, "Lite");
        assert_eq!(suggest(8, 8.0, &[gpu("gpu", 8_000)]).0, "Lite");
    }
}

#[tauri::command]
pub async fn device_report(state: tauri::State<'_, crate::AppState>) -> Result<DeviceReport, String> {
    let dir = state.engine_dir.lock().unwrap().clone();
    tokio::task::spawn_blocking(move || read(dir.as_deref())).await.map_err(|e| e.to_string())
}
