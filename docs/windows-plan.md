# Nomi for Windows: plan

> Written 2026-11-20. Nothing is built yet. Section 13 lists the decisions that are yours.
> Facts marked **(verify)** come from one web source or from my own estimate and must be checked in Phase 0 before we rely on them.

## 1. Summary

- **One repo.** The Windows app lives in a new `Windows/` folder in this repo. The Rust engine in `Backend/` is shared and built for both systems.
- **Any Windows PC, with or without a graphics card.** Nomi measures the device on first run and picks one of three model sets (Lite, Standard, Full). A PC that can only run small models gets small models; nothing is refused for lacking a GPU.
- **Same engine, new model runtime.** The engine (`moxin-engine`) and its worker protocol stay as they are. Only the two workers change: MLX is Apple-only, so on Windows they run GGUF models through two ggml-based libraries, which use the GPU through Vulkan when there is one and the CPU when there is not.
- **New app shell.** SwiftUI does not run on Windows. The Windows app is a Tauri 2 app: a Rust core plus a web UI. The answer page (`AnswerWeb/`) is already web code and is reused as is.
- **First step is a measurement, not UI.** Phase 0 runs both models on real Windows machines and confirms the runtime choice before any screen is built.

## 2. What exists today, and what carries over

| Part | Today (Mac) | Size | On Windows |
|---|---|---|---|
| Engine `moxin-engine` | Rust, axum HTTP + WebSocket on localhost | 1,600 lines | Reused. A few Unix calls are replaced (section 6.3). |
| `voice-core` | Rust: VAD, phrase cutting, repeat cleanup, worker frames | 1,100 lines | Reused unchanged. |
| `asr-worker` | Rust + `qwen3-asr-mlx` (MLX) | 107 lines | Rewritten on `transcribe-cpp`. Same frames in and out. |
| `llm-worker` | Rust + `qwen3-5-35b-mlx` (MLX) | 321 lines | Rewritten on `llama-cpp-2`. Same frames in and out. |
| Answer page | `answer.html`, `answer.js`, `answer.css`, KaTeX, markdown-it | web | Reused unchanged, moved to a shared folder. |
| App logic | Swift: `Models/` 6,800, `App/` 3,500, `Engine/` 2,700 lines | 13,000 | Ported to a Rust crate, `nomi-core`. The 236 Swift tests are ported with it and act as the specification. |
| Screens | SwiftUI: `Pages/`, `Meetings/`, `Shell/`, `DesignSystem/` | 12,500 | Rebuilt in React. |
| Saved data | `meetings.json`, chats, sources (JSON) | – | Same schema, so a folder can move between Mac and Windows. |

The engine design helps a great deal here: the app talks to the engine over HTTP and WebSocket, and the engine talks to each worker over length-prefixed frames on stdin and stdout (`voice-core/src/protocol.rs`). The MLX dependency is confined to the two small worker programs.

## 3. Goals and limits

**Goals for 1.0**
- Feature parity with Mac 0.9.1: live transcription and translation, meetings, sources, chat with citations, Q&A, summaries, settings, onboarding, updates.
- Runs on Windows 10 22H2 and Windows 11, x64.
- Works with no GPU, an integrated GPU (Intel, AMD), or a discrete GPU (NVIDIA, AMD, Intel Arc).
- Recordings never leave the PC, as on Mac.

**Not in 1.0**
- Windows on ARM (Snapdragon). Planned as a CPU-only build after 1.0 (section 5.6).
- NPU acceleration. The llama.cpp OpenVINO backend that would reach Intel NPUs is still described as work in progress.
- Syncing data between a Mac and a PC. The file format is shared, but there is no sync.

**Minimum PC (target, to confirm in Phase 0)**
- 64-bit CPU with AVX2 (Intel 4th gen / AMD Ryzen or newer), 4 cores.
- 8 GB of memory, 3 GB of free disk for the Lite set.

## 4. Tech stack

