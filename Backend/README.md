# Nomi local backend

Standalone Rust workspace containing the HTTP/WebSocket engine, ASR and language-model workers, shared voice pipeline, and the patched Qwen3-ASR loader. Imported from the local Moxin-Voice integration at commit `2ab501d`; the source repository is preserved separately. Original licensing is retained in LICENSE and vendor/qwen3-asr-mlx/LICENSE-*.

Build together with the app using `bash scripts/build-app.sh` from the project root. For backend-only development, run `cargo build --locked -p moxin-engine -p asr-worker -p llm-worker` here. Dependencies are pinned by Cargo.lock and the OminiX-MLX Git revision in each manifest.

The app passes `--managed-by-app` and owns the write end of stdin. This mode puts the engine and its workers in a private process group. stdin EOF terminates that group, including when the app crashes. CLI/replay use without this flag is unchanged.
