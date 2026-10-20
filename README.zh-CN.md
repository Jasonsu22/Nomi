<p align="center">
  <img src="Design/Brand/logo-in-app.svg" width="96" alt="Nomi">
</p>

<h1 align="center">Nomi</h1>

<p align="center">
  <b>每一节课，都用你的母语听懂。</b><br>
  在你的 Mac 上实时转写和翻译，还有一个了解你课程的助手。
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>中文</strong> · <a href="https://nomi.software">nomi.software</a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Design/README/hero-dark.svg">
    <img src="Design/README/hero-light.svg" width="760" alt="老师讲课时 Nomi 实时写下内容，逐段翻译，并回答老师提出的问题">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/Jasonsu22/Nomi/releases/latest/download/Nomi-arm64.dmg"><img src="Design/README/download-zh.svg" height="54" alt="下载 Mac 版"></a>
</p>

<p align="center">
  <a href="https://github.com/Jasonsu22/Nomi/releases/latest"><img src="https://img.shields.io/github/v/release/Jasonsu22/Nomi?style=flat-square&color=20B68A&label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC" alt="最新版本"></a>
  <a href="https://github.com/Jasonsu22/Nomi/releases"><img src="https://img.shields.io/github/downloads/Jasonsu22/Nomi/total?style=flat-square&color=004A77&label=%E4%B8%8B%E8%BD%BD" alt="下载次数"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-555555?style=flat-square&logo=apple&logoColor=white" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Apple%20silicon-MLX-555555?style=flat-square" alt="Apple 芯片">
  <img src="https://img.shields.io/badge/license-MIT-20B68A?style=flat-square" alt="MIT 许可">
</p>

## 💡 为什么用 Nomi

用第二语言上课本来就不容易：老师语速快，生词到处都是，边听边记往往两头都顾不好。Nomi 帮你听、帮你记，把每一段翻译在原文下方，下课后还能就课上的内容回答你的问题。语音识别和翻译都在你的 Mac 上完成，你的课堂只留在你手里。

## ✨ 能做什么

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>🎙️ 实时转写</h3>
      老师说话时文字随即出现，随后整理成句子，译文显示在下方。随时暂停、继续。支持 AirPods 等蓝牙麦克风。
    </td>
    <td width="50%" valign="top">
      <h3>❓ 老师的提问，都有答案</h3>
      「问答」页收集老师在课上真正提出的问题（不包括「对吧？」「能听到吗？」），并逐个回答。每个问题都能跳回转写里的那一刻。
    </td>
  </tr>
  <tr>
    <td valign="top">
      <h3>💬 问以前的任何内容</h3>
      「老师上周讲考试说了什么？」Nomi 会搜索你全部的课堂转写、以前的对话和资料，并标出回答每一部分的来源。打开「联网」还会上网查资料。
    </td>
    <td valign="top">
      <h3>🧪 交互演示</h3>
      有些概念看比读更好懂。回答会附上一个小的交互页面：拖动滑块、按下按钮，看着概念动起来。
    </td>
  </tr>
  <tr>
    <td valign="top">
      <h3>📎 课件和阅读材料</h3>
      导入 PDF、幻灯片和文档，关联到某节课后，Nomi 会把它们和转写一起参考。
    </td>
    <td valign="top">
      <h3>📝 摘要</h3>
      把 90 分钟的课浓缩成要点、新术语和结论，和会议一起保存，方便复习。
    </td>
  </tr>
  <tr>
    <td valign="top">
      <h3>🧩 越用越懂你</h3>
      Nomi 会记住你的偏好、课程和考试日期，之后回答时用上。可以在「设置 › 记忆」里查看、编辑或关闭。
    </td>
    <td valign="top">
      <h3>🔒 隐私优先</h3>
      识别和翻译在你的 Mac 上运行，没有网络也能用。提问可以用本地模型或你自己的 API，密钥保存在 macOS 钥匙串中。
    </td>
  </tr>
</table>

录音时也能照常提问，实时转写始终优先。课堂语言和翻译支持中文、英语、日语、韩语、德语、法语、西班牙语、俄语和阿拉伯语。

## 🚀 安装

