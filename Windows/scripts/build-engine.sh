#!/usr/bin/env bash
# Builds the engine and the two GGUF workers for development on a Mac, into
# Windows/app/src-tauri/engine (moxin-engine, asr/asr-worker, llm/llm-worker).
# The Windows build is build-engine.ps1. Needs cmake and, for bindgen, LIBCLANG_PATH.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/Windows/app/src-tauri/engine"
export LIBCLANG_PATH="${LIBCLANG_PATH:-$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib}"

# The engine has no MLX code; it builds into its own folder so the Mac app's build is untouched.
cargo build --release --manifest-path "$root/Backend/Cargo.toml" --target-dir "$root/Backend/target-windows-dev" -p moxin-engine
# The workers each build their own ggml, so each gets its own target folder.
cargo build --release --manifest-path "$root/Windows/engine/Cargo.toml" --target-dir "$root/Windows/engine/target-asr" -p asr-worker
cargo build --release --manifest-path "$root/Windows/engine/Cargo.toml" --target-dir "$root/Windows/engine/target-llm" -p llm-worker

mkdir -p "$out/asr" "$out/llm"
cp "$root/Backend/target-windows-dev/release/moxin-engine" "$out/"
cp "$root/Windows/engine/target-asr/release/asr-worker" "$out/asr/"
cp "$root/Windows/engine/target-llm/release/llm-worker" "$out/llm/"
echo "engine ready in $out"