| Layer | Choice | Why |
|---|---|---|
| App shell | **Tauri 2** (Rust + WebView2) | Rust like the engine; small installer; proven by Handy, an offline speech app with 39k stars built the same way. |
| UI | **React 19 + TypeScript + Vite** | Largest ecosystem; Handy uses the same. |
| Styling | **Tailwind CSS 4** + CSS variables from Nomi's design tokens | One token file drives light and dark. |
| UI state | **Zustand** | Small; fits event-driven updates from Rust. |
| Rust ↔ UI types | **tauri-specta** | Generates TypeScript types from Rust commands, so the two sides cannot drift. |
| App logic | New crate **`nomi-core`** (Rust) | Testable with `cargo test`; no UI inside. |
| Speech models | **`transcribe-cpp` 0.4.2** (transcribe.cpp, ggml, MIT) | Runs Qwen3-ASR 0.6B and 1.7B, SenseVoice, Parakeet and Whisper from GGUF; CPU, Vulkan and CUDA. |
| Chat/translation models | **`llama-cpp-2`** (llama.cpp, Apache-2.0) | Runs Qwen3.5 GGUF; CPU, Vulkan and CUDA. |
| GPU path | **Vulkan** first; CUDA as a later add-on | One Vulkan build covers Intel, AMD and NVIDIA. |
| Microphone | **`cpal`** (WASAPI) + **`rubato`** resampler | Standard Rust audio capture. |
| System audio (later) | **`wasapi`** crate, loopback capture | For online classes in Zoom or Tencent Meeting. |
| Recording file | AAC through Windows Media Foundation | Same format as the Mac's `audio-N.aac`. |
| Audio decode/playback | **`symphonia`** + **`rodio`** | Sample-accurate seek for "Play this moment". |
| HTTP, streaming | **`reqwest`** + SSE | Remote model APIs and web search. |
| PDF | **pdf.js** (viewer) + **`pdfium-render`** (text, thumbnails) | Replaces PDFKit. |
| Office files | `zip` + `quick-xml` for docx, pptx, xlsx, epub | Replaces the Mac's unzip-and-read code. |
| Picture text (OCR) | **Windows.Media.Ocr** through the `windows` crate | Built into Windows; replaces Apple Vision. |
| Secrets | **`keyring`** (Windows Credential Manager) | Replaces Keychain. |
| Settings | **tauri-plugin-store** | Replaces UserDefaults. |
| Updates | **tauri-plugin-updater** | Replaces Sparkle. |
| Installer | **NSIS**, per-user (no admin prompt) | Tauri's default for Windows. |
| Strings | **i18next**, generated from `Localizable.strings` | One source of wording for both apps. |
| CI | GitHub Actions, `windows-latest` | Builds and tests every push. |

## 5. Models on any device

This is the core of "universal". The rule: **decide by measuring, not by reading the spec sheet**, and always have a smaller set to fall back to.

### 5.1 How live transcription loads the machine

Nomi cuts speech into phrases at pauses and sends each phrase to the speech model, with interim passes while the phrase is still growing. Each finished phrase then goes to the translation model. So during a lecture two models run at once, and the speech model runs several times per phrase. A device passes only if it keeps up **with both running together**.

transcribe.cpp does not offer streaming for Qwen3-ASR. That is fine: Nomi already works phrase by phrase, and transcribe.cpp supports the context prompt Nomi uses for course terms.

### 5.2 Model files

Sizes are the published GGUF files.

**Speech**

| Model | File | Size | Notes |
|---|---|---|---|
| SenseVoice Small | Q8_0 | 253 MB | Chinese, Cantonese, English, Japanese, Korean only. No context prompt. Very fast. |
| Qwen3-ASR 0.6B | Q4_K_M | 590 MB | 30 languages, auto-detect, context prompt. |
| Qwen3-ASR 0.6B | Q8_0 | 850 MB | Same, slightly more accurate. |
| Qwen3-ASR 1.7B | Q4_K_M | 1.32 GB | The Mac's model, smaller file. English WER 1.81%. |
| Qwen3-ASR 1.7B | Q8_0 | 2.19 GB | Closest to the Mac's 8-bit model. English WER 1.62%. |

**Translation and local answers** (unsloth GGUF)

| Model | File | Size |
|---|---|---|
| Qwen3.5 0.8B | Q4_K_M | 533 MB |
| Qwen3.5 2B | Q4_K_M | 1.28 GB |
| Qwen3.5 4B | Q4_K_M | 2.74 GB |

### 5.3 The three sets

