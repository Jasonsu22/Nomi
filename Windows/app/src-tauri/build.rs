fn main() {
    // ONNX Runtime (sherpa-rs, static) needs advapi32 for event tracing and the registry.
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        println!("cargo:rustc-link-lib=advapi32");
    }
    tauri_build::build()
}
