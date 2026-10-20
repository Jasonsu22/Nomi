<p align="center">
  <img src="Design/Brand/logo-in-app.svg" width="128" alt="Nomi">
</p>

<h1 align="center">Nomi</h1>

<p align="center">
  <strong>English</strong> · <a href="README.zh-CN.md">中文</a>
</p>

<p align="center">
  On-device lecture transcription, translation, and study.<br>
  Record a class, then keep the transcript, the translation, the slides, and notes you can ask about.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-20B68A?style=flat-square" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Swift-6.2-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.2">
  <img src="https://img.shields.io/badge/Rust-engine-000000?style=flat-square&logo=rust&logoColor=white" alt="Rust">
  <img src="https://img.shields.io/badge/Apple%20Silicon-MLX-555555?style=flat-square" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/license-MIT-20B68A?style=flat-square" alt="MIT License">
</p>

The interface is SwiftUI and the engine is Rust. The product name is Nomi. The Swift module is `LectureNoteApp`. Speech recognition and translation run on this Mac. Questions and summaries can use a local model or your own API.

## ✨ Features

| | |
| --- | --- |
| 🎙️ **Live transcription** | Listens to the microphone and writes as you speak. The translation follows each passage. A meeting can be paused and resumed. Works with AirPods and other Bluetooth microphones, and chat keeps working while you record. |
| 🗂️ **Categories** | Meetings and sources share one set of categories. |
| 📎 **Sources** | Import PDFs and documents. Files added on a meeting’s Sources tab stay linked to that meeting and are filed under its category. |
| 💬 **Ask** | Choose meetings, sources, or categories as context. Ask inside a meeting reads that meeting and its linked files. When a question needs more, such as "what did the teacher say last week", Nomi searches all your lectures, earlier chats and files, and every passage it uses is cited; a cited chat opens that chat. With Web on, each question is searched on the web too. Explanations can come with an interactive demo. |
| ❓ **Q&A** | A meeting's Q&A tab lists the real questions the teacher asked (not "right?" or "can you hear me?"), found while recording and again when it ends, and answers them one at a time from the lecture, its files and the web. Turn off Auto-answer to answer each one yourself. Each question links to its moment in the transcript. |
| 📝 **Summary** | Summarizes a meeting from its transcript, and keeps the summary with the meeting. Long chats keep a running summary, so follow-ups still know what was said earlier. |
| 🧩 **Memory** | Learns your preferences, courses and goals from your chats and uses them in later answers. Review, edit, pin, turn off or clear it in Settings › Memory. |
| 🧠 **Local models** | Download, switch, and delete models for speech recognition, translation, and questions. |
| 🔌 **API** | Save several model IDs, or fetch the list from the service. Keys stay in the macOS Keychain. |
| 🪄 **Skills** | One system prompt, a default reply language, and skills you can turn on or off. |
| ❔ **Help** | App information, a quick tutorial of the main buttons, and a contact email. |

## 🚀 Getting started

