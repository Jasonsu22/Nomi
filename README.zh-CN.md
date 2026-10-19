<p align="center">
  <img src="Design/Brand/logo-in-app.svg" width="128" alt="Nomi">
</p>

<h1 align="center">Nomi</h1>

<p align="center">
  <a href="README.md">English</a> · <strong>中文</strong>
</p>

<p align="center">
  本机课堂转录、翻译和学习。<br>
  听一场课，留下原文、译文、课件，以及可以继续追问的笔记。
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%2B-20B68A?style=flat-square" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Swift-6.2-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.2">
  <img src="https://img.shields.io/badge/Rust-engine-000000?style=flat-square&logo=rust&logoColor=white" alt="Rust">
  <img src="https://img.shields.io/badge/Apple%20Silicon-MLX-555555?style=flat-square" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/license-MIT-20B68A?style=flat-square" alt="MIT License">
</p>

界面是 SwiftUI，引擎是 Rust。产品名是 Nomi，Swift 模块名是 `LectureNoteApp`。识别和翻译在这台 Mac 上完成；提问和摘要可以用本机模型，也可以改用你自己的 API。

## ✨ 功能

| | |
| --- | --- |
| 🎙️ **实时转写** | 听麦克风，边说边出字。译文接在同一段下面。一场会议可以暂停后再继续录。 |
| 🗂️ **分类** | 用同一套分类整理会议和资料。 |
| 📎 **资料** | 导入 PDF 和文档。会议详情的「资料」页会把文件挂到这场会议，并放进对应分类。 |
| 💬 **提问** | 选择会议、资料或分类作为范围。不选范围时只回答这个问题。会议里的提问只看这场会议和它挂上的资料。 |
| 📝 **摘要** | 根据这场会议的转写生成摘要。 |
| 🧠 **本机模型** | 下载、切换、删除语音识别、翻译和提问用的模型。 |
| 🔌 **API** | 保存多条模型 ID，或向服务拉取列表。密钥放在 macOS 钥匙串里。 |
| 🪄 **技能** | 一份系统提示词、默认回复语言，以及可以单独开关的技能。 |

## 🚀 开始使用

需要 Apple Silicon Mac、macOS 26、Xcode（Swift 6.2）和 Rust。首次编译会从网络拉取依赖，其中包括固定版本的 [OminiX-MLX](https://github.com/OminiX-ai/OminiX-MLX)。

```sh
bash scripts/build-app.sh
open build/Nomi.app
```

`build-app.sh` 接受 `debug`（默认）或 `release`，并生成 `build/Nomi.app`。`build/` 不进入 git。

只改了 Swift 界面时，可以更新已有的应用包，而不重新编译 Rust：

```sh
bash scripts/refresh-app.sh
```

这个脚本要求 `build/Nomi.app` 已经存在。

## 🧩 模块

| | 模块 | 在哪里 |
| --- | --- | --- |
| 🖥️ | SwiftUI 界面、会议、提问、设置 | `Sources/LectureNoteApp/` |
| 🧪 | Swift 测试 | `Tests/LectureNoteTests/` |
| ⚙️ | 本机引擎 `moxin-engine` | `Backend/moxin-engine/` |
| 🗣️ | 语音识别 worker | `Backend/workers/asr-worker/` |
| 🌐 | 翻译与本机提问 worker | `Backend/workers/llm-worker/` |
| 📦 | 随仓库提供的 ASR 加载器 | `Backend/vendor/qwen3-asr-mlx/` |
| 🎨 | 标志与应用图标 | `Design/Brand/` |

打包脚本只从 `Backend/target` 复制 `moxin-engine`、`asr-worker`、`llm-worker` 和 `mlx.metallib`。缺任何一个都会停止打包。

## 🔒 可以单独编译

编译和运行不需要再克隆 [Moxin-Voice](https://github.com/moxin-org/Moxin-Voice) 或 [Moxin-Studio](https://github.com/moxin-org/Moxin-Studio)。引擎、两个 worker，以及改过的 Qwen3-ASR 加载器已经在 `Backend/` 里。应用自己拉起这个引擎，退出时关掉它。调试构建找 `Backend/target/debug/moxin-engine`；打包后的应用只用包内的那一份。

已经下载的模型权重仍放在 `~/.OminiX/models`。这是模型文件目录。换一台没有这些文件的 Mac 时，在设置里重新下载即可。

实时转写这条路径是从 Moxin-Voice 继续做下来的。谢谢。见[致谢](#-致谢)。

## 🗂️ 数据

| 内容 | 位置 |
| --- | --- |
| 会议、分类 | `~/Library/Application Support/Nomi/meetings.json` |
| 资料索引和文件副本 | `~/Library/Application Support/Nomi/sources.json` 与 `sources/` |
| 会议和资料的关联 | `~/Library/Application Support/Nomi/meeting-links.json` |
| 提问记录 | `~/Library/Application Support/Nomi/chats/` |
| 本机模型 | `~/.OminiX/models` |
| API 密钥 | macOS 钥匙串 |
| 引擎日志 | `~/Library/Logs/Nomi/engine.log` |

界面语言、外观、麦克风权限、所选本机模型和 API 配置保存在应用的 UserDefaults 里。

## 🧪 测试

```sh
swift test
cargo test --manifest-path Backend/Cargo.toml --locked
```

推送到 `main` 或打开拉取请求时，GitHub Actions 会在 macOS 26 上编译并测试 Swift 界面，并在 Linux 上测试不依赖 MLX 的引擎（`voice-core`、`moxin-engine`）。语音识别和翻译 worker 需要 Apple 的 MLX，不在这台 Linux 运行器上编译。

## 🙏 致谢

Nomi 自己的界面和为这个应用写的部分使用 MIT。从别的项目拿来的代码和想法，仍使用那些项目原来的许可。

| 项目 | Nomi 用到了什么 | 他们的许可 |
| --- | --- | --- |
| [Moxin-Voice](https://github.com/moxin-org/Moxin-Voice) | 实时转写引擎、语音识别和翻译 worker，以及共用的语音流水线。Nomi 在 `Backend/` 里接着改。 | Apache-2.0 |
| [Moxin-Studio](https://github.com/moxin-org/Moxin-Studio) | 本机模型管理的做法，以及文本 API 服务商的范围。 | Apache-2.0 |
| [OminiX-MLX](https://github.com/OminiX-ai/OminiX-MLX) | Apple Silicon 上的推理库，固定在 `6aac996`。`Backend/vendor/qwen3-asr-mlx/` 里改过的识别加载器来自这里。 | Apache-2.0。随仓库附带的加载器同时带有 MIT 文本。 |
| [Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR) | 提示词格式，以及识别结果的解析方式。 | Apache-2.0 |
| [MLX](https://github.com/ml-explore/mlx) | OminiX-MLX 底下的数组计算框架。 | MIT |

## 📄 许可

Nomi 自己的源码使用 [MIT](LICENSE)。Copyright 2026 Jason Su。

引进和附带的代码保留原来的许可：

- `Backend/` 从 Moxin-Voice 接过来，仍是 [Apache-2.0](Backend/LICENSE)。
- `Backend/vendor/qwen3-asr-mlx/` 仍使用随它附带的 [MIT](Backend/vendor/qwen3-asr-mlx/LICENSE-MIT) 和 [Apache-2.0](Backend/vendor/qwen3-asr-mlx/LICENSE-APACHE)。