| Set | Typical device | Speech | Translation | Interim text | Download | Memory in use (estimate) |
|---|---|---|---|---|---|---|
| **Lite** | 8 GB, 4 cores, no GPU | Qwen3-ASR 0.6B Q4 (SenseVoice if that is too slow) | Qwen3.5 0.8B | Off or slow | 0.8–1.1 GB | about 2 GB |
| **Standard** | 16 GB, 6+ cores or an integrated GPU | Qwen3-ASR 0.6B Q8 | Qwen3.5 2B | On | 2.1 GB | about 3.5 GB |
| **Full** | Discrete GPU with 6 GB+, or a strong integrated GPU with 32 GB | Qwen3-ASR 1.7B Q8 (Q4 on integrated) | Qwen3.5 2B, or 4B for answers | On | 3.5–4.9 GB | 5–7 GB |

- The user can always pick a different model by hand in Settings, as on Mac.
- On Lite, local answers and summaries from a 0.8B model are weak. Onboarding says so and suggests connecting an API for chat, while transcription and translation stay local.

### 5.4 What the published numbers say

transcribe.cpp publishes speed for these models on a 2020 laptop chip, the Ryzen 7 PRO 4750U (8 cores, integrated Radeon). "×" is how many times faster than real time.

| Model (Q4_K_M) | CPU only | Integrated GPU (Vulkan) |
|---|---|---|
| Qwen3-ASR 1.7B | 2.7–3.1× | 4.5–5.5× |
| Qwen3-ASR 0.6B | 5.2–6.6× | 10–12× |
| SenseVoice Small | 16–18× | 27× |

What this means:
- A six-year-old laptop with **no graphics card** runs Qwen3-ASR 0.6B at about 5× real time on the CPU alone. That is enough for live use.
- The 1.7B model on a CPU alone is about 3×, which is too tight once translation and interim passes share the CPU. It belongs on devices with a GPU or a newer CPU.
- These runs had the machine to themselves. With translation running, expect less. Phase 0 measures the combined load.

### 5.5 How Nomi picks a set

1. **Read the hardware** (instant): memory, CPU cores and instruction sets, and every GPU Vulkan reports (name, discrete or integrated, memory).
2. **Suggest a set** from that reading and show it in onboarding with its download size. The user can accept or choose another.
3. **Download** the two models (section 8.4).
4. **Measure** (about 30 seconds): transcribe a bundled 30-second clip while translating, on each placement that makes sense:
   - both models on the CPU;
   - speech on the GPU, translation on the CPU;
   - both on the GPU.
5. **Keep the fastest placement that passes.** Pass means:
   - speech at 4× real time or better with interim text on, or 2× with interim text off;
   - a phrase's translation finishes within 2 seconds.
6. **If nothing passes, step down**: turn interim text off, then offer the next smaller set.
7. **Remember** the result per GPU driver version, and measure again after a driver or Nomi update. Settings has "Check this PC again".

### 5.6 Devices with and without a GPU

**No GPU, or a GPU that fails**
- The CPU path is always present. ggml ships several CPU builds (AVX2, AVX-512 and so on) and picks the best one at run time, so one installer suits old and new chips.
- Threads are set to the number of performance cores, not all logical cores. On hybrid Intel chips, the efficiency cores slow things down if they are used for model math **(verify in Phase 0)**.

**Integrated GPUs (Intel, AMD)**
- Used through Vulkan. They share system memory, so the limit is free RAM, not video memory.
- Speech goes on the GPU first: it is the part that must keep pace. Translation stays on the CPU unless measuring shows both fit.
- Intel's Lunar Lake Vulkan driver has open bug reports in llama.cpp. This is the reason for the next point.

**Driver safety**
- Each model already runs in its own worker process. If a Vulkan driver crashes or hangs while loading, only that worker dies. The engine then restarts it on the CPU, marks that GPU and driver version as bad, and tells the user in plain words.
- Loading on a GPU has a time limit, because a known failure is a shader compile that never finishes.

**Discrete GPUs (NVIDIA, AMD, Arc)**
- Vulkan works on all of them, so 1.0 ships Vulkan only.
- CUDA is usually faster on NVIDIA. If Phase 0 shows a large gap, CUDA becomes an optional add-on downloaded on demand, because its runtime files are large and would bloat every install.

**Battery and heat**
- On battery, use fewer threads and slow the interim passes.
- During a recording the chat worker runs at low priority so transcription comes first. The Mac does this with a macOS-only call; Windows uses process priority classes.

**Windows on ARM (after 1.0)**
- CPU-only build. Handy ships the same way: Adreno Vulkan drivers are immature, and the Vulkan shader tool does not build under the ARM toolchain.

