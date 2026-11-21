# Builds the engine and the two GGUF workers for Windows x64 (CPU + Vulkan), into
# Windows\app\src-tauri\engine, which the installer bundles:
#   moxin-engine.exe
#   asr\asr-worker.exe + transcribe.cpp's ggml DLLs
#   llm\llm-worker.exe + llama.cpp's ggml DLLs
# The two workers' DLLs share names, so they live in separate folders.
# Needs: Rust (MSVC), CMake, LLVM (LIBCLANG_PATH), the Vulkan SDK.
$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\..\.."
$out = "$root\Windows\app\src-tauri\engine"
if (-not $env:LIBCLANG_PATH) { $env:LIBCLANG_PATH = "C:\Program Files\LLVM\bin" }

cargo build --release --manifest-path "$root\Backend\Cargo.toml" --target-dir "$root\Backend\target-windows" -p moxin-engine
if ($LASTEXITCODE) { throw "moxin-engine failed" }
cargo build --release --manifest-path "$root\Windows\engine\Cargo.toml" --target-dir "$root\Windows\engine\target-asr" -p asr-worker
if ($LASTEXITCODE) { throw "asr-worker failed" }
cargo build --release --manifest-path "$root\Windows\engine\Cargo.toml" --target-dir "$root\Windows\engine\target-llm" -p llm-worker
if ($LASTEXITCODE) { throw "llm-worker failed" }

New-Item -ItemType Directory -Force "$out\asr", "$out\llm" | Out-Null
Copy-Item "$root\Backend\target-windows\release\moxin-engine.exe" "$out\" -Force
Copy-Item "$root\Windows\engine\target-asr\release\asr-worker.exe" "$out\asr\" -Force
Get-ChildItem "$root\Windows\engine\target-asr\release\build" -Recurse -Filter *.dll |
  Where-Object { $_.FullName -match 'transcribe-cpp-sys' } | Copy-Item -Destination "$out\asr\" -Force
Copy-Item "$root\Windows\engine\target-llm\release\llm-worker.exe" "$out\llm\" -Force
Get-ChildItem "$root\Windows\engine\target-llm\release" -Filter *.dll | Copy-Item -Destination "$out\llm\" -Force
Get-ChildItem "$root\Windows\engine\target-llm\release\build" -Recurse -Filter *.dll |
  Where-Object { $_.FullName -match 'llama-cpp-sys-2' } | Copy-Item -Destination "$out\llm\" -Force
Get-ChildItem -Recurse $out | Select-Object FullName, Length | Format-Table -AutoSize
