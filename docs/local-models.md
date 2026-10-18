# Local ASR and translation models

Settings → Local Models shows the engine's actual loaded model for each role. The chooser offers downloads for uninstalled models and Use for installed models. Selection is saved only after the engine confirms successful loading. Switching is disabled during recording and other model switches; a failed load restores the previous model where possible.

The catalog contains Qwen3-ASR 0.6B / 1.7B (8-bit MLX), Qwen3.5 0.8B / 2B / 4B (4-bit MLX), and Qwen3 0.6B / 4B (4-bit MLX). Qwen3 is offered for questions and summaries; translation keeps its independent Qwen3.5 selection. Repository IDs, pinned revisions and download sizes are in `Sources/LectureNoteApp/Models/LocalModelCatalog.swift`. File manifests and SHA-256 values come from Hugging Face at those revisions. No Python installation or Hugging Face login is needed for these public repositories.

Models remain in `~/.OminiX/models`, including the existing `qwen3-asr-1.7b` and `Qwen3.5-2B-MLX-4bit` directories. Existing complete installations are detected without network requests. Downloads use a staging directory under `.nomi-downloads`; completed files are reused after cancellation, failure or an app restart. The currently downloading file restarts. LFS file hashes and all file sizes are checked before the installation is published. An incomplete old installation is preserved in a backup directory if replaced.

ASR repositories can supply `vocab.json` + `merges.txt` instead of `tokenizer.json`; the existing ASR loader builds and caches that tokenizer. The engine readiness check now recognizes that layout and sharded safetensors for both roles.

The download workflow follows Moxin-Studio's local model manager (catalog, per-model progress, cancel and retry), implemented with native Swift URLSession downloads. The Rust engine exposes an authenticated `/v1/models/select` endpoint. It blocks simultaneous recording / switching, validates model architecture and files, unloads the selected role, and loads the new directory. Other model families require additional worker support.

The app repository includes its backend in `Backend/`. From the Nomi project directory, build the Swift app, Rust engine/workers and app bundle together:

```sh
bash scripts/build-app.sh
open build/Nomi.app
```

No sibling Moxin-Voice checkout or separately started backend is required. The app bundle includes `moxin-engine`, `asr-worker`, `llm-worker` and `mlx.metallib`; packaging fails if any are missing. Launching the app starts its own authenticated loopback engine, and quitting closes its lifetime pipe to terminate that engine and its workers. An unexpected engine exit clears readiness and triggers one restart attempt. A missing backend is an error rather than a silent switch to fixture playback. Startup logs are written to `~/Library/Logs/Nomi/engine.log`.

## Questions, summaries and API profiles

Settings → Questions & Summaries switches between local MLX inference and API profiles. This choice does not change ASR or translation. A local Qwen3.5 model can reuse the translation worker when both roles select the same directory; otherwise the assistant uses a separate worker loaded on demand. Local generation is serialized with model operations and blocked during recording.

The API presets match Moxin-Studio's text providers: OpenAI, Anthropic, Gemini, DeepSeek, Kimi, Groq, NVIDIA, Zhipu and Ollama, plus a custom base URL. OpenAI-compatible Chat Completions and native Anthropic Messages are supported. Users can fetch model IDs or type one manually. API model availability is determined by their provider/account. Changing sources, selecting profiles, saving or overwriting a profile, connecting to fetch models, and deleting profiles require confirmation in the UI.

API keys are stored only in macOS Keychain, scoped to the profile UUID and base URL. Non-secret settings use UserDefaults. Changing a remote address requires a new key; keys are never silently reused for a different address. Cross-origin HTTP redirects are blocked. No Studio keys or accounts are imported automatically.

The meeting detail sidebar and Ask page now call the selected model using the meeting's transcript, timestamps and the latest conversation turns. Local inputs above 16,384 tokens return a clear error rather than silently omitting transcript content. Answers and summaries are kept in memory for the current app session; meetings and categories are saved separately in `~/Library/Application Support/Nomi/meetings.json`. Timestamps are textual citations, not jump links. Native Responses-only models, image/audio APIs, GGUF, GLM and Mistral backends are outside this integration.

Installed models have a Delete action with confirmation. The engine unloads all roles sharing the directory before moving it to the macOS Trash. Switching/deleting is blocked during recording or local generation. The selection remains explicit; deleting a chosen model does not silently select another model.

API protocol references:

- https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create
- https://developers.openai.com/api/reference/resources/models/methods/list
- https://platform.claude.com/docs/en/api/messages/create
- https://platform.claude.com/docs/en/api/models/list
- https://ai.google.dev/gemini-api/docs/openai
- https://docs.ollama.com/api/openai-compatibility

Validation covers compilation, opening the packaged app from the renamed Nomi directory, and confirming that app exit closes all bundled backend processes and reopening starts them again. No automated test suite was run, as requested. Downloads, model switching/deletion, API credentials/requests, confirmation flows, and generated answers/summaries still need user testing. No paid requests or model deletions were performed by the agent.
