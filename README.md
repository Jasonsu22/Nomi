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
| 🎙️ **Live transcription** | Listens to the microphone and writes as you speak. The translation follows each passage. A meeting can be paused and resumed. |
| 🗂️ **Categories** | Meetings and sources share one set of categories. |
| 📎 **Sources** | Import PDFs and documents. Files added on a meeting’s Sources tab stay linked to that meeting and are filed under its category. |
| 💬 **Ask** | Choose meetings, sources, or categories as context. With nothing selected, only the question is sent. Ask inside a meeting reads that meeting and its linked files. |
| 📝 **Summary** | Summarizes a meeting from its transcript. |
| 🧠 **Local models** | Download, switch, and delete models for speech recognition, translation, and questions. |
| 🔌 **API** | Save several model IDs, or fetch the list from the service. Keys stay in the macOS Keychain. |
| 🪄 **Skills** | One system prompt, a default reply language, and skills you can turn on or off. |

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
| Meetings and categories | `~/Library/Application Support/Nomi/meetings.json` |
| Source index and file copies | `~/Library/Application Support/Nomi/sources.json` and `sources/` |
| Links between meetings and sources | `~/Library/Application Support/Nomi/meeting-links.json` |
| Ask history | `~/Library/Application Support/Nomi/chats/` |
| Local models | `~/.OminiX/models` |
| API keys | macOS Keychain |
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
