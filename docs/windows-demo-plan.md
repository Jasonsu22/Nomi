# Nomi for Windows: demo build plan

> Written 2026-11-21. This is the build plan for the first runnable Windows app (the demo).
> The full product plan is `docs/windows-plan.md`; this file covers what the demo contains and how it is built.

## 1. What the demo does

A Windows app that records a lecture and shows the live transcript and translation, running fully on the PC.

1. **Set-up screen:** reads the PC (CPU, cores, memory, GPUs), suggests a model set (Lite, Standard or Full), and downloads the two models with progress. Downloads try huggingface.co first, then hf-mirror.com for mainland China.
2. **Live page:** title, spoken language, translation language and input (a microphone, or an audio file played as if live, for testing). Start and Stop. Finished lines appear with their translation, and the line being spoken appears in grey. A level meter shows the input, and dot loaders show while models load.
3. **Meetings:** each recording is saved with its transcript and audio. You can open a past meeting, read it, play the audio, and rename or delete it.
4. **Settings:** model choice per role, where each model runs (CPU or GPU), threads, interim text (every pass, skip when busy, or off), and the models folder.

Not in the demo: chat, sources, Q&A, summaries, updater, installer signing, system-audio capture. These follow in Phases 3–4 of the main plan.

## 2. How it fits together

```
React UI (WebView2)                        Windows/app/src
   │  Tauri commands + events
Tauri core (Rust)                          Windows/app/src-tauri
   ├─ engine.rs   starts moxin-engine, reads {port, token}, health checks
   ├─ session.rs  WebSocket to /v1/session; sends 16 kHz PCM, forwards events
   ├─ audio.rs    microphone (cpal) or a file (symphonia), resampled to 16 kHz mono
   ├─ store.rs    meetings.json in the Mac's schema, audio-1.wav per meeting
   ├─ models.rs   model catalogue, download with resume and fallback source
   └─ device.rs   memory and CPU (sysinfo) + GPU list from the speech worker
moxin-engine(.exe)                         Backend/moxin-engine (shared with the Mac)
   ├─ asr/asr-worker(.exe)  + ggml DLLs    Windows/engine/asr-worker (transcribe-cpp)
   └─ llm/llm-worker(.exe)  + ggml DLLs    Windows/engine/llm-worker (llama-cpp-2)
```

- The engine is the Mac's engine. The Tauri core speaks the same HTTP and WebSocket protocol the Swift app speaks.
- The two GGUF workers speak the same frame protocol as the Mac's MLX workers (`voice-core/src/protocol.rs`). They live in their own folders because transcribe.cpp and llama.cpp each ship ggml DLLs with the same names.
- The app tells the engine where the workers are with `ASR_WORKER_BIN` and `LLM_WORKER_BIN`, which the engine already reads, and passes device and thread choices through environment variables the workers read. No new engine flags are needed for that.

## 3. Front-end stack

| Part | Choice | Notes |
|---|---|---|
| Shell | Tauri 2 | WebView2 on Windows; the same code runs on macOS for development. |
| UI library | React 19 + TypeScript (strict) | |
| Build | Vite 6 | Hot reload during development. |
| Styling | Tailwind CSS 4 (`@tailwindcss/vite`) | Colors, spacing and radii come from Nomi's design tokens as CSS variables, with light and dark sets. |
| State | Zustand | One store per area: app, live session, meetings, settings. Rust events update the stores. |
| Rust ↔ UI types | Hand-written `src/lib/api.ts` for the demo | Moves to tauri-specta when the command list settles (main plan, section 4). |
| Icons | lucide-react | Line icons similar to SF Symbols. |
| Loaders | Canvas `DotLoader` | Reads the same timing as `DotLoader.swift` (hop, gather, infinity, circle, breeze). |
| Fonts | Segoe UI Variable, Microsoft YaHei UI for Chinese | System fonts, nothing bundled. |
| Strings | Chinese and English in `src/i18n.ts` | Generated from `Localizable.strings` later. |

Look: Nomi's colors and spacing (`DesignSystem/Colors.swift`, `Spacing.swift`), left rail with the leaf mark, cards with 16 px corners, and Windows conventions for the title bar.

## 4. Engine changes (`Backend/moxin-engine`, small and Mac-safe)

1. Builds on Windows: Unix calls behind `cfg(unix)`; on Windows the app-lifetime watch exits on stdin EOF, and the token comes from the system's random source rather than `/dev/urandom`.
2. Accepts a `.gguf` file as a model path (today it expects an MLX folder).
3. Interim passes can skip when the engine falls behind (`NOMI_INTERIM=all|skip-busy|off`). The default stays `all`, so the Mac app behaves exactly as before; the Windows app sets `skip-busy` (Phase 0 findings).
4. The home folder falls back to `USERPROFILE` on Windows.

The Mac build (`scripts/build-app.sh`) builds the same packages with the same features and is unchanged.

## 5. Milestones

| # | Milestone | Done when |
|---|---|---|
| 1 | Engine changes and GGUF workers | `moxin-engine replay-wav` with the GGUF workers turns a lecture clip into a translated transcript on the Mac |
| 2 | Tauri app skeleton | The app opens with the rail, pages, tokens, light and dark |
| 3 | Engine in the app | The app starts the engine, shows model status, and stops it on quit |
| 4 | Live page | A file played as live shows commits and translations; the microphone works |
| 5 | Meetings | A recording is saved, listed, reopened and played back |
| 6 | Set-up and settings | Device reading, model set suggestion, downloads with progress, model and device choice |
| 7 | Windows build in CI | GitHub Actions builds the app with the engine and workers bundled, as an NSIS installer (unsigned) |
| 8 | Test on real PCs | Over SSH on the user's Windows PC: install, record, check speed on CPU and GPU |

## 6. Folder layout

```
Windows/
├─ app/                 Tauri app
│  ├─ src/              React UI (pages, components, stores, lib)
│  ├─ src-tauri/        Rust core
│  └─ package.json
├─ engine/              GGUF workers (own Cargo workspace)
│  ├─ asr-worker/
│  └─ llm-worker/
├─ scripts/             build-engine.sh (Mac dev), build-engine.ps1 (Windows)
└─ phase0/              measurement kit (unchanged)
```

When the branch is merged, the workers can move under `Backend/workers/` as the main plan describes.

## 7. Decisions taken for the demo

Taken from my suggestions in `docs/windows-plan.md` section 13, since the build runs without stopping:

- Tauri 2 + React + TypeScript; Vulkan as the GPU path; unsigned beta installer.
- Recording saved as WAV in the demo; AAC through Media Foundation comes with Phase 2's polish.
- Windows versions start at 0.1 and are published only as pre-releases, never marked Latest.
