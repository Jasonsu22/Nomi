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
# llama.cpp's Vulkan shader tool nests deep build folders; MSVC fails past 260 characters
# ("Cannot open compiler generated file"), so NOMI_TARGETS can put the builds at a short path.
$targets = if ($env:NOMI_TARGETS) { $env:NOMI_TARGETS } else { "$root\Windows\engine" }
$engineTarget = if ($env:NOMI_TARGETS) { "$env:NOMI_TARGETS\engine" } else { "$root\Backend\target-windows" }
$asrTarget = "$targets\target-asr"
$llmTarget = "$targets\target-llm"

cargo build --release --manifest-path "$root\Backend\Cargo.toml" --target-dir "$engineTarget" -p moxin-engine
if ($LASTEXITCODE) { throw "moxin-engine failed" }
cargo build --release --manifest-path "$root\Windows\engine\Cargo.toml" --target-dir "$asrTarget" -p asr-worker
if ($LASTEXITCODE) { throw "asr-worker failed" }
cargo build --release --manifest-path "$root\Windows\engine\Cargo.toml" --target-dir "$llmTarget" -p llm-worker
if ($LASTEXITCODE) { throw "llm-worker failed" }

New-Item -ItemType Directory -Force "$out\asr", "$out\llm" | Out-Null
Copy-Item "$engineTarget\release\moxin-engine.exe" "$out\" -Force
Copy-Item "$asrTarget\release\asr-worker.exe" "$out\asr\" -Force
Get-ChildItem "$asrTarget\release\build" -Recurse -Filter *.dll |
  Where-Object { $_.FullName -match 'transcribe-cpp-sys' } | Copy-Item -Destination "$out\asr\" -Force
Copy-Item "$llmTarget\release\llm-worker.exe" "$out\llm\" -Force
Get-ChildItem "$llmTarget\release" -Filter *.dll | Copy-Item -Destination "$out\llm\" -Force
Get-ChildItem "$llmTarget\release\build" -Recurse -Filter *.dll |
  Where-Object { $_.FullName -match 'llama-cpp-sys-2' } | Copy-Item -Destination "$out\llm\" -Force
Get-ChildItem -Recurse $out | Select-Object FullName, Length | Format-Table -AutoSize