## 6. Engine changes (`Backend/`)

### 6.1 Workers
- `asr-worker` and `llm-worker` keep their names, flags and frames. The model code moves behind a small trait with two implementations chosen at compile time:
  - macOS: the current MLX code, untouched;
  - Windows: `transcribe-cpp` and `llama-cpp-2`.
- New flags: `--device cpu|gpu:<index>`, `--threads N`. A new `Ready` field reports which device actually loaded.
- `llm-worker` on Windows uses the chat template stored in the GGUF file, with thinking turned off for translation, as the Mac worker does.
- The repeat guard, token budget and short-phrase rule in `asr-worker` are plain Rust and carry over.

### 6.2 Engine
- New flag `--interim-interval` so a weak device can slow or stop interim passes.
- New route `GET /v1/devices` (CPU and GPU list) and `POST /v1/benchmark` (section 5.5).
- Default model folder becomes a parameter. Windows uses `%LOCALAPPDATA%\Nomi\models`.

### 6.3 Unix-only code to replace
| Today | Used for | Windows |
|---|---|---|
| `setpgid`, `kill(0, SIGTERM)` | Engine and workers die together, also when the app crashes | A Job Object with kill-on-close. stdin EOF already works on both. |
| `kill(pid, SIGUSR1)` | Stop the reply being written | A named event the worker checks in its token loop. |
| `setpriority(PRIO_DARWIN_BG)` | Chat worker yields to transcription | `SetPriorityClass` on the worker. |

### 6.4 Tests
- `replay-wav` already runs a WAV through the whole pipeline. CI runs it on Windows (CPU) and Mac with the same clip and checks both produce a sane transcript.
- Existing `voice-core` tests run on both systems.

### 6.5 Later option: one runtime for both systems
transcribe.cpp and llama.cpp both support Metal. Moving the Mac to them too would mean one model runtime and one set of model files everywhere. It is not part of this plan; MLX stays on Mac until there is a reason to change.

## 7. The Windows app (`Windows/`)

### 7.1 Shape

```
React UI (WebView2)
   │  typed commands and events (tauri-specta)
Tauri core (Rust)
   ├─ nomi-core: storage, chat, citations, library search, memory, queue
   ├─ audio: microphone → 16 kHz mono → engine WebSocket, and AAC file
   ├─ engine client: starts moxin-engine, HTTP + WebSocket on 127.0.0.1
   └─ updater, secrets, model downloads
moxin-engine.exe ── asr-worker.exe
                 └─ llm-worker.exe (translation), llm-worker.exe (answers)
```

The engine stays a separate program, started by the app, as on Mac. That keeps the engine identical on both systems and keeps a model crash away from the app.

### 7.2 `nomi-core`
A Rust library with no UI, holding what the Swift `AppModel` and `Models/` hold now.

- Ported file by file from Swift, each with its tests: `ChatContext`, `ChatHistory`, `CitationQuote`, `LectureMoment`, `LibrarySearch`, `ChatQueue`, `UserMemory`, `AnswerSteps`, `MeetingQA`, `SourceText`, `ContextBudget`, and the stores.
- The 236 Swift tests are the specification. A ported module is done when its ported tests pass.
- Prompts are copied word for word. A test compares the system prompt built by Rust with fixtures exported from the Swift tests.

### 7.3 Mac feature → Windows replacement

| Mac | Windows |
|---|---|
| SwiftUI screens | React components, one folder per page: Meetings, Meeting detail, Sources, Chat, Settings, Help, Onboarding |
| WKWebView answer page | The same `answer.html/js/css`, loaded in an iframe with the same message bridge |
| Citation card (NSPanel) | A positioned React layer; same look, 500 ms wait and fade |
| Dot loaders (`DotLoader.swift`) | Canvas component reading `Design/Animations/leaf-loaders.json` |
| AVAudioEngine microphone | `cpal` input stream, device list and hot-plug handling |
| "Classroom mic" voice processing | Not in 1.0. Later through WebRTC audio processing |
| AAC recording | Media Foundation AAC; FLAC on Windows "N" editions without media features |
| "Play this moment" | Decode with `symphonia`, seek by sample count, play with `rodio` |
| PDFKit viewer and thumbnails | pdf.js viewer at the cited page; `pdfium-render` for text and thumbnails |
| docx, pptx, xlsx, epub reading | `zip` + `quick-xml` |
| doc, rtf, odt (NSAttributedString) | rtf and odt through small Rust parsers; old `.doc` unsupported at first |
| Vision OCR for pictures | Windows.Media.Ocr; if no language pack, the picture goes to a vision-capable API model |
| Keychain | Windows Credential Manager |
| Sparkle | tauri-plugin-updater |
| LinkPresentation (site icon, picture) | Fetch the page and read its Open Graph tags |
| Microphone permission prompt | Detect denial and open `ms-settings:privacy-microphone` |
| `~/Library/Application Support/Nomi` | `%LOCALAPPDATA%\Nomi` |
| `~/.OminiX/models` | `%LOCALAPPDATA%\Nomi\models` |

