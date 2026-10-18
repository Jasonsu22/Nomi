# Nomi

macOS 本地课堂转录、翻译与笔记应用。

## 启动

双击 `build/Nomi.app`，或在本项目目录运行：

```sh
open build/Nomi.app
```

后端随应用自动启动，无需另开终端或手动运行服务。

## 编译并打包

需要 Apple Silicon Mac、Swift/Xcode 工具链和 Rust/Cargo。首次编译需要下载依赖。

```sh
bash scripts/build-app.sh
```

此命令同时编译 Swift 界面和 `Backend/` 中的 Rust 后端，并将引擎、语音识别 worker、语言模型 worker 和 MLX Metal 库打包至 `build/Nomi.app`。

源码与构建均不依赖旁边的 Moxin-Voice 或 Moxin-Studio 目录。下载的模型继续保存在 `~/.OminiX/models`，改名项目目录不需要重新下载模型。设置与 API 配置沿用原有存储位置。

应用退出或被强制关闭后，其后端进程组会退出。后端意外退出时会取消就绪状态并尝试重启一次；持续失败时显示引擎错误。启动日志：`~/Library/Logs/Nomi/engine.log`。

模型管理与 API 配置说明见 [docs/local-models.md](docs/local-models.md)。

会议、分类、标题和开始时间保存到 `~/Library/Application Support/Nomi/meetings.json`。详情页点击日期/时间可以修改开始时间。列表页的「开始转录」创建新会议；进入已有会议后，右上角变为「继续录制 / Resume」，内容和段落时间追加到原会议。结束会保存，切换页面不会结束正在进行的录音。
