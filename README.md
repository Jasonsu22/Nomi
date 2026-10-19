# Nomi

Nomi 是跑在本机上的 macOS 课堂笔记应用。它对麦克风做实时转写和翻译，把课件收进资料库，并按会议或分类回答问题。识别和翻译在这台 Mac 上完成；提问和摘要可以用本机模型，也可以改用你自己的 API。

界面是 SwiftUI，引擎是 Rust。产品名是 Nomi，Swift 模块名是 `LectureNoteApp`。

## 能做什么

- 从麦克风实时转写，并把译文接在同一段下面。一场会议可以暂停后再继续录。
- 用分类整理会议。分类和资料库是同一套。
- 把 PDF 和文档导入资料库。在会议详情的「资料」页导入的文件会挂到这场会议，同时放进这个分类。
- 在「提问」里选择会议、资料或分类作为范围。不选范围时只回答这个问题，不把资料塞进上下文。会议详情里的提问只看这场会议和它挂上的资料。
- 为会议生成摘要。
- 在本机模型和使用 API 之间切换。API 密钥放在 macOS 钥匙串里。一个配置可以保存多条模型 ID，也可以向服务拉取模型列表。
- 编辑一份系统提示词，设置默认回复语言，并添加可以单独开关的技能。

## 环境

- Apple Silicon Mac
- macOS 26 或更新版本
- Xcode，以及 Swift 6.2 工具链
- Rust 和 Cargo

首次编译会从网络拉取 Rust 依赖，其中包含固定版本的 [OminiX-MLX](https://github.com/OminiX-ai/OminiX-MLX)。

## 独立于 Moxin

编译和运行都不读取旁边的 Moxin-Voice 或 Moxin-Studio 目录。

- Swift 包没有指向仓库外的路径依赖。
- 引擎、语音识别 worker、语言模型 worker，以及改过的 Qwen3-ASR 加载器都在这个仓库的 `Backend/` 里。
- 打包脚本只从 `Backend/target` 复制 `moxin-engine`、`asr-worker`、`llm-worker` 和 `mlx.metallib`。缺任何一个都会停止打包。
- 应用启动后自己拉起本机引擎，退出时关掉引擎和它的 worker。调试构建会找 `Backend/target/debug/moxin-engine`；打包后的应用只用包内的那一份。
- 已经下载的模型权重仍放在 `~/.OminiX/models`。这是模型文件目录，不是 Moxin 的源码。换一台没有这些文件的 Mac 时，在 Nomi 的设置里重新下载即可。

## 编译并运行

在仓库根目录：

```sh
bash scripts/build-app.sh
open build/Nomi.app
```

`build-app.sh` 接受 `debug`（默认）或 `release`。它会编译 Rust 后端和 Swift 界面，并生成 `build/Nomi.app`。`build/` 不进入 git。

只改了 Swift 界面时，可以更新已有的应用包，而不重新编译 Rust：

```sh
bash scripts/refresh-app.sh
```

这个脚本要求 `build/Nomi.app` 已经存在。

## 数据放在哪里

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

## 目录

```text
Package.swift                 Swift 包
Sources/LectureNoteApp/       界面、会议、提问、设置
Tests/LectureNoteTests/       Swift 测试
Backend/                      Rust 引擎和两个 worker
Backend/vendor/qwen3-asr-mlx/ 随仓库提供的 ASR 加载器
scripts/build-app.sh          编译并打包应用
scripts/refresh-app.sh        只更新 Swift 界面
Design/Brand/                 应用图标
docs/                         设计说明和本机模型说明
```

## 测试

```sh
swift test
cargo test --manifest-path Backend/Cargo.toml --locked
```

## 许可

`Backend/` 使用 Apache License 2.0，见 [Backend/LICENSE](Backend/LICENSE)。`Backend/vendor/qwen3-asr-mlx/` 同时提供 MIT 和 Apache-2.0 许可。界面源码目前没有单独的许可证文件。