### 7.4 Look and feel
- Nomi's own design, not a copy of macOS: same colors, spacing and leaf mark, with Windows conventions for the title bar (caption buttons on the right, snap layouts).
- Fonts: Segoe UI Variable, with Microsoft YaHei UI for Chinese.
- Light and dark follow the system. Reduced motion follows the Windows animation setting.
- The compact recording window carries over. It is a normal window, as decided for 0.9.1.

### 7.5 Shared files
- `AnswerWeb/` moves to `Shared/AnswerWeb/`. The Mac build copies it into its bundle; the Windows app imports it. One copy, two apps.
- Strings: a script turns `en.lproj/Localizable.strings` into `en.json` and `zh.json`. Chinese stays the key language.

## 8. Packaging, updates and distribution

### 8.1 Installer
- NSIS, installs per user with no administrator prompt.
- WebView2 is part of Windows 11. For Windows 10 the installer carries the small WebView2 bootstrapper.
- The installer holds the app, the engine, the workers and the Vulkan and CPU backend libraries. Models are downloaded on first run, as on Mac.
- No Vulkan runtime is installed by Nomi. GPU drivers provide it; without one, Nomi uses the CPU.

### 8.2 Code signing (your decision, section 13)
Unsigned Windows apps show a SmartScreen warning ("Windows protected your PC").

| Route | Cost | Notes |
|---|---|---|
| Unsigned | Free | Fine for a beta with instructions. Not for 1.0. |
| Microsoft Store (MSIX) | Free | Individual accounts are free since late 2025 and the Store signs MSIX packages. Tauri does not produce MSIX itself, so this needs an extra packaging step, and Store rules apply. |
| SignPath Foundation | Free for open source | Nomi is public and MIT-licensed, so it may qualify **(verify terms)**. |
| Certificate from a CA (DigiCert, Sectigo, GlobalSign) | Paid yearly | Works everywhere. Needs identity validation and a hardware or cloud key. |
| Azure Artifact Signing | Low monthly fee | Per Microsoft Q&A posts in 2026, individuals are accepted only in the USA and Canada, and organizations only in the USA, Canada, EU and UK **(verify)**. |

### 8.3 Updates
- tauri-plugin-updater checks a small JSON file and verifies each update with Nomi's own update key. This key is separate from code signing.
- **Important:** the Mac app reads `releases/latest/download/appcast.xml`. Whatever GitHub release is marked Latest must contain that file, or Mac updates stop. So:
  - during the Windows beta, Windows builds are published as pre-releases under their own tag and are never marked Latest;
  - from Windows 1.0, each version is one release carrying both systems' files: `appcast.xml` and the DMG for Mac, `latest.json` and the installer for Windows.

### 8.4 Model downloads
- Same approach as the Mac: pinned revisions, resume, size and SHA-256 check.
- huggingface.co is not reachable from mainland China, and the first test device is a Chinese-language laptop. The downloader tries a list of sources in order: huggingface.co, then a mirror, then ModelScope. This needs Nomi's own model repo on ModelScope holding the exact files **(decision 6)**.

### 8.5 Other channels
- winget manifest after 1.0.
- nomi.software gets a Windows download button. The site is deployed by you, not by pushing `website/`.

## 9. Repo layout