1. **[下载 Nomi](https://github.com/Jasonsu22/Nomi/releases/latest/download/Nomi-arm64.dmg)**，打开 DMG，把 Nomi 拖进「应用程序」。
2. 打开 Nomi。因为还没有经过 Apple 公证，macOS 会提示「无法验证」，点 **完成**。
3. 打开 **系统设置 › 隐私与安全性**（安装包里有「打开安全设置」快捷入口），在 Nomi 旁边点 **仍要打开**，输入密码确认。

只需要做一次。Nomi 需要 macOS 26 或更高版本，以及 Apple 芯片（M1 或更新）。

<details>
<summary><b>常见问题</b></summary>

**上课时需要联网吗？** 不需要。模型下载一次后，转写和翻译都能离线使用。只有联网搜索或使用 API 模型时才需要网络。

**可以录下我的课吗？** 不同学校和国家的规定不一样。录课前请先查看学校的规定，并征得老师同意。

**收费吗？** Nomi 免费并以 MIT 许可证开源。如果你接入自己的 API 来提问，API 服务商可能会向你收费。

**遇到问题去哪里反馈？** 在这里提交 [issue](https://github.com/Jasonsu22/Nomi/issues)，或在应用里用「帮助 › 联系我们」。

</details>

## 🛠️ 开发者

界面是 SwiftUI，引擎是 Rust。Swift 模块名是 `LectureNoteApp`。

<details>
<summary><b>从源码编译</b></summary>

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

没有付费的 Apple 开发者证书时，每次重新编译后 macOS 都会再要一次钥匙串密码。调试版，以及用 `NOMI_DEV_KEYS=1` 编译的发布版，会在第一次允许后把每个 API 密钥复制到一个只有你能读取的文件里，之后重新编译就不再询问：

```sh
NOMI_DEV_KEYS=1 bash scripts/build-app.sh release
```

开启这个模式时脚本会打印提醒。给别人用的版本请用普通的发布版编译，密钥只保存在钥匙串里。

打包发布时，先不带 `NOMI_DEV_KEYS` 编译，再生成 DMG：

```sh
bash scripts/build-app.sh release
bash scripts/build-dmg.sh
```

`build-dmg.sh` 会生成 `build/Nomi-<版本>-arm64.dmg`，带上 `Design/DMG/` 里的安装背景和第一次打开的说明。第一次运行时会把 [dmgbuild](https://github.com/dmgbuild/dmgbuild) 装进 `build/.dmgbuild-venv`，并拒绝打包调试版和开发密钥模式的版本。把 DMG 以 `Nomi-arm64.dmg` 的名字附到 GitHub Release 上，网站的下载链接就会指向它。

</details>

<details>
<summary><b>模块</b></summary>

| | 模块 | 在哪里 |
| --- | --- | --- |
| 🖥️ | SwiftUI 界面、会议、提问、设置 | `Sources/LectureNoteApp/` |
| 🧪 | Swift 测试 | `Tests/LectureNoteTests/` |
| ⚙️ | 本机引擎 `moxin-engine` | `Backend/moxin-engine/` |
| 🗣️ | 语音识别 worker | `Backend/workers/asr-worker/` |
| 🌐 | 翻译与本机提问 worker | `Backend/workers/llm-worker/` |
| 📦 | 随仓库提供的 ASR 加载器 | `Backend/vendor/qwen3-asr-mlx/` |
| 🎨 | 标志、应用图标、DMG 和 README 图片 | `Design/` |
| 🌍 | 网站 | `website/` |

打包脚本只从 `Backend/target` 复制 `moxin-engine`、`asr-worker`、`llm-worker` 和 `mlx.metallib`。缺任何一个都会停止打包。

编译和运行不需要再克隆 [Moxin-Voice](https://github.com/moxin-org/Moxin-Voice) 或 [Moxin-Studio](https://github.com/moxin-org/Moxin-Studio)。引擎、两个 worker，以及改过的 Qwen3-ASR 加载器已经在 `Backend/` 里。应用自己拉起这个引擎，退出时关掉它。调试构建找 `Backend/target/debug/moxin-engine`；打包后的应用只用包内的那一份。

已经下载的模型权重仍放在 `~/.OminiX/models`。换一台没有这些文件的 Mac 时，在设置里重新下载即可。

</details>

<details>
<summary><b>数据保存在哪里</b></summary>

| 内容 | 位置 |
| --- | --- |
| 会议、分类和会议摘要 | `~/Library/Application Support/Nomi/meetings.json` |
| 资料索引和文件副本 | `~/Library/Application Support/Nomi/sources.json` 与 `sources/` |
| 会议和资料的关联 | `~/Library/Application Support/Nomi/meeting-links.json` |
| 提问记录 | `~/Library/Application Support/Nomi/chats/` |
| 会议问答 | `~/Library/Application Support/Nomi/qa/` |
| 记忆 | `~/Library/Application Support/Nomi/memory.json` |
| 本机模型 | `~/.OminiX/models` |
| API 密钥 | macOS 钥匙串；开发版还会在 `~/Library/Application Support/Nomi/secrets.json` 保存一份副本（只有你能读取） |
| 引擎日志 | `~/Library/Logs/Nomi/engine.log` |

界面语言、外观、麦克风权限、所选本机模型和 API 配置保存在应用的 UserDefaults 里。

</details>

<details>
<summary><b>测试</b></summary>

```sh
swift test
cargo test --manifest-path Backend/Cargo.toml --locked
```

推送到 `main` 或打开拉取请求时，GitHub Actions 会在 macOS 26 上编译并测试 Swift 界面，并在 Linux 上测试不依赖 MLX 的引擎（`voice-core`、`moxin-engine`）。语音识别和翻译 worker 需要 Apple 的 MLX，不在这台 Linux 运行器上编译。

</details>

## 🙏 致谢

实时转写这条路径是从 Moxin-Voice 继续做下来的，谢谢。Nomi 自己的界面和为这个应用写的部分使用 MIT。从别的项目拿来的代码和想法，仍使用那些项目原来的许可。

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
