# Local ASR and translation models

Settings → Local Models shows the engine's actual loaded model for each role. The chooser offers downloads for uninstalled models and Use for installed models. Selection is saved only after the engine confirms successful loading. Switching is disabled during recording and other model switches; a failed load restores the previous model where possible.

The first catalog contains Qwen3-ASR 0.6B / 1.7B (8-bit MLX) and Qwen3.5 0.8B / 2B / 4B (4-bit MLX). Repository IDs, pinned revisions and download sizes are in `Sources/LectureNoteApp/Models/LocalModelCatalog.swift`. File manifests and SHA-256 values come from Hugging Face at those revisions. No Python installation or Hugging Face login is needed for these public repositories.

Models remain in `~/.OminiX/models`, including the existing `qwen3-asr-1.7b` and `Qwen3.5-2B-MLX-4bit` directories. Existing complete installations are detected without network requests. Downloads use a staging directory under `.nomi-downloads`; completed files are reused after cancellation, failure or an app restart. The currently downloading file restarts. LFS file hashes and all file sizes are checked before the installation is published. An incomplete old installation is preserved in a backup directory if replaced.

ASR repositories can supply `vocab.json` + `merges.txt` instead of `tokenizer.json`; the existing ASR loader builds and caches that tokenizer. The engine readiness check now recognizes that layout and sharded safetensors for both roles.

The download workflow follows Moxin-Studio's local model manager (catalog, per-model progress, cancel and retry), implemented with native Swift URLSession downloads. The Rust engine exposes an authenticated `/v1/models/select` endpoint. It blocks simultaneous recording / switching, validates model architecture and files, unloads the selected role, and loads the new directory. Other model families require additional worker support.

Build the updated Rust binaries in `../Moxin-Voice` before packaging the app:

```sh
cargo build -p moxin-engine -p asr-worker -p llm-worker
```

Then, from this app directory:

```sh
swift build
bash scripts/build-app.sh
```

Validation for this change is compilation and opening the packaged app only, as requested. Downloads, cancellation, switching and live recognition / translation still need user testing.