```
Nomi/
├─ Backend/                 shared engine (Rust workspace)
│  ├─ moxin-engine/
│  ├─ crates/voice-core/
│  └─ workers/
│     ├─ asr-worker/        src/mlx.rs (macOS), src/ggml.rs (Windows)
│     └─ llm-worker/        src/mlx.rs (macOS), src/gguf.rs (Windows)
├─ Shared/
│  ├─ AnswerWeb/            answer.html, answer.js, answer.css, vendor/
│  └─ strings/              generated en.json, zh.json
├─ Sources/, Tests/         the Mac app (unchanged)
├─ Windows/
│  ├─ src/                  React UI
│  ├─ src-tauri/            Tauri core
│  └─ crates/nomi-core/     app logic and its tests
├─ Design/                  shared design files and loaders JSON
├─ scripts/                 build-app.sh (Mac), build-windows.ps1
└─ .github/workflows/       mac.yml, windows.yml
```

Work happens in short branches merged into `main`. There is no long-lived Windows branch.

## 10. Phases

Each phase ends with something you can run. Sizes are rough estimates for one person working with AI help.

**Phase 0 — Prove the runtime (about 1 week)**
- Build `transcribe-cli` and `llama-cli` for Windows in CI: CPU and Vulkan.
- On the Huawei laptop (Core Ultra 9 185H, Arc integrated) and at least one PC with no GPU, measure every model in section 5.2, alone and together, on CPU and Vulkan.
- Confirm Qwen3.5 GGUF loads in the llama.cpp version `llama-cpp-2` bundles, and that translation quality matches the Mac on the same sentences.
- Confirm the Qwen3-ASR context prompt behaves like the MLX loader's.
- **Done when:** a table of real numbers exists and the three sets in section 5.3 are confirmed or adjusted. If Qwen3-ASR falls short, the fallback is SenseVoice or Parakeet for the Lite set, which the same library already runs.

**Phase 1 — Engine on Windows (about 2 weeks)**
- Section 6: workers, flags, Job Object, cancel event, priority, device list, benchmark route.
- CI builds and runs `replay-wav` on Windows.
- **Done when:** `moxin-engine.exe replay-wav` turns a lecture WAV into a translated transcript on a PC, on CPU and on GPU.

**Phase 2 — Record and read (about 3 weeks)**
- Tauri app skeleton, design tokens, rail and pages.
- Onboarding: device check, model download, microphone.
- Microphone capture, live transcript, AAC recording, meeting list and detail, categories.
- Storage in `nomi-core` with the Mac's schema.
- **Done when:** you can record a real lecture on a PC and read it back the next day.

**Phase 3 — Sources and chat (about 4–5 weeks)**
- Sources: import, PDF, Office files, OCR.
- Chat: API providers, local answers, web search, library search, steps, queue and steer, memory.
- Answer page, citations, cards, jump to the moment, play the moment.
- Q&A and summaries in the meeting side panel.
- **Done when:** the ported tests pass and a chat on a PC cites a lecture, a PDF and a web page correctly.

**Phase 4 — Ship (about 2 weeks)**
- Settings, Help, tutorial, English and Chinese.
- Installer, updater, signing, release workflow.
- Diagnostics: a "Copy device report" button, since there is no telemetry.
- **Done when:** a public beta installer updates itself to the next beta.

**After 1.0**
- System audio capture for online classes.
- CUDA add-on if Phase 0 numbers justify it.
- Windows on ARM.
- Classroom mic processing.

## 11. Testing

- **Logic:** ported unit tests in `nomi-core`, run in CI on every push.
- **Engine:** `replay-wav` on Windows and Mac in CI (CPU).
- **Devices:** GPUs cannot be tested in CI. A manual pass before each release on:
  - a PC with no GPU and 8 GB;
  - an Intel integrated GPU (the Huawei laptop);
  - an AMD integrated GPU;
  - an NVIDIA card.
  Cloud GPU machines can stand in for hardware you do not own.
- **Developing from a Mac:** UI work can run in a Windows VM, but a VM's GPU is not representative. Model and audio work must be checked on real PCs.

## 12. Risks

| Risk | Effect | Answer |
|---|---|---|
| Qwen3-ASR on GGUF behaves differently from the MLX build (context prompt, repeats) | Lower accuracy or new repeat loops | Phase 0 comparison on the same recordings; the repeat guards are already in shared Rust. |
| Vulkan driver crashes or hangs on some integrated GPUs | Model never loads | Worker isolation, load time limit, automatic CPU fallback, remembered per driver. |
| Weak CPUs cannot keep up even with small models | Late text | Lite set, interim text off, SenseVoice as the floor; onboarding says honestly what the PC can do. |
| Two runtimes (MLX and ggml) drift apart | Different results on Mac and PC | Shared prompts and tests; optional later move of the Mac to ggml (6.5). |
| Model downloads fail in mainland China | Onboarding cannot finish | Source list with mirror and ModelScope. |
| SmartScreen warning scares users | Fewer installs | Signing decision before 1.0. |
| Windows release marked Latest without `appcast.xml` | Mac updates stop | Rule in 8.3; the release script checks for the file. |
| Port of 13,000 lines of logic introduces behavior gaps | Bugs the Mac does not have | Tests are ported first and gate each module. |
| Old `.doc` files and iWork files are not readable | Some sources refused | Stated in the import message, as on Mac for iWork today. |