You need an Apple Silicon Mac, macOS 26, Xcode (Swift 6.2), and Rust. The first build downloads dependencies, including a pinned revision of [OminiX-MLX](https://github.com/OminiX-ai/OminiX-MLX).

```sh
bash scripts/build-app.sh
open build/Nomi.app
```

`build-app.sh` accepts `debug` (the default) or `release` and writes `build/Nomi.app`. The `build/` directory is not committed.

After a Swift-only change, refresh the existing app without rebuilding Rust:

```sh
bash scripts/refresh-app.sh
```

That script requires `build/Nomi.app` to exist already.

Without a paid Apple Developer certificate, macOS asks for the Keychain password again after every rebuild. Debug builds, and release builds made with `NOMI_DEV_KEYS=1`, copy each API key into a private file after the first approval, so rebuilding stops asking:

```sh
NOMI_DEV_KEYS=1 bash scripts/build-app.sh release
```

The script prints a warning when this mode is on. Builds you give to other people should be plain release builds, which keep keys in the Keychain only.

## 🧩 Modules

| | Module | Where |
| --- | --- | --- |
| 🖥️ | SwiftUI interface, meetings, Ask, and settings | `Sources/LectureNoteApp/` |
| 🧪 | Swift tests | `Tests/LectureNoteTests/` |
| ⚙️ | Local engine, `moxin-engine` | `Backend/moxin-engine/` |
| 🗣️ | Speech-recognition worker | `Backend/workers/asr-worker/` |
| 🌐 | Translation and local question worker | `Backend/workers/llm-worker/` |
| 📦 | ASR loader shipped with this repo | `Backend/vendor/qwen3-asr-mlx/` |
| 🎨 | Logo and app icon | `Design/Brand/` |

The packager copies `moxin-engine`, `asr-worker`, `llm-worker`, and `mlx.metallib` from `Backend/target`. Packaging stops if any of them is missing.

## 🔒 Build it on its own

You do not need a checkout of [Moxin-Voice](https://github.com/moxin-org/Moxin-Voice) or [Moxin-Studio](https://github.com/moxin-org/Moxin-Studio) to compile or run Nomi. The engine, both workers, and the patched Qwen3-ASR loader are already in `Backend/`. The app starts that engine itself and stops it on quit. Debug builds look for `Backend/target/debug/moxin-engine`. The packaged app uses only the copy inside the bundle.

Downloaded weights stay in `~/.OminiX/models`. That directory holds model files. On a Mac without them, download the models again from Settings.

The live transcription path began in Moxin-Voice. Thank you. See [Acknowledgements](#-acknowledgements).

## 🗂️ Data

| What | Where |
| --- | --- |
| Meetings, categories and meeting summaries | `~/Library/Application Support/Nomi/meetings.json` |
| Source index and file copies | `~/Library/Application Support/Nomi/sources.json` and `sources/` |
| Links between meetings and sources | `~/Library/Application Support/Nomi/meeting-links.json` |
| Ask history | `~/Library/Application Support/Nomi/chats/` |
| Meeting Q&A | `~/Library/Application Support/Nomi/qa/` |
| Memory | `~/Library/Application Support/Nomi/memory.json` |
| Local models | `~/.OminiX/models` |
| API keys | macOS Keychain; development builds also keep a copy in `~/Library/Application Support/Nomi/secrets.json` (readable only by you) |
| Engine log | `~/Library/Logs/Nomi/engine.log` |

Interface language, appearance, microphone permission, the selected local model, and API profiles are stored in the app’s UserDefaults.

## 🧪 Tests

```sh
swift test
cargo test --manifest-path Backend/Cargo.toml --locked
```

Pushes to `main` and pull requests run GitHub Actions. Swift is built and tested on macOS 26. The engine crates that do not use MLX (`voice-core` and `moxin-engine`) are tested on Linux. The speech and translation workers need Apple’s MLX, so that Linux runner does not compile them.

## 🙏 Acknowledgements

Nomi’s own interface and the work written for this app are MIT. Code and ideas taken from other projects stay under those projects’ licenses.

| Project | What Nomi took from it | Their license |
| --- | --- | --- |
| [Moxin-Voice](https://github.com/moxin-org/Moxin-Voice) | The live transcription engine, the speech and translation workers, and the shared voice pipeline. Nomi continues that work in `Backend/`. | Apache-2.0 |
| [Moxin-Studio](https://github.com/moxin-org/Moxin-Studio) | The shape of the local model manager, and the set of text API providers. | Apache-2.0 |
| [OminiX-MLX](https://github.com/OminiX-ai/OminiX-MLX) | The Apple Silicon inference crates, pinned at `6aac996`. The patched ASR loader in `Backend/vendor/qwen3-asr-mlx/` comes from this tree. | Apache-2.0. The vendored loader is also shipped with its MIT text. |
| [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR) | The prompt format and the way recognition output is parsed. | Apache-2.0 |
| [MLX](https://github.com/ml-explore/mlx) | The array framework underneath OminiX-MLX. | MIT |

## 📄 License

Nomi’s own source is [MIT](LICENSE). Copyright 2026 Jason Su.

Imported and vendored code keeps its original license:

- `Backend/`, adapted from Moxin-Voice, remains [Apache-2.0](Backend/LICENSE).
- `Backend/vendor/qwen3-asr-mlx/` remains under the [MIT](Backend/vendor/qwen3-asr-mlx/LICENSE-MIT) and [Apache-2.0](Backend/vendor/qwen3-asr-mlx/LICENSE-APACHE) texts shipped with it.