## 13. Decisions for you

My suggestion is in bold.

1. **UI stack.** **Tauri 2 + React + TypeScript**, or Electron (heavier, more forgiving), or native WinUI (most work).
2. **Where app logic lives.** **A Rust crate (`nomi-core`) with the ported tests**, or TypeScript in the UI (faster to write, harder to keep equal to the Mac).
3. **GPU path for 1.0.** **Vulkan only**, with CUDA as a later add-on if Phase 0 shows a large gain on NVIDIA.
4. **Lowest device to support.** **8 GB, 4 cores, AVX2, no GPU, on the Lite set.** Going lower means SenseVoice only and no local translation.
5. **Code signing.** **Beta unsigned; apply to SignPath for open source; fall back to the Microsoft Store (MSIX) or a paid certificate for 1.0.**
6. **Model mirror for China.** **Yes: a Nomi repo on ModelScope with the exact GGUF files.** It needs an account you own.
7. **Recording format.** **AAC, the same as Mac**, or Opus (smaller, but the Mac could not play it without extra work).
8. **Release numbering.** **Windows starts as 0.1 beta under its own pre-release tag; it joins the Mac's version number at 1.0.**

## 14. Sources

- [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp): supported models, backends, Windows build guide, speed tables.
- [Qwen3-ASR 1.7B GGUF](https://huggingface.co/handy-computer/Qwen3-ASR-1.7B-gguf) and [0.6B GGUF](https://huggingface.co/handy-computer/Qwen3-ASR-0.6B-gguf): file sizes and accuracy.
- [Handy](https://github.com/cjpais/Handy): Tauri 2 offline speech app; its `Cargo.toml` shows the Vulkan and ARM choices on Windows.
- [unsloth/Qwen3.5-2B-GGUF](https://huggingface.co/unsloth/Qwen3.5-2B-GGUF): Qwen3.5 for llama.cpp.
- [llama-cpp-rs](https://github.com/utilityai/llama-cpp-rs): Rust bindings and backend features.
- [OpenVINO backend in llama.cpp](https://medium.com/openvino-toolkit/openvino-lands-in-llama-cpp-run-gguf-models-on-intel-cpu-gpu-and-npu-d6fca1d633e8): Intel CPU, GPU and NPU, work in progress.
- [llama.cpp OpenCL backend for Adreno](https://www.qualcomm.com/developer/blog/2024/11/introducing-new-opn-cl-gpu-backend-llama-cpp-for-qualcomm-adreno-gpu): Snapdragon status.
- [llama.cpp Vulkan performance discussion](https://github.com/ggml-org/llama.cpp/discussions/10879) and [Lunar Lake Vulkan issue](https://github.com/ggml-org/llama.cpp/issues/18946).
- [OpenVINO guide for Qwen3-ASR](https://developer.aliyun.com/article/1712893): an alternative Intel-only route, not chosen.
- [sherpa-onnx Qwen3-ASR page](https://k2-fsa.github.io/sherpa/onnx/qwen3-asr/huggingface-space.html): an alternative ONNX route, not chosen.
- [Tauri Windows code signing](https://v2.tauri.app/distribute/sign/windows/).
- [Free Microsoft Store registration for individuals](https://blogs.windows.com/windowsdeveloper/2025/09/10/free-developer-registration-for-individual-developers-on-microsoft-store/) and [Store getting-started FAQ](https://learn.microsoft.com/en-us/windows/apps/publish/faq/get-started-with-the-microsoft-store).
- [Artifact Signing availability by country](https://learn.microsoft.com/en-us/answers/questions/2243504/trusted-signing-for-other-countries) (Microsoft Q&A).
- [wasapi-rs](https://github.com/HEnquist/wasapi-rs) and [cpal](https://github.com/RustAudio/cpal): Windows audio capture.
