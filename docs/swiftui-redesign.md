# Nomi 设计与推进文档

> 2026-10-18 从 `Moxin-Voice/docs/swiftui-redesign.md` 搬到这里，之后以这份为准。Moxin-Voice 里的旧副本不再更新。
> 现在推进到哪、接下来做什么、已知问题，先看第 20–22 节。第 1–19 节是原方案，和现状不一致的地方在第 20 节「决定有变的地方」里列出。

把 Moxin Voice 的窗口换成 macOS 原生 SwiftUI，做成一个本机会议 / 讲座笔记应用，产品名 Nomi。版式参考 Google AI Edge Foresight：左侧图标栏、大标题、搜索框、今天的时间轴、右上角开始转录。识别和翻译继续用已经验证过效果的 Qwen3-ASR 1.7B 和 Qwen3.5-2B，模型代码不重写。

## 1. 目标

- 打开就能看到今天的记录，右上角一键开始转录。
- 边听边出字；翻译模型在本机时同时出译文。
- 每段定稿立刻落盘。九十分钟的课中途崩溃，最多丢正在说的半句。
- 能搜索、导出 Markdown。
- 会议按课程分类（英语课、数学课……），能按分类筛选、分组和导出。
- 会议结束后自动出摘要；能针对一场会议、一个分类或全部会议提问，回答附上时间，点一下跳到原文。
- 对话模型有三种来源：本机的 Qwen3.5-2B（和翻译共用一份）、本机已经在跑的推理服务（Ollama、LM Studio、OminiX-API）、云端服务商。云端密钥只存在钥匙串里。
- 界面跟随系统的浅色 / 深色外观自动切换。
- 界面动画在 120 Hz 屏幕上不掉帧。模型计算、网络解码、磁盘写入都不在主线程。

不重写模型，不把约三万一千行的 `screen.rs` 翻译成 Swift。新应用能独立上完一节课之前，Makepad 版继续保留。

## 2. 技术栈

| 层 | 选择 |
|---|---|
| 界面 | SwiftUI，最低 macOS 26 |
| 浮层控件 | Liquid Glass（`glassEffect`、`GlassEffectContainer`） |
| 图标 | SF Symbols |
| 存储 | SwiftData，写入走后台 `ModelActor` |
| 麦克风 | AVAudioEngine |
| 系统 / 单个应用的声音 | Core Audio tap（`CATapDescription`） |
| 本机引擎 | 新 Rust 进程 `moxin-engine`（tokio + axum） |
| 模型进程 | `asr-worker`（Qwen3-ASR-1.7B）、`llm-worker`（Qwen3.5-2B，翻译和本机对话共用），第二阶段加 `tts-worker` |
| 通信 | `127.0.0.1` 随机端口上的一条 WebSocket，带随机令牌 |
| 对话模型 | OpenAI 兼容的 Chat Completions，流式（SSE）。App 用 URLSession 直接调云端和本机服务；本机 Qwen3.5-2B 由引擎提供同一套接口 |
| 密钥 | 钥匙串（Keychain），不进配置文件、UserDefaults 和日志 |

两点取舍：

- Foresight 的图标栏、胶囊按钮、时间轴都不是系统自带控件。SwiftUI 画得出来，但要做成我们自己的组件库（第 5、6 节）。`NavigationSplitView` 给的是 Finder 式的列表侧栏，长不成那样。
- 系统声音不用 ScreenCaptureKit。它只要音频也得申请「屏幕录制」权限，还要求有显示器。Core Audio tap 只申请「系统音频录制」，并且可以只录某一个应用，比如正在放网课的浏览器。Info.plist 要加 `NSAudioCaptureUsageDescription`。

部署目标是当前这台 macOS 27。最低版本定为 macOS 26，是因为 Liquid Glass 的接口从 26 开始才有。以后要支持 macOS 15，玻璃部分用 `if #available(macOS 26, *)` 退回 `.regularMaterial`。

## 3. 进程与职责

```
LectureNote.app (SwiftUI)
  界面 · 权限 · 采集 · 重采样到 16 kHz · 存储 · 对话客户端
        │                                     │
        │ ws://127.0.0.1:{port}/v1/session     │ OpenAI 兼容接口（HTTPS / 本机 HTTP）
        │ http://127.0.0.1:{port}/v1/…         ▼
        │ Authorization: Bearer {token}      云端服务商、Ollama、LM Studio、OminiX-API
        ▼
moxin-engine (Rust，不画界面，不链接 MLX，不访问外网)
  切句（VAD） · 会话 · 合并文字 · 决定何时提交和翻译 · 时间戳 · 本机对话排队
        │                         │
        │ stdin / stdout 帧协议     │
        ▼                         ▼
asr-worker                  llm-worker
~/.OminiX/models/           ~/.OminiX/models/
qwen3-asr-1.7b              Qwen3.5-2B-MLX-4bit
                            翻译（优先）+ 本机对话
```

云端和本机服务由 App 直接调用，不经过引擎：密钥只在 App 进程和钥匙串里，引擎只监听 `127.0.0.1`，不需要出网。本机的 Qwen3.5-2B 也走同一种 OpenAI 兼容接口，所以 App 只有一个对话客户端（第 17 节）。

### 新路径不经过 Dora

1. 现在每次开始翻译都要新起一条 Dora 数据流：拉起节点进程、重新加载模型。`moxin-dora-bridge` 在 macOS 上还固定先等 5 秒再连接（`dispatcher.rs`）。按下开始到出字至少要好几秒。新路径的 worker 常驻，模型只加载一次，开一场会话只是一条消息。
2. 之前遇到的「Bridge already connected」，是 Makepad 版在数据流重启后，麦克风动态节点还停在已连接状态（它没响应 Dora 的 Stop）。新路径没有动态节点，这类问题不存在。
3. 打包不必再带 `dora` 命令行、协调器和守护进程。

ASR 和翻译分成两个进程，是因为 MLX 不能在同一进程里并发推理（ominix-api 的启动日志也写明了这一点），现在的两个 Dora 节点也是各占一个进程、一个推理线程。分开之后，翻译慢一点不会挡住下一句识别。

### 翻译和本机对话共用一个 llm-worker

原来的 `translate-worker` 改名 `llm-worker`。同一份 Qwen3.5-2B 既做实时翻译，也回答本机对话（提问、摘要、建议）。

- 权重只加载一次（1.72 GB）。翻译、对话各开一个进程会多占约 2 GB，两份模型还会在 GPU 上互相抢。
- 能共用是因为 `qwen3-5-35b-mlx`（OminiX-MLX `6aac996`）的缓存不绑在模型上：`Model::forward(&inputs, &mut cache)`、`HybridCache`、`sample` 都是公开的。每条序列（一次翻译或一次对话）有自己的 `Vec<HybridCache>`，worker 可以在 token 之间换序列。现在翻译节点用的 `Generate` 迭代器全程借着 `&mut Model`，所以 worker 要自己写解码循环。`Generate` 本身只有几十行：预填充、采样、`async_eval` 预取下一个 token、逐个解码，照着写即可。
- 调度：翻译优先。对话每解码一个 token、预填充每送入 512 个 token，检查一次翻译队列，有翻译就先做完再回来。同一时间只跑一条对话，其余按优先级排队：提问先于后台任务（摘要、分类和标题建议）。
- 分块预填充（带着缓存分几段送入提示词）要先验证：输出和一次送入完全一致才用。不一致就整段预填充，同时把本机对话的输入限制在 4k token 以内，翻译最多多等一次预填充。
- 每次翻译、每次对话结束都调 `mlx_clear_cache()`，和现在的节点一致，否则 Metal 缓冲池会越积越大。
- 对话模板默认关闭思考：`chat_template.jinja` 只有在 `enable_thinking` 为真时才打开 `<think>`。翻译照旧在系统提示词里加 `/no_think`。

### 不用 OminiX-API 跑实时链路

Moxin-Studio 的本机模型全部走 OminiX-API：`localhost:8080` 上的 OpenAI 兼容服务，用 `/v1/models/load` 动态加载模型。2026-10-18 在这台机器（M5，24 GB）上实测过，结论是实时转录不依赖它：

- 装在 `~/.local/bin/ominix-api` 的 v1.0.0+d12a7e1 启动时能扫到两个模型（日志里都是 Ready），但可执行文件旁边没有 `mlx.metallib`，加载任何模型都直接崩溃（「Rust cannot catch foreign exceptions」）。
- 把 metallib 放到旁边之后不再崩溃，但它把 `model_type: qwen3_5` 交给了 Qwen3 后端，返回「Failed to load Qwen3 model」。这一版跑不了 Qwen3.5-2B。
- 它只有一个推理线程，ASR 和翻译放进去会互相排队。
- ASR 的语言、上下文提示和每次识别后的 `mlx_clear_cache()` 都控制不了；端口固定 8080，和 Moxin-Studio 共用。

OminiX-API 仍然可以作为对话的「本机服务」（第 17 节）：用户装了能用的版本、想用更大的本机模型时，从 `~/.OminiX/api_url` 读地址。

### 逻辑来源：迁移，不重写

- 切句：搬 `moxin-dora-bridge/src/widgets/aec_input.rs` 的 `VadState`，包括渐进式片段（说话中每 1500 ms 送一次未完成片段）和 8 秒片段上限。
- 合并与提交：搬 `dora-qwen35-translator` 的 `TranscriptBuffer` 和提交规则。稳定文字满 10 个字符后，在最后一个逗号、句号、问号、感叹号或分号处切出一段，每 500 ms 检查一次；9 秒没有新的识别结果，就把剩下的全部提交。
- 搬的时候顺手修一个英文问题：每段识别结果进来时先 `trim` 过，`update_from_chunk` 再把相邻两段直接 `push_str` 拼起来。中文没影响，英文会把前一段最后一个词和下一段第一个词粘在一起（「attentionit」）。现有测试全是中文，所以没暴露。源语言用空格分词时，在两段之间补一个空格，并补英文测试。
- 识别：`asr-worker` 调 `qwen3-asr-mlx` 的 `transcribe_samples_with_config`，`max_tokens` 1024，和现在的节点一致。语言参数按会议的源语言传（`"Chinese"`、`"English"`……），不再固定中文。
- 翻译：`llm-worker` 用现在 `translation_worker_loop` 的提示词和参数（温度 0，最多 256 token），翻译之间不并发。

这些代码先抽成共享库 `voice-core`，Dora 节点和新 worker 同时依赖它，迁移期间 Makepad 版照常能跑。

### 引擎由 App 管

- App 启动后在后台拉起 `moxin-engine --port 0 --asr-model <目录> --llm-model <目录>`。引擎在 stdout 第一行输出 `{"port":…,"token":"…"}`，之后的连接都带这个令牌。不用固定端口：8080 是 ominix-api 的。
- 第一帧画完后预热 ASR，用户按开始时不再等模型加载。旧日志里 Qwen3-ASR-1.7B 从开始加载到就绪约 0.7 秒（文件已在系统缓存里时）。
- 引擎意外退出时自动重启。已定稿的段落在 Swift 侧，不受影响，只丢正在说的那半句。
- `llm-worker` 在没有会话、也没有对话请求 10 分钟后卸载。系统内存紧张时先卸载它，再卸载 ASR。
- App 退出时结束引擎和所有 worker。

## 4. 引擎接口

HTTP 接口都要带同一个令牌：

| 方法 | 路径 | 作用 |
|---|---|---|
| GET | `/health` | 引擎是否在跑 |
| GET | `/v1/status` | 两个模型各自的路径、文件是否完整、是否已加载、占用内存、最近一次错误 |
| POST | `/v1/models/{asr,llm}/load`、`/unload` | 设置里手动加载、卸载 |
| GET | `/v1/models` | OpenAI 格式的模型列表，只有一项 `qwen3.5-2b`，给对话客户端用 |
| POST | `/v1/chat/completions` | OpenAI 兼容的对话接口，支持 `stream: true`，规则见第 17 节 |
| POST | `/v1/speech` | 第二阶段：文字合成 wav |

转录只走一条 WebSocket：`/v1/session`。音频和事件在同一条连接上，顺序有保证，也不用每几十毫秒发一次 HTTP 请求。

客户端发给引擎：

- 文本帧 `{"type":"start","source":"microphone","sourceLanguage":"zh","targetLanguage":"en"}`
- 二进制帧：float32 小端 PCM，16 kHz，单声道，每帧 20–100 ms
- 文本帧 `{"type":"stop"}`：刷出最后一段，然后发 `state: idle`

引擎发给客户端：

```json
{"type":"state","value":"loading","asr":"ready","translator":"missing"}
{"type":"tail","text":"今天我们讲注意力机制，它的","start":12.4,"revision":41}
{"type":"commit","id":7,"source":"今天我们讲注意力机制，","translation":"Today we'll cover attention,","start":12.4,"end":15.1,"tail":"它的"}
{"type":"level","rms":0.021}
{"type":"error","code":"translator_missing","message":"…"}
```

规则：

- `state.value` 只有 `loading`、`listening`、`stopping`、`idle` 四种。`translator` 是 `ready`、`missing` 或 `off`（目标语言为 `none`）。
- `tail` 是还没提交的那一截，每次整段替换，不追加。`tail.start` 是这一截开始说话的时间，客户端用它判断要不要另起一段。
- `commit` 只追加。`id` 在会话内递增，存储和去重都用它。事件里带上提交后剩下的 `tail`，客户端在同一个动画里更新两者，文字不会闪。
- 提交点可以是逗号，所以一次提交常常只有半句。界面按段落显示（第 6 节），不是一次提交占一行。
- 译文和提交一起到达，这和现在翻译节点的行为一致：译文返回之前，原文一直显示在 tail 里，读者不用等。
- 翻译不可用时 `translation` 是空字符串。
- `start`、`end` 是相对会话开始的秒数，由引擎按采样数计算：每个片段记录自己的采样区间，提交时按字符偏移映射回片段。
- `level` 每秒最多 20 次。

## 5. 视觉设计

### 方向

照 Foresight 的版式和节奏：带一点蓝的浅灰底、白色大卡片、深海军蓝主按钮、浅蓝选中态、大量留白。区域之间靠底色和卡片区分，不画分隔线。Liquid Glass 只用在浮在内容上面的控件：开始 / 录音胶囊、「回到最新」、置顶字幕。转写正文要长时间阅读，放在不透明的卡片上，保证对比度。

### 外观跟随系统

- 所有颜色都是动态色：同一个令牌有浅色、深色两个值，系统切换外观时界面立刻跟着变，不用重启。
- 应用里不做单独的主题开关。环境变量 `LECTURE_COLOR_SCHEME=light|dark` 只用来截图和测试，不给用户用。
- 玻璃、材质、SF Symbols 和应用图标都跟着系统外观走。
- 现状：系统为深色时启动，当前构建显示的就是深色界面；运行中切换外观还没验证过，第 1b 步也没做到，放进第 1c 步的验收。

### 颜色

浅色值取自 Foresight 截图，深色值按同一色相压暗。颜色写在代码里（`Color(light:dark:)` 包一层动态 `NSColor`），不用 Asset Catalog：SwiftPM 命令行构建也能用，改色只改一处。

| 名称 | 浅色 | 深色 | 用途 |
|---|---|---|---|
| `canvas` | #E9EDF6 | #0F1216 | 窗口底 |
| `surface` | #FFFFFF | #181C21 | 卡片、搜索框 |
| `surfaceInset` | #EBF0F6 | #1F242B | 卡片里的次级面板 |
| `selection` | #C2E8FF | #1D3A50 | 侧栏选中块、选中的标签和分类、录音胶囊 |
| `onSelection` | #17587E | #CDEBFF | 选中块上的图标和文字 |
| `accent` | #004A77 | #7CC4F2 | 开始按钮、进行中的小点 |
| `onAccent` | #FFFFFF | #0F1216 | 开始按钮上的字 |
| `accentSoft` | #E3F3FF | #1A2C3A | 「现在」胶囊、进行中段落的底色 |
| `textPrimary` | #111418 | #E6E8EB | 正文、标题 |
| `textSecondary` | #5E6670 | #9AA3AD | 译文、时间、说明 |
| `outline` | #B0B4BD | #3A414A | 「新建分类」的虚线框 |
| `separator` | #D5DCE6 | #2A3038 | 只用在卡片内部，比如表头下面 |

Foresight 的次要文字更浅（约 #9CA0A9），在白底上对比度不到 3:1。这里保留更深的 `textSecondary`。

分类用 8 个固定颜色。每个颜色有一个墨色（图标、文字），底色是墨色加透明度（浅色 14%，深色 22%）：

| 颜色 | 浅色墨色 | 深色墨色 |
|---|---|---|
| 蓝 | #2F6FDE | #7FA8F5 |
| 绿 | #2E9D5B | #6CCB92 |
| 橙 | #E07B24 | #F2A65E |
| 紫 | #7B5CD6 | #A99AF0 |
| 粉 | #D6497C | #F08CB0 |
| 青 | #1F9AA6 | #6CCBD3 |
| 黄 | #C99A06 | #E8C34A |
| 灰（未分类） | #6B717B | #9AA3AD |

### 字体

用系统字体，中文会自动用苹方。不打包 Foresight 用的 Google 字体。

| 名称 | 规格 | 用途 |
|---|---|---|
| `pageTitle` | 28 pt medium | 「会议」「资料」，比原来的 semibold 轻一档，接近 Foresight |
| `detailTitle` | 20 pt semibold | 会议详情的标题 |
| `sectionTitle` | 17 pt semibold | 「今天」、分类分组名 |
| `body` | 15 pt regular，行距 5 | 转写原文 |
| `secondary` | 13 pt regular | 译文、元信息 |
| `caption` | 11 pt medium | 侧栏文字、时间戳、胶囊 |

时间一律 24 小时制（`03:53`），加 `.monospacedDigit()`，数字变化时宽度不跳。界面是中文，不出现「AM / PM」，语言名也写中文（「英文」而不是「English」）。

### 形状与布局

- 间距只用 4、8、12、16、24、32、48。
- 圆角：按钮、胶囊、搜索框用 `Capsule`；大卡片 16；卡片里的面板 12；小标签 8。全部 `.continuous`。
- 阴影只给浮层，内容面靠底色区分层次。
- 顶栏和侧栏之间、侧栏和内容之间都不画分隔线。
- 列表类页面内容左对齐：左边距 48 pt，右边距 32 pt，最宽 1200 pt，再宽才居中。不再固定居中 880 pt。
- 转写正文在卡片里最大行宽 720 pt。
- 详情页的卡片占满剩余高度。卡片本身不滚动，内容在卡片里滚动，圆角一直在原位。

### 品牌与图标

- 当前版本是 `LectureNoteApp/Design/logo.svg`（矢量母版）和 `logo.png`（1024 px，透明底）：深海军蓝圆角方形上直接放白色的波形竖条和两条文字横线，意思是「说的话变成笔记」。它由生成的草图 `logo-concept-bubble.jpg` 改来，去掉了对话气泡，图形放大到圆角方形宽度的约六成。
- 按 Apple 的 macOS 图标网格画：1024 画布，824 的连续圆角方形（圆角 185.4），和 `RoundedRectangle(style: .continuous)` 是同一条路径。
- 蓝色沿用草图的 #15498B，比开始按钮的 `accent`（#004A77）亮一些。要完全一致时只改 SVG 里的一个颜色。
- 32 px 开始变挤，16 px（Finder 列表视图）时竖条糊在一起。小尺寸单独出一版：只留三根竖条，去掉文字横线。
- 第 1b 步先用 `iconutil` 生成 `AppIcon.icns` 放进应用包。之后换成 Xcode 工程签名时，改用 Icon Composer 做分层图标，分别调好默认、深色、着色、透明四种外观。
- 顶栏左上角放 20 pt 的图标加「Nomi」字样，和 Foresight 的品牌位一致。「关于」里用大图标。图标用 `Design/brand-final-v1` 里白底的丝带 N。

### 无障碍

- 打开「减弱动态效果」时，所有位移动画换成 0.2 秒淡入淡出。运行中改这个设置要立即生效：读系统的 `accessibilityReduceMotion` 环境值，不要只在启动时读一次。要自己监听的话，`NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` 只发到 `NSWorkspace.shared.notificationCenter`，不发到 `NotificationCenter.default`。
- 打开「降低透明度」时，玻璃控件改用 `surface` 实色。
- 打开「增强对比度」时，`textSecondary` 加深一档。
- 每个组件的预览同时看浅色和深色。

## 6. 页面

### 现有能力的去向

| 现在的页面 | 新位置 |
|---|---|
| 实时翻译 | 会议详情里的原文和译文，加置顶字幕 |
| 语音合成 | 段落上的「朗读」，调用 `/v1/speech` |
| 声音库、声音克隆 | 设置里的「声音」，排在转录闭环之后 |
| 历史 | 会议列表本身 |
| 关于 | 设置底部 |

### 窗口与外壳

- 窗口用 `.windowStyle(.hiddenTitleBar)`，根视图背景铺 `canvas` 并 `.ignoresSafeArea()`。
- 顶栏通栏，从窗口最左边开始，压在侧栏上面（Foresight 的做法）。它在交通灯下面一行，高 52 pt：左边是图标、「LectureNote」和状态胶囊（「本机 · 模型就绪」或「准备中」，点一下打开设置里的「模型」），右边是开始按钮。顶栏背景加 `WindowDragGesture()`，保证能拖动窗口。隐藏标题栏后，安全区已经让出交通灯那一行，顶栏直接接在下面，不要再另加拖动条。开始按钮不放进系统工具栏：macOS 26 会给工具栏按钮自动套玻璃底和分组，我们自己的变形动画不好控制。
- 左侧图标栏宽 72 pt，在顶栏下面，图标在上、文字在下：会议、提问、资料；设置和帮助放在底部。统计页不做（第 12 节）。
- 选中项背后是一块 `selection` 浅蓝圆角块，图标和文字用 `onSelection`，切换时圆角块滑过去。
- 页面切换不用 `NavigationStack` 的推入动画。外壳自己持有当前页，新页面淡入并略微上移（第 7 节「切换页面」）。

### 会议页

- 标题行：大标题「会议」；右侧是「导出」胶囊和「时间 / 分类」两段切换（决定怎么分组）。原来的「上次导入」去掉，导入放到资料页。
- 搜索框是胶囊形，高 40 pt，占满内容宽度。能搜标题、正文和分类名，和下面的分类筛选同时生效。
- 搜索框下面是一排分类标签：「全部 12」「英语课 5」「数学课 4」「未分类 3」，最后是虚线框的「＋ 新建分类」（Foresight 里「+ Add label」的样子）。每个标签前面有分类颜色的小圆点。选中的标签是 `selection` 底，切换时底块滑过去。
- 按时间分组（默认）：「今天」下面先是「现在 · 14:37」分隔线：一条细线，中间一个 `accentSoft` 胶囊，时间由 `TimelineView(.everyMinute)` 驱动。今天的会议按开始时间倒序排在分隔线下面，进行中的那场排第一；再往下是「更早」。
- 按分类分组：每个分类一组，组名前面是分类颜色的小圆点，后面是场数；组内按时间倒序；没有会议的分类不显示。这个模式下没有「现在」分隔线。
- 会议卡片：左边 32 pt 圆形图标，用分类的底色和图标；中间是标题和「03:53 · 30 分钟 · 中文 → 英文」；右边是时长。进行中的卡片右边换成一个缓慢呼吸的 `accent` 小点和「进行中」。
- 卡片右键菜单：打开、重命名、移到分类、导出、删除。
- 点卡片进入会议详情，卡片底板展开成详情容器。
- 「导出」用保存面板把当前筛选出的会议存成 Markdown 文件；选了某个分类就只导出这个分类。不再是悄悄复制到剪贴板。

### 分类

- 一场会议属于零个或一个分类，没有分类的归在「未分类」。
- 新建：点「＋ 新建分类」弹出小浮层，填名字，选颜色和图标，回车创建并选中。图标从 8 个里挑：`character.book.closed`（语言）、`function`（数学）、`atom`（物理）、`flask`（化学）、`globe.asia.australia`（文史地）、`laptopcomputer`（计算机）、`music.note`（艺术）、`book.closed`（默认）。
- 修改：分类标签的右键菜单里改名、换颜色和图标、删除。删除前确认，这个分类下的会议移到「未分类」，不删会议。
- 归类有三个入口：卡片右键「移到分类」、详情页头部的分类胶囊、详情右栏的「信息」。
- 新会议的分类：开始转录时如果正在看某个分类，新会议直接归到这个分类；否则是「未分类」，之后在详情页改。
- 上次选的筛选和分组方式记住，下次打开还是这样。
- 第 5 步做：用默认对话模型根据前几分钟的转写建议分类（「这节课像是数学课，归进去吗？」），只做建议，由用户确认（第 18 节）。

### 会议详情 / 转录

版式照 Foresight 的会议页：头部直接在底色上，下面左右两张白卡片。

- 头部：圆形返回按钮（32 pt，白底）；分类图标圆（32 pt，分类底色）；标题（`detailTitle`，可直接改）。标题下面一排小胶囊：日期「10月18日 周日」、时间「03:53–04:23」、分类（点开可改）、语言「中文 → 英文」。进行中的会议，结束时间换成跟着走的时长。
- 左卡片「转写」，占大部分宽度。卡片右上角有字号 A− / A+、「段内 / 对照」切换和「复制全文」。内容在卡片里滚动。
- 右栏宽 340 pt，可以关掉（右上角的 ×，头部有按钮再打开）。三个标签：「信息」「提问」「摘要」。「信息」放分类、输入源、语言、时长、导出、删除，第 1b 步就做。「提问」「摘要」第 5 步接上对话模型（第 18 节），在那之前只显示一句说明，不放能点但没反应的按钮。选中的标签用 `selection` 浅蓝胶囊，和侧栏、分类标签一致。窗口窄于 1100 pt 时右栏默认收起。
- 正文是一条段落流。连续的几次提交拼成一个段落：停顿超过 2 秒就另起一段；段落写满之后（中文约 200 字，英文约 600 个字符）遇到句末标点也另起一段。中文句末标点是「。！？」，英文是「. ! ?」。
- 拼接按语言来：中文、日文直接接上；英文这类用空格分词的语言，两次提交之间补一个空格，边界上已经有空白就不补。原文按源语言拼，译文按目标语言拼。
- 每段左侧是 48 pt 宽的时间戳栏，右侧是原文，原文下面是这一段的译文。原文和译文放在同一段里，不分左右两栏：译文按提交和原文一一对应，放在一起永远对得齐，窗口窄的时候也不挤。
- 最后一段是进行中的段落，带 `accentSoft` 底。已提交的文字用 `textPrimary`，后面紧接着正在说的 tail，用 `textSecondary`，实时替换。
- 提交时，那部分文字在原位从 `textSecondary` 变成 `textPrimary`，位置不动；这次的译文接在本段译文后面，译文块的高度随之展开。段落结束时底色褪掉。
- 「对照」模式（窗口宽于 1100 pt 时可用）：原文和译文左右并排，仍然按段落成行。
- 翻译模型不在时，只在转写卡片顶部显示一次说明「放入 Qwen3.5-2B 后显示译文」和「在 Finder 中打开」，不在每段重复。
- 滚动：进行中的会议停在底部并自动跟随。用户往上滚超过一屏就停止跟随，右下角出现「回到最新」玻璃胶囊，点一下滚回底部并恢复跟随。已经结束的会议从开头显示。

### 开始按钮与录音胶囊

按下「开始转录」后，按钮变宽，变成录音胶囊（Foresight 录音时的样子）：计时、点阵波形、暂停、停止。第 6 步再加「置顶字幕」按钮，对应 Foresight 胶囊最右边的展开按钮。两种状态放在同一个 `GlassEffectContainer` 里，共用一个 `glassEffectID`，是同一块胶囊变形过去，而不是一个消失、另一个出现。

会话状态由 `SessionState` 驱动，和引擎的 `state` 对应：

| 状态 | 外观 |
|---|---|
| 空闲 | 深海军蓝 `accent` 胶囊「开始转录」，白字 |
| 准备中 | 同一个胶囊，`waveform` 图标做 `.pulse`，文字「准备中」 |
| 收听中 | 变宽变成浅蓝 `selection` 胶囊，`onSelection` 色的计时和点阵波形 |
| 已暂停 | 同上，波形停住变淡，暂停键变成继续 |
| 停止中 | 胶囊收窄，显示「正在保存」，完成后变回开始按钮 |

点阵波形：约 24 个圆点排成一行，每个点的高度对应最近 1.2 秒里一小段时间的音量，新的从右边进来。用 `TimelineView(.animation(minimumInterval: 1/60, paused: isPaused))` 驱动 `Canvas` 画，最高 60 帧，只重画胶囊里这一小块，不触发布局。打开「减弱动态效果」时点不做缓动，直接跳到新高度。出错时回到空闲，并在胶囊下方显示一行说明。

### 置顶字幕

单独的 `Window` 场景：`.windowStyle(.plain)`、`.windowLevel(.floating)`，内容加 `WindowDragGesture()` 可以拖动。背景是超薄材质，透明度由设置里的滑杆控制。

要盖在全屏的网课视频或演示上，还要通过 `NSWindow` 把 `collectionBehavior` 设成包含 `.canJoinAllSpaces` 和 `.fullScreenAuxiliary`。另外提供「点击穿透」开关，打开后字幕不挡鼠标。

字幕只显示两行：上一行是最近一次提交的原文和译文，下一行是正在说的话。新的提交从下方淡入，旧的向上淡出。

### 其他页

- 提问：跨会议提问。范围可以选全部、某个分类（「在英语课里找」）或某几场。回答附上会议名和时间，点一下打开那场会议并跳到那一段。只问一场时用详情右栏的「提问」。转写放得进模型上下文就整场给，放不进就先检索相关段落（第 18 节）。
- 资料：照 Foresight 的 Knowledge Sources。大标题加「导入」胶囊，下面是胶囊搜索框和同一套分类标签，再下面是一张白卡片里的表格（名称、所属会议、分类、时间）。第一版只列每场的音频和导出文件，音频可播放，点段落跳到对应时间。课件导入放下一轮。
- 设置：输入源、语言、模型（语音识别、翻译、对话模型和服务商，第 17 节）、权限状态、声音、关于。外观没有选项，跟随系统。识别的源语言默认取 macOS 首选语言，能对上的有中文、英文、日文、韩文、德文、法文、西班牙文、俄文、阿拉伯文，对不上就用英文。目标语言默认是配对的另一边：系统是中文就译成英文，系统是英文就译成中文，其余译成英文。两处都可以改；源语言可以选回「跟随系统」，目标语言可以选「不翻译」。用户改过目标语言之后，换系统语言不再改它。界面文案、日期和时间仍然是中文，不跟区域格式走。

## 7. 动画

### 动画令牌

```swift
enum Motion {
    static let tap    = Animation.snappy(duration: 0.18)
    static let page   = Animation.smooth(duration: 0.22)
    static let layout = Animation.smooth(duration: 0.32)
    static let morph  = Animation.bouncy(duration: 0.42, extraBounce: 0)
    static let fade   = Animation.easeOut(duration: 0.16)
}
```

页面里只用这五个。打开「减弱动态效果」时，五个令牌都返回 `.easeInOut(duration: 0.2)`，位移类过渡换成纯透明度。

### 切换页面

侧栏切换和页内标签切换（详情右栏、资料页）用同一个过渡：新页面从下方 8 pt 处淡入并上移到位，0.22 秒；旧页面 0.1 秒淡出，不和新页面叠在一起。动画很短，只是让人感觉到「换了一页」，不拖慢操作。

```swift
extension AnyTransition {
    static let pageEnter = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 8)).animation(Motion.page),
        removal: .opacity.animation(.easeOut(duration: 0.1))
    )
}
```

页面容器按当前页加 `.id(page)`，保证切换时是旧页移除、新页插入，而不是同一个视图原地更新。打开「减弱动态效果」时只淡入，不上移。

### 动画清单

| 交互 | 做法 | 令牌 |
|---|---|---|
| 切换页面、页内标签 | `pageEnter` | `page` |
| 侧栏选中块滑动 | 选中块用 `matchedGeometryEffect(id: "rail", in: ns)` | `tap` |
| 分类标签选中块滑动 | 同上，`id: "category"` | `tap` |
| 按分类筛选、切换分组 | 卡片按会议 id 增删，`.opacity.combined(with: .offset(y: 8))`，其余卡片顺势移动 | `layout` |
| 开始按钮变录音胶囊 | `GlassEffectContainer` 加 `glassEffectID`，深蓝变浅蓝、变宽 | `morph` |
| 进入会议 | 列表留在 `ZStack` 里，只是淡出，所以返回时滚动位置还在。详情淡入并上移 8 pt。不用 `matchedGeometryEffect`：卡片和详情同时在树上时，匹配会把详情锁在卡片的位置上 | `layout` |
| 新会议出现在时间轴 | 插在「现在」分隔线下，下面的卡片顺势下移 | `layout` |
| 新段落出现 | `.opacity.combined(with: .offset(y: 8))` | `layout` |
| tail 文字更新 | 不加动画，直接替换 | 无 |
| 提交 | 原文原位变色，`.contentTransition(.interpolate)`；译文块高度展开，新译文淡入 | `layout` |
| 段落结束 | `accentSoft` 底色褪掉 | `fade` |
| 「现在」时间变化 | `.contentTransition(.numericText())` | `fade` |
| 「回到最新」出现 | `.move(edge: .bottom).combined(with: .opacity)` | `tap` |
| 右栏收起、展开 | 右栏滑出并淡出，转写卡片变宽。正文列宽固定（最大 720 pt），卡片变宽时文字不重新换行 | `layout` |
| 录音波形 | `TimelineView` 驱动 `Canvas` 逐帧画 | 无 |
| 字幕换段 | 新段淡入，旧段上移淡出 | `layout` |
| 悬停 | 卡片和胶囊底色变化 | `fade` |
| 流式回答、流式摘要 | 文字直接追加，不加动画；每 50 ms 合并一次增量 | 无 |
| 分类、标题建议胶囊出现和消失 | `.opacity.combined(with: .scale(scale: 0.96))` | `tap` |
| 点引用跳到段落 | 滚动到那一段，那一段的 `accentSoft` 底色闪一下再褪掉 | `layout`、`fade` |

SwiftUI 的 `navigationTransition(.zoom)` 在 macOS 上不可用，所以「进入会议」用 `matchedGeometryEffect` 自己做。「现在」胶囊也不需要 `matchedGeometryEffect`：它的位置由数据决定，列表变化时跟着布局动画走就行。

### 不掉帧的规则

1. 主线程只更新界面状态。WebSocket 接收和 JSON 解码在后台任务里做，解析完再切回主线程。
2. 音频回调线程不碰界面，也不碰 SwiftData。采集、重采样、发送走一条 `AsyncStream`。
3. 状态拆细：`LiveTranscript`（段落和 tail）、`LevelMeter`（电平）、`SessionState`（状态机）是三个独立的 `@Observable`。电平每秒刷新 20 次，只会重画录音胶囊。
4. 客户端把 tail 合并到最多每 100 ms 刷新一次。
5. 转写用 `ScrollView` 加 `LazyVStack`，段落用客户端分配的段落序号作为身份。只有 tail、还没有提交的段落也已经有序号，第一次提交时不会被当成新行重新插入。不用 `List`，行里不放 `GeometryReader`，不用 `AnyView`。
6. 进行中的会议不绑 `@Query`，界面读内存里的 `LiveTranscript`。SwiftData 写入在后台 `ModelActor` 里做，每提交一段写一次。
7. 动画只写在状态变化的地方（`withAnimation(Motion.layout) { … }`），不对整页挂 `.animation`，也不用定时器逐帧改坐标。唯一逐帧画的是录音波形，它在 `Canvas` 里画，不改布局。
8. 尺寸动画只作用在底板上。进入会议时详情直接是最终尺寸，只做淡入，文字不跟着缩放重新换行。收起、展开右栏时正文列宽不变。
9. 搜索输入防抖 150 ms，筛选结果在一次刷新里只算一遍。

## 8. 数据

SwiftData 里三种对象：

- `Category`：`id`、名字、颜色序号、图标名、排序。
- `Meeting`：`id`、标题、开始时间、时长、输入源、语言对、分类（可空；删除分类时置空）、音频文件的相对路径。
- `Segment`：一次提交。所属会议、会话内的 `id`、段落序号、`start`、`end`、原文、译文。段落序号在提交时就定下来存进去，重新打开会议时分段和录制时一样。

音频由 Swift 侧边采集边写成 AAC（`.m4a`，单声道 64 kbps，一小时约 29 MB），存在 `~/Library/Application Support/LectureNote/meetings/{id}/audio.m4a`。

每提交一段就写一条 `Segment`，不是停止后一次写入。

第 1b 步的分类先放在内存里，带几条示例数据；第 3 步和会议、段落一起换成 SwiftData。

第 5 步加的对话相关数据：

- `Summary`：所属会议、Markdown 正文、服务商和模型、生成时间、生成时的提交数。转写之后又有新提交时，摘要上方提示「转写有更新，重新生成」。
- `ChatTurn`：一问一答。所属会议（跨会议提问时为空，另记范围）、问题、回答、引用（会议 id 加段落序号）、服务商和模型、时间。思考内容不存。
- `Meeting` 加两个可空字段：建议的分类、建议的标题，以及「用户已忽略建议」的标记。
- `Category` 加可选的术语表，以后给 ASR 当上下文提示（第 17 节）。

服务商配置（名称、地址、模型、上下文长度、开关、是否允许发送会议内容）存在 `~/Library/Application Support/LectureNote/providers.json`，文件里只记「有没有密钥」，密钥本身只在钥匙串。

## 9. 工程结构

`LectureNoteApp` 实际用的是 SwiftPM（`Package.swift`），不是 Xcode 工程：命令行就能编译和跑测试，Cursor 里改起来也方便。要签名和公证时再加 Xcode 工程。

**现在的结构（2026-10-18）：** 前端和后端都在 `LectureNote/Nomi` 这一个仓库里，不再依赖旁边的 Moxin-Voice 或 LectureNoteApp 目录。

```
Nomi/
├── Package.swift                      SwiftPM 包，模块仍叫 LectureNoteApp
├── Sources/LectureNoteApp/            App、Shell、Meetings、Categories、Live、Engine、
│                                          Models、Pages、Support、DesignSystem、Resources
├── Tests/LectureNoteTests/
├── Backend/                           Rust workspace
│   ├── crates/voice-core/             VAD、TranscriptBuffer、提交规则、帧协议、语言
│   ├── moxin-engine/                  会话、HTTP / WebSocket、worker 管理
│   ├── workers/asr-worker/            Qwen3-ASR
│   ├── workers/llm-worker/            Qwen3.5 / Qwen3：翻译和问答
│   └── vendor/qwen3-asr-mlx/
├── Design/Brand/                      AppIcon.icns 等
├── scripts/build-app.sh               一条命令编 Rust + Swift，打出 build/Nomi.app
└── docs/                              本文档、local-models.md
```

下面是原方案里的结构，留作对照：

```
LectureNote/
├── LectureNoteApp/                    SwiftPM 包，独立 git 仓库
│   ├── Package.swift
│   ├── Design/                        logo.svg 母版和草图，之后放 Icon Composer 文件
│   ├── scripts/build-app.sh           组装 build/LectureNote.app（第 1b 步加）
│   ├── Sources/LectureNoteApp/
│   │   ├── App/                       LectureNoteApp、AppModel
│   │   ├── DesignSystem/
│   │   │   ├── Colors.swift           动态色令牌
│   │   │   ├── Typography.swift
│   │   │   ├── Spacing.swift
│   │   │   ├── Motion.swift           动画令牌、pageEnter
│   │   │   └── Components/            RailItem、PillButton、SearchField、
│   │   │                                  StatusChip、NowDivider、MeetingCard、
│   │   │                                  ParagraphRow、RecordingCapsule、
│   │   │                                  DotWaveform、CategoryChip、
│   │   │                                  JumpToLatestPill
│   │   ├── Shell/                     AppShell、Rail、TopBar
│   │   ├── Meetings/                  MeetingListView、MeetingDetailView、
│   │   │                                  DetailSidePanel
│   │   ├── Categories/                Category、CategoryPalette、CategoryEditor
│   │   ├── Live/                      LiveTranscript、SessionState、LevelMeter
│   │   ├── Engine/                    TranscriptionEngine（协议）、ReplayEngine，
│   │   │                                  之后加 LiveEngine、EngineProcess、EngineStatus
│   │   ├── LLM/                       第 4 步：ChatProvider、ProviderStore、Keychain、
│   │   │                                  OpenAICompatibleClient（SSE）、
│   │   │                                  TranscriptContext（切块、检索、引用）、Prompts
│   │   ├── Pages/                     提问、资料、设置、帮助
│   │   ├── Models/                    Meeting、示例数据，第 3 步换成 Store/
│   │   ├── Support/                   时间和语言格式化
│   │   └── Fixtures/                  事件日志 *.jsonl
│   └── Tests/LectureNoteTests/
└── Moxin-Voice/                       现有仓库，swiftui-redesign 分支
    ├── crates/voice-core/             VAD、TranscriptBuffer、翻译提示词、帧协议
    ├── moxin-engine/                  会话、/v1/chat/completions、worker 管理
    ├── workers/asr-worker/            Qwen3-ASR-1.7B
    ├── workers/llm-worker/            Qwen3.5-2B：翻译和本机对话，自己的解码循环和调度
    └── node-hub/                      现有 Dora 节点，改为依赖 voice-core
```

之后的 `Subtitles/`（置顶字幕）、`Audio/`（麦克风、系统声音、重采样）、`Store/`（SwiftData 和 `ModelActor`）在对应步骤加。

## 10. 开发与验证

- 每个组件都有 `#Preview`，浅色、深色各一份。
- 页面预览接 `ReplayEngine`，按原始时间间隔回放 `Fixtures/` 里的事件日志。所有动画都在回放下调，不用开模型。
- 事件日志由引擎生成：`moxin-engine replay-wav lecture.wav --out lecture.jsonl`。这条命令同时是引擎的回归测试。
- 动画要录屏逐帧看（QuickTime 或 `screencapture -v`），静态截图看不出跳动和重排。
- 外观测试：应用开着，到系统设置里来回切换浅色、深色，再开关「减弱动态效果」，每个页面都看一遍。
- 对话客户端的测试接一个假的 OpenAI 兼容服务：测试里在本机起一个 HTTP 服务，按固定节奏回放 SSE，包括思考内容、各种错误码和中途断开，不依赖真实服务商和密钥。提示词用固定的转写拼出来，和存好的期望结果比对。
- 性能用 Xcode 26 Instruments 的 SwiftUI 工具和 Time Profiler 检查：回放一整节课的过程中，主线程上没有超过一帧的视图更新（120 Hz 下约 8 ms）。

## 11. 改造步骤

每一步都能单独运行和验收。

- **第 0 步：整理仓库。** 已完成。`LectureNoteApp` 单独建了仓库；Moxin-Voice 的本地修改（麦克风桥重连、ASR 模型路径、缺翻译模型时只出原文）提交在 `swiftui-redesign` 分支，提交 `333226c`。
- **第 1 步：设计系统和空壳。** 已完成，`LectureNoteApp` 的 `main` 分支，提交 `daffe58`。令牌、组件、外壳、会议列表、会议详情、开始按钮变形都接在 `ReplayEngine` 上。复查发现的问题列在第 15 节。
- **第 1b 步：按 Foresight 修整界面，加分类。** 已完成，`LectureNoteApp` 提交 `76759dd`。统计页已去掉，顶栏用了 `Design/logo.svg`，会议可以按课程分类，页面切换是淡入上移。验收时看过浅色列表、详情、英文分段、录音胶囊和深色列表。页面切换的动画没有逐帧录屏。第 15 节第 21 条（把界面拆成库 target 以方便预览）留到加 Xcode 工程时再做；16 px 的简化图标留到 Icon Composer。做了这些：
  - 删掉统计页。
  - 顶栏通栏加图标，去掉分隔线，换第 5 节的新颜色和布局。
  - 页面切换改成淡入上移。
  - 会议页加分类标签、按分类分组、右键归类，分类先存在内存里。
  - 会议详情改成头部加左右两张卡片，右栏先做「信息」。
  - 录音胶囊改成浅蓝底加点阵波形。
  - 应用图标（`iconutil` 生成 `.icns`）和 `scripts/build-app.sh`。
  - 修第 15 节里的问题。
- **第 1c 步：修第 16 节的问题。** 已完成，`LectureNoteApp` 提交 `a49780f`。减弱动态效果改读 SwiftUI 的环境值；去掉顶栏上方多出来的拖动条；窄窗口隐藏「对照」；导出改成挂在窗口上的保存面板，写失败会提示；转写拆成 `TranscriptCard`，段落行可比较；波形按音量历史在 `Canvas` 里算高度；字号记住；右栏选中标签和分类胶囊用浅蓝 / 白底胶囊；未分类图标改成 `tray`；关掉窗口状态恢复。`scripts/build-app.sh release` 打正式包。浅色下列表、详情和录音胶囊都看过。还没做的验收：应用开着时到系统设置里切换外观和「减弱动态效果」，以及页面切换、进入会议的逐帧录屏。
- **第 2 步：引擎和两个 worker。** 已接上。`Moxin-Voice` 提交 `5452567`，`LectureNoteApp` 提交 `66a6b5a`。`voice-core`、`asr-worker`、`llm-worker`（这一步只做翻译）和 `moxin-engine` 都在。短句 `replay-wav`：中文「今天我们讲注意力机制，它决定了模型看向哪里。」译成 “Today we discuss attention mechanisms, which determine where the model looks.”；英文两句词间有空格，并译回中文。缺翻译模型时 `translator` 是 `missing`、译文为空；缺识别模型时退出码非 0，事件是 `asr_missing`；`/v1/status` 写出缺失路径。英文片段之间补空格的修复在 `voice-core` 里，并有测试。App 会拉起引擎，顶栏按状态显示「本机 · 模型就绪」「本机 · 只出原文」「缺少识别模型」或「准备中」，开始后把麦克风送进 `/v1/session`。会议还是样例数据，SwiftData 仍是第 3 步。第 19 节里 10 分钟和 Dora 对照、延迟统计、60 分钟内存，以及杀掉 worker 后自动拉起，这次没做。
- **第 3 步：麦克风实时转录和翻译，边录边存。** App 拉起并看管引擎，接上 `LiveEngine`；会议、段落、分类换成 SwiftData。源语言和目标语言已经在设置里，新会议用那一对。顶栏状态胶囊和设置里的「模型」显示真实状态。这是第一个能拿去上课的版本。
- **第 4 步：对话模型层。** 设置里的服务商列表和编辑页、钥匙串、OpenAI 兼容的流式客户端、「测试连接」。`llm-worker` 加对话序列和抢占调度，引擎开放 `/v1/chat/completions`。云端和本机服务这一半不依赖第 2、3 步，想早点看到提问和摘要，可以挪到第 2 步之前，先接在示例会议上。
- **第 5 步：用到对话模型的功能。** 详情右栏的「摘要」「提问」，回答里的时间能点；分类建议、标题建议；导出的 Markdown 带摘要（第 18 节）。
- **第 6 步：记录管理、系统声音、跨会议提问和置顶字幕。** 搜索建索引，提问页和搜索共用这份索引。Core Audio tap 作为第二种输入源，可以只录某个应用。录音胶囊加「置顶字幕」按钮。
- **第 7 步：朗读和导入音频。** 段落上的「朗读」（`tts-worker`）。资料页导入音频文件，用 `transcribe_samples_chunked`（每 30 秒一块）整段转写成一场会议。
- **第 8 步：停用 Makepad 版。** `moxin-voice-shell` 只留作调试入口；签名、公证。

~~现在做完了第 2 步。下一步是第 3 步。~~ 进度已经超过这里，见第 20 节。产品名是 Nomi，Swift 模块仍叫 `LectureNoteApp`。

## 12. 不做

- 不把 `screen.rs` 翻译成 Swift。
- Swift 不直接调用 MLX，不读 Dora 的 YAML。
- 第一版不做课件上传、测验、复习计划。
- 不做统计页。时长、字数这些只在会议详情的「信息」里显示。
- 不做应用内的主题开关，外观跟随系统。
- 一场会议只属于一个分类，不做多标签。
- 界面里不提供切换 Paraformer 或 FunASR，ASR 固定 Qwen3-ASR 1.7B。
- 实时翻译第一版只用本机的 Qwen3.5-2B，不走云端。
- 对话模型不做工具调用、MCP、A2UI（Moxin-Studio 有），也不传图片。Qwen3.5-2B 的权重里带了视觉部分（991 个张量里 297 个属于视觉塔），这一版用不上。
- 第一版不做向量检索，提问用关键词检索（第 18 节）。
- 不把 API 密钥写进配置文件、UserDefaults 或日志。Moxin-Studio 把密钥明文存在 `~/.moly/preferences.json`，这一点不照搬。
- 第一版不上 Mac App Store：要读 `~/.OminiX/models`、要拉起子进程，沙盒里都受限。走 Developer ID 签名加公证。

## 13. 风险

- **切句参数要重新试听。** 现在的阈值在 `screen.rs` 的 `start_translation_dataflow` 里。中文麦克风：起始 / 结束 RMS 0.018 / 0.010，起始 5 帧，结束静音 420 ms，最短片段 420 ms，问句结束静音 1200 ms。英文 RMS 0.015 / 0.009，其他语言 0.016 / 0.009。系统声音在此基础上乘 0.3。片段上限 8 秒。这组值是按 CPAL 采集加线性重采样调出来的，换成 AVAudioEngine 和 `AVAudioConverter` 后要在真机上再试一遍。默认不开语音处理（回声消除和自动增益），因为自动增益会改变音量，直接影响 RMS 门限。
- **打包。** MLX 要求 `mlx.metallib` 和可执行文件放在一起，现在的 `build_macos_app.sh` 就是把它拷进 `Contents/MacOS`，新的每个 worker 都要能找到它。所有子进程都要单独签名并开启 Hardened Runtime。开了 Hardened Runtime 后，主应用必须带 `com.apple.security.device.audio-input` 授权，否则拿不到麦克风。
- **内存。** ASR 权重 2.46 GB（8-bit），运行时约 3–4 GB。Qwen3.5-2B 权重 1.72 GB，里面有用不上的视觉塔，加载后的实际占用要量。对话缓存很小：24 层里只有 6 层是全注意力，每层 2 个 KV 头、头维 256，每个 token 约 12 KB，8k token 约 100 MB；另外 18 层是固定大小的循环状态，每条序列约 18 MB。两个 worker 合计预计 6–7 GB。按 16 GB 内存设计（这台是 24 GB），转录期间不加载 TTS。worker 不要学 ominix-api 把 MLX 的 wired limit 设到内存的四分之三（它在这台机器上设了 18186 MB）。
- **首次启动。** 模型加载要几秒。用顶栏状态胶囊和开始按钮的「准备中」承接，不弹窗挡住界面。
- **系统音频权限。** 没有公开接口能预先检查，第一次录制时系统才弹窗。授权被拒或持续静音几秒后，在录音胶囊下方提示去系统设置里打开。
- **用 2B 模型回答问题和写摘要。** 能力有限，上下文越长越明显。本机模型的输入限制在 6k token，长课用检索和分段摘要；回答必须带时间，方便核对；提问时可以随时换成本机服务上的大模型或云端模型。
- **本机对话和实时翻译抢同一个模型。** 调度见第 3 节。验收看一边翻译一边回答时，翻译延迟涨了多少（第 19 节）。
- **服务商的兼容层不完全一样。** Anthropic、Gemini 的 OpenAI 兼容接口不支持全部参数，有的拉不到模型列表。客户端只用最基本的字段（`model`、`messages`、`temperature`、`max_tokens`、`stream`）；`max_tokens` 每次都带，Anthropic 要求必填；模型名允许手填。每个预设地址在实现时逐个连通测试。
- **云端隐私。** 转写会发给服务商。第一次让某个云端服务商处理会议内容之前要确认，回答下面标出用的是哪个模型（第 17 节）。
- **钥匙串弹窗。** 开发期每次重新编译，临时签名都会变，钥匙串可能每次都问「是否允许访问」。开发时用固定的开发证书签名。
- **思考内容。** 有的模型把思考过程放在 `reasoning_content`、`reasoning` 字段或正文开头的 `<think>` 里，Moxin-Studio 用的 aitk 客户端三种都处理。默认不显示、不存进回答，只在出正文之前显示「正在思考」。
- **OminiX-API 的版本。** 本机装的版本跑不了 Qwen3.5-2B，旁边也缺 `mlx.metallib`（第 3 节）。它只是可选的本机服务，坏了不影响转录，也不影响本机的 Qwen3.5-2B。
- **浅蓝录音胶囊在深色模式下。** #C2E8FF 直接搬到深色底上太亮，深色用 #1D3A50 配浅色字。要在真机上看对比度和玻璃效果。

## 14. 第 1b 步完成标准

第 1 步已经验收：应用能打开，侧栏可切换，会议页、开始按钮变形、回放转录都正常，浅色、深色都截图检查过。第 1b 步的标准：

- 侧栏只有会议、提问、资料，底部是设置和帮助。切换页面时新页淡入并上移，旧页不和新页叠在一起。
- 和 Foresight 截图并排对比：顶栏通栏带图标，没有分隔线，选中态是浅蓝，开始按钮是深海军蓝，录音胶囊是浅蓝底加点阵波形。
- 会议页能新建分类、给会议归类、按分类筛选和分组，筛选时卡片平滑进出。删除分类后会议回到「未分类」。
- 会议详情是头部加左右两张卡片。旧会议从开头显示，进行中的会议跟随底部。英文示例里词与词之间有空格。
- 应用开着时到系统设置切换浅色、深色，界面立刻跟着变；运行中开关「减弱动态效果」也立刻生效。
- 进入会议、返回列表、开始和停止转录、切换页面、筛选分类都录屏逐帧看过，没有跳动和重排。
- `scripts/build-app.sh` 一条命令出 `build/LectureNote.app`，Dock 和 Finder 里显示新图标。
- 第 15 节列出的问题都改掉，或者写明留到哪一步。

验收结果：侧栏、和 Foresight 的对照、分类、详情布局、英文空格、打包脚本、第 15 节的问题都达标。三条没达标，挪到第 1c 步：运行中切换外观没有试过；运行中开关「减弱动态效果」实际不生效（第 16 节第 1 条）；动画没有录屏逐帧看。

## 15. 第 1 步代码复查

`swift build` 没有警告，4 个分段测试都通过。下面是读代码和跑起来看到的问题，按影响排序，第 1b 步处理。

### 会出错的

1. **英文段落词连在一起。** 引擎发来的提交有时带前导空格，有时被 `trim` 掉（flush 出来的那段、tail 都会 `trim`）。`Paragraph.source` 用 `joined()` 直接拼，英文课会出现「attention,it」。译文反过来用空格拼，目标语言是中文时又多出空格。客户端先去掉每次提交的首尾空白，再按第 6 节的规则分语言拼接，补测试。引擎那边的同类问题见第 3 节。
2. **英文段落按长度永远不会断。** `TranscriptBuilder.shouldClose` 只认「。！？!?」，没有英文句号「.」；200 字的上限对英文也太短（约 35 个词）。
3. **从旧会议的详情页开始转录，标题还是旧的。** `MeetingDetailView` 的 `titleDraft` 只在 `onAppear` 里赋值，切到新会议时视图被复用，状态没重置。按会议 id 重建视图（`.id(meetingID)`）。
4. **打开已结束的会议直接跳到最底部。** `defaultScrollAnchor(.bottom, for: .initialOffset)` 对所有会议都生效。只有进行中的会议停在底部。
5. **「减弱动态效果」只在启动时读一次。** 自定义的 `appReduceMotion` 取代了系统的 `accessibilityReduceMotion`，运行中改设置不生效。改回读系统环境值，环境变量只在测试时覆盖。

### 和方案不一致、会影响流畅度的

6. **转写列表用的是 `VStack`。** 方案是 `LazyVStack`。一节课几百段时，每次 tail 更新都会重新布局全部段落。
7. **进入会议时整个详情页跟着卡片尺寸变化。** 动画过程中文字反复换行。应该只让底板匹配，内容稍后淡入。另外列表和详情是 `if/else` 切换，返回列表时滚动位置丢了，方案是放在同一个 `ZStack` 里。
8. **页面切换没有设计过渡。** 现在是系统默认的交叉淡化，新旧两页叠在一起。按第 7 节「切换页面」改。
9. **详情头部的时长不走。** 它只在转写更新时才刷新，和录音胶囊里的计时对不上。
10. **搜索每次刷新都把所有会议的全部段落扫一遍，而且一次刷新里算了两遍。** 先加防抖、只算一遍，第 6 步建索引。
11. **跟随底部的逻辑靠时间窗口。** 程序滚动后用 `ignoreScrollUntil` 忽略一段时间内的滚动事件，滚动慢一点就会误判成用户在滚。改成根据滚动是否由用户手势触发来判断（`onScrollPhaseChange`）。

### 界面上不合适的

12. **「上次导入」是占位按钮。** 点了只提示「尚未接上」。「导出会议记录」其实是复制到剪贴板。导入挪到资料页，导出改成保存文件。
13. **时间显示混用中英文。** 时间格式跟着系统区域走，这台机器是 `en_US`，中文界面里就出现了「今天 3:33 AM」「现在 · 3:59 AM」，更早的会议还会显示英文日期。语言名里只有 English 是英文。统一用 24 小时制、中文日期和中文语言名，不跟系统区域。
14. **转写卡片随内容高度伸缩，卡片自己也在滚。** 内容少时下面空一大块，内容多时圆角滚出去。改成固定大小的卡片，里面滚动。
15. **布局和 Foresight 差得最多的几处。** 内容固定居中 880 pt，宽窗口两边空；顶栏不通栏，没有图标；顶栏和侧栏之间画了分隔线；侧栏选中是灰色；搜索框是圆角矩形；录音胶囊是白底。都按第 5、6 节改。
16. **开始按钮的玻璃几乎看不见。** 现在是实色胶囊在变宽、变色，玻璃只剩一圈高光；变形动画也还没录屏检查过，只看了静态截图。
17. **没有「增强对比度」处理。** 第 5 节写了 `textSecondary` 加深一档，代码里还没有。
18. **在会议详情里点侧栏的「会议」回不到列表。** 当前页已经是会议，只改了选中项，详情还开着。再点一次当前页应该回到列表。

### 工程上的

19. **`TranscriptionEngine` 协议没用上。** `ReplayEngine` 声明遵守了协议，但 `AppModel` 直接持有 `ReplayEngine` 类型，接真引擎时要改很多地方。现在就改成依赖协议。
20. **应用包是手工拼的。** 拷二进制、写 Info.plist、拷资源包都是手动做的，没有脚本，换台机器跑不起来。补 `scripts/build-app.sh`，之后签名和授权也放进去。
21. **还没有 `#Preview`。** 方案要求每个组件浅色、深色各一份。建议把界面和模型挪进一个库 target，可执行 target 只留入口；预览、测试都只依赖库，以后加 Xcode 工程也省事。
22. **调试用的环境变量会进正式包。** `LECTURE_PREVIEW`、`LECTURE_COLOR_SCHEME`、`LECTURE_REDUCE_MOTION` 用 `#if DEBUG` 包起来。

### 已确认没问题的

- 外观跟随系统：不加任何覆盖启动时，系统是深色，界面就是深色；颜色都是动态色，浅色、深色截图都正常。
- 回放下的静态截图：段落按停顿分开，tail 用浅色，译文在原文下面。
- 录音胶囊的计时、暂停、停止在回放下都能用。

## 16. 第 1b 步代码复查

`swift build` 通过，7 个分段测试都通过。下面是读代码、对照截图看到的问题，第 1c 步处理。

### 会出错的

1. **运行中开关「减弱动态效果」不生效。** `ReduceMotionBridge` 在 `NotificationCenter.default` 上等 `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`，但 SDK 头文件 `NSAccessibility.h` 写明这条通知只发到 NSWorkspace 自己的通知中心，所以永远收不到。改成读 SwiftUI 的 `accessibilityReduceMotion` 环境值，再叠加调试用的环境变量覆盖。
2. **顶部空白多了一倍。** 隐藏标题栏后，安全区已经让出交通灯那一行，`AppShell` 又在顶栏上面加了一条 28 pt 的透明拖动条。结果交通灯到「LectureNote」那一行之间空了约 70 pt，而 Foresight 的品牌行紧挨着交通灯。`TopBar` 的背景本来就带 `WindowDragGesture`，删掉这条拖动条即可。
3. **「对照」按钮在窄窗口下没有效果。** 窗口窄于 1100 pt 时对照不生效，按钮文字却照样切换；按钮上还留着一句无效的 `.disabled(false)`。窄窗口时隐藏这个按钮。
4. **导出失败没有提示。** 写文件用的是 `try?`；保存面板用 `runModal()`，会挡住整个应用。改成挂在窗口上的面板，写失败时提示。

### 影响流畅度的

5. **进行中的会议，每次 tail 更新都让整个详情页重新求值。** `MeetingDetailView` 在同一个 `body` 里读 `engine.transcript`，头部、右栏、`GeometryReader` 都跟着重算。把转写列表拆成单独的视图，只有它读 `LiveTranscript`；`ParagraphRow` 实现 `Equatable` 并加 `.equatable()`。接真引擎（tail 每秒最多 10 次）之前必须改。
6. **录音波形每帧写两个 `@State` 数组。** `DotWaveform` 在 `onChange(of: timeline.date)` 里改 `targets` 和 `shown`，60 Hz 下每帧多一次视图更新。把电平历史放进 `LevelMeter` 里一个不参与观察的环形缓冲，`Canvas` 按 `timeline.date` 直接算插值，不写状态。改完用 Instruments 确认。
7. **启动时先看到旧画面。** 用 `open -n` 启动后约 2.5 秒截到的是第 1 步的界面（有「统计」页、没有图标），几秒后才换成当前界面，进程跑的确实是新二进制。可能是系统保存的窗口快照，也可能是首帧本身就慢。量一下冷启动到首帧的时间；应用不需要恢复窗口状态，用 `restorationBehavior(.disabled)` 关掉。

### 界面上不合适的

8. **右栏标签只靠字重区分。** Foresight 的选中标签是浅蓝胶囊，侧栏和分类标签也是这样。改成 `selection` 底加 `onSelection` 字。
9. **详情头部的分类胶囊没有白底。** 它用的是 `.menuStyle(.borderlessButton)`，系统去掉了背景，和旁边的日期、时间、语言胶囊不一致。自己画胶囊，隐藏菜单指示器或改小。
10. **字号每进一场会议都回到 15。** `fontSize` 是详情页的 `@State`。改成 `@AppStorage` 记住。
11. **「未分类」的图标是问号，看起来像「帮助」。** 换成 `tray`。
12. **设置页、提问页还是静态说明。** 预期内，第 3–5 步换掉。

### 工程上的

13. **`Paragraph.source` 和 `.translation` 写死了中文、英文的拼法。** `bottomToken` 和测试还在用。删掉，统一用 `renderedSource(language:)`、`renderedTranslation(language:)`。
14. **`AppModel.engine` 是 `let`。** 回放引擎和真引擎之间切换、引擎重启后换实例，都得重建整个 `AppModel`。第 3 步改成由 `EngineController` 持有引擎并对外发布状态。
15. **`scripts/build-app.sh` 打的是 debug 包。** `#if DEBUG` 里的调试环境变量会进包。正式包用 `-c release`。

### 已确认没问题的

- 资源包查找：SwiftPM 生成的 `Bundle.module` 先找 `Bundle.main.resourceURL`，脚本把资源包拷进了 `Contents/Resources`，换一台机器也找得到图标。
- 应用包里的二进制就是当前代码编译出来的，和 `swift build` 的产物哈希相同。
- 被详情盖住的列表已经设了 `allowsHitTesting(false)` 和 `accessibilityHidden`。

## 17. 模型接入

### 三类模型

| 用途 | 默认 | 可选 | 跑在哪 |
|---|---|---|---|
| 语音识别 | Qwen3-ASR-1.7B（8-bit） | 无（第 12 节） | `asr-worker` |
| 实时翻译 | Qwen3.5-2B-MLX-4bit | 关闭，只出原文 | `llm-worker` |
| 对话：提问、摘要、分类和标题建议 | 本机 Qwen3.5-2B | 本机服务（Ollama、LM Studio、OminiX-API）、云端服务商 | `llm-worker`，或 App 直连 |

两个本机模型都已经在 `~/.OminiX/models/` 下，路径可以在设置里改：

- `qwen3-asr-1.7b/`：`model_type` 是 `qwen3_asr`，8-bit，`model.safetensors` 2.46 GB，另有分词器文件和 `preprocessor_config.json`。支持 30 种语言。
- `Qwen3.5-2B-MLX-4bit/`：`model_type` 是 `qwen3_5`，mlx-vlm 转换的 4-bit 权重，`model.safetensors` 1.72 GB。语言部分在 `language_model.model.*` 下，`qwen3-5-35b-mlx` 会自动识别这个前缀。`tokenizer_config.json` 里没有对话模板，要读 `chat_template.jinja`，现在的翻译节点就是这么做的。最长位置 262144。

引擎启动时检查这些文件是否齐全，结果放进 `/v1/status`。缺 ASR 时不能开始转录。缺 Qwen3.5-2B 时只出原文、本机对话不可用，本机服务和云端照常可用。

### 服务商

照 Moxin-Studio 的做法，所有服务商都按 OpenAI 兼容接口接（`Authorization: Bearer`、`/chat/completions`、`/models`），Anthropic 和 Gemini 也用它们自己的 OpenAI 兼容地址，这样只要一个客户端。和 Moxin-Studio 不同的有两点：本机服务不要求填密钥（Moxin-Studio 没有密钥就跳过这个服务商，所以不填密钥的 Ollama 用不了）；密钥存钥匙串，不存明文 JSON。

| 服务商 | 默认地址 | 密钥 |
|---|---|---|
| 本机 · Qwen3.5-2B | 引擎地址 `http://127.0.0.1:{port}/v1` | 用引擎令牌，用户不用填 |
| Ollama | `http://localhost:11434/v1` | 不需要 |
| LM Studio | `http://localhost:1234/v1` | 不需要 |
| OminiX-API | `~/.OminiX/api_url` 里的地址加 `/v1` | 不需要 |
| OpenAI | `https://api.openai.com/v1` | 需要 |
| Anthropic | `https://api.anthropic.com/v1` | 需要 |
| Google Gemini | `https://generativelanguage.googleapis.com/v1beta/openai` | 需要 |
| DeepSeek | `https://api.deepseek.com/v1` | 需要 |
| Kimi（月之暗面） | `https://api.moonshot.cn/v1`，海外账号用 `api.moonshot.ai` | 需要 |
| 智谱 GLM | `https://open.bigmodel.cn/api/paas/v4`，海外用 `api.z.ai` | 需要 |
| 通义千问（阿里云百炼） | `https://dashscope.aliyuncs.com/compatible-mode/v1` | 需要 |
| 硅基流动 | `https://api.siliconflow.cn/v1` | 需要 |
| OpenRouter | `https://openrouter.ai/api/v1` | 需要 |
| Groq | `https://api.groq.com/openai/v1` | 需要 |
| 自定义 | 任意 OpenAI 兼容地址 | 可选 |

- 模型列表从 `GET /models` 拉，拉不到就手填模型名。预设里不写死模型名，模型更新太快。
- 每个服务商记一个「上下文长度」：本机 Qwen3.5-2B 固定 8k（输入 6k、输出留 2k；分块预填充验证不通过时输入降到 4k）；其他默认 32k，用户可以改。第 18 节靠它决定整场给还是先检索。
- 选一个默认对话模型，摘要和建议用它，提问时可以临时换。

### 客户端

`OpenAICompatibleClient` 用 `URLSession.bytes(for:)` 逐行读 SSE：

- 请求只带 `model`、`messages`、`temperature`、`max_tokens`、`stream: true`。本机 Qwen3.5-2B 额外带 `enable_thinking: false`。
- 读 `data:` 行，遇到 `[DONE]` 结束。正文取 `choices[0].delta.content`；思考内容取 `reasoning_content` 或 `reasoning`；正文以 `<think>` 开头时，把 `</think>` 之前的部分切出来，和 aitk 的 `split_reasoning_tag` 一样。思考内容不显示、不存。
- 网络读取和 JSON 解析不在主线程。界面每 50 ms 合并一次增量，和 tail 的做法一样。
- 停止就是取消 `Task`，连接随之断开；引擎看到连接断开就丢掉这条序列。
- 超时：连接 15 秒；第一个 token 本机 60 秒、云端 30 秒；之后两个 token 之间最多 30 秒。
- 错误换成一句中文：401、403 是「密钥无效或没有权限」；404 是「模型不存在」；429 是「请求太频繁或额度用完」；网络错误是「连不上 {服务商}」。原始响应只进调试日志。日志里不带密钥和完整提示词，只记长度。
- Info.plist 加 `NSAppTransportSecurity` → `NSAllowsLocalNetworking`，允许用 HTTP 访问 `localhost`。

### 引擎的对话接口

- `POST /v1/chat/completions` 只支持 OpenAI 接口的一小部分：`messages`（纯文本的 system、user、assistant）、`temperature`、`max_tokens`、`stream`，外加 `enable_thinking`（默认 false）。其他字段忽略。
- 流式时按 OpenAI 的格式发 `data: {"choices":[{"delta":{"content":"…"}}]}`；最后一条带 `finish_reason` 和 `usage`，然后发 `data: [DONE]`。
- 输入超过上限时返回 400 和 `context_length_exceeded`，由 App 先裁剪再发。
- 引擎按优先级把请求交给 `llm-worker`（第 3 节）。录音中开着翻译时回答会慢一些，提问界面提示「本机模型同时在翻译，回答会慢一点」。

### 密钥和隐私

- 密钥存钥匙串：`kSecClassGenericPassword`，service 为 `local.lecturenote.provider`，account 为服务商 id，可访问性用 `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，不随 iCloud 同步。保存后界面上只显示「已保存」和「删除」，不再回显。
- 每个云端服务商有一个「允许发送会议内容」开关，默认关。第一次用它处理会议时弹确认：「会把这场会议的转写发给 DeepSeek，用来生成摘要」，可以选「这次允许」或「总是允许」。
- 每条回答、每份摘要下面标出来源：「本机 · Qwen3.5-2B」或「DeepSeek · 模型名」。
- 没有统计上报。云端请求只在用户操作或打开了自动摘要时才发。

### 设置里的「模型」

设置页加三张白卡片：

- **模型**：语音识别、翻译各一行，显示模型名、状态（已就绪、未找到、加载中、出错）、占用内存，带「在 Finder 中显示」和「更改…」。翻译这一行有开关和目标语言。改了路径就重启引擎。
- **对话模型**：默认模型，下面是服务商列表。每行显示状态（可用、缺密钥、连不上、未启用），最后是虚线框「＋ 添加服务商」。点一行打开编辑页：名称、地址、密钥、模型（下拉加手填）、上下文长度、允许发送会议内容、「测试连接」。测试连接先拉一次模型列表，再发一个 1 token 的请求，显示耗时或错误。
- **自动功能**：会议结束后生成摘要、分类建议、标题建议，三个开关，默认都开。默认对话模型是云端、又没有授权发送会议内容时，不自动发送。

顶栏状态胶囊对应 `/v1/status`：「本机 · 模型就绪」；「本机 · 只出原文」（缺翻译模型）；「缺少识别模型」（开始按钮不可用）；「准备中」（引擎启动或模型加载中）。点胶囊打开这里。

### 以后再做

- ASR 上下文提示：Qwen3-ASR 的提示词里有一段空的 system 消息，`qwen3-asr-mlx` 现在什么也没放。把分类的术语表放进去，可能提高专业词的识别率。需要自己拼提示词，先试效果。
- 实时翻译走云端：引擎里的翻译做成一个接口，以后可以接 App 转发的云端翻译。
- 自动识别源语言。

## 18. 用到对话模型的功能

### 共用：怎么把转写交给模型

- 单位是段落（第 6 节的分段：停顿超过 2 秒，或写满后遇到句末标点）。每段带开始时间，格式 `[12:30]`，超过一小时写 `[1:02:30]`。
- 只给原文，不给译文：译文本身是模型生成的，可能有错，还会让长度翻倍。
- 长度按字符估算：中文一个字算 1 个 token，其他语言 4 个字符算 1 个 token，宁可估多。
- 转写放得进服务商上下文长度的 70% 就整场给，放不进就检索。
- 检索用 BM25：中文按相邻两个字切词，英文按单词切、去掉常见虚词。取得分最高的段落，每段顺带它的前一段，直到用满预算，再按时间顺序排好交给模型。一个词都对不上时（比如「这节课讲了什么」），有摘要就给摘要，没有就均匀抽段落。
- 引用：要求模型照转写里的格式标时间。App 把回答里的 `[mm:ss]` 换成可点的小胶囊：先找时间完全相同的段落；找不到就在给过模型的段落里找不晚于它、时间最近的那段；还找不到就保留原文，不做链接。点了打开会议、滚到那一段，`accentSoft` 底色闪一下。
- 回答和摘要只用标题、列表、粗体。流式输出时按纯文本显示，结束后再解析成这几种块来画，不用 WebView。

### 摘要

- 位置在详情右栏「摘要」，有「生成摘要」「重新生成」「复制」。导出 Markdown 时摘要放在最前面。
- 自动生成：会议结束后，时长超过 3 分钟、原文超过 300 字才做。默认模型是云端又没有授权时不自动发送，只显示按钮。
- 整场放得进就一次生成。放不进就分段：每段约 3k token，先各自列要点（每条带时间），再把要点合成最终摘要。
- 格式如下，没有内容的部分省略：

```
**概要**：一两句话。

### 要点
- [05:12] …

### 术语
- 主谓一致（subject-verb agreement）：…

### 作业和待办
- …
```

- 用中文写。原文是英文时，术语后面的括号里带上原文。
- 录音中也能手动生成「到目前为止」的摘要。

### 本场提问

- 位置在详情右栏「提问」。顶部一行显示当前模型（「本机 · Qwen3.5-2B」，点一下可以换），下面是问答记录，底部是胶囊输入框（↩ 发送，⇧↩ 换行）。生成时发送键变成停止键。
- 还没提问时给三个示例问题：「这节课讲了什么？」「布置了什么作业？」「有哪些需要记住的定义？」。
- 带上最近 3 轮问答，每轮的回答截到 300 字。
- 录音中也能问，用的是到目前为止已提交的原文，回答上方标「截至 12:30」。
- 问答存成 `ChatTurn`，重新打开会议还在，可以清空。

### 跨会议提问

- 位置在侧栏的「提问」页。大标题下面是范围标签：「全部」、各个分类、「选择会议…」，样子和会议页的分类标签一样。
- 检索范围内所有会议的段落，每场最多取 4 段，避免一场长课占满预算。
- 不同会议的时间会重复，所以这里给每段编号，例如「[3] 线性代数 · 特征值 · 10月18日 12:30：……」，要求模型用 `[3]` 引用。App 把编号换成「线性代数 12:30」这样的胶囊，点了打开那场会议并跳过去。
- 第一版在内存里检索，几百场会议够用；第 6 步改成和搜索共用索引。

### 分类建议

- 时机：会议还没有分类，录音满 3 分钟、原文满 300 字时做一次，会议结束时再做一次。用户忽略后，这场不再提。分类菜单里也可以手动点「建议分类」。
- 输入：现有分类名、会议标题、开头约 1500 字原文。
- 输出只能是三种之一：一个现有分类名；「新建：名字」（名字不超过 6 个字）；「无」。温度 0，最多 16 个 token。不是这三种格式就当没有建议。
- 界面：详情头部的分类胶囊旁边出现建议胶囊「像是数学课 · 归入」，带 ✕；需要新建时是「新建『线性代数』并归入」。只有用户点了才归类。

### 标题建议

- 时机：标题还是「未命名会议」，并且录音满 3 分钟、原文满 300 字，或者会议结束时。用户改过标题就不再建议。
- 输出不超过 16 个字，格式像「线性代数 · 特征值」。
- 界面：标题右边出现「命名为『线性代数 · 特征值』」胶囊，点一下采用，带 ✕。

### 提示词初稿

全部用中文，放在 `Prompts.swift`。单元测试用几份固定的输入，检查拼出来的提示词。

- 提问（system）：「你在帮用户回顾一场讲座或会议。只根据下面的转写回答；转写里没有的，直接说“转写里没有提到”。用中文回答，简洁。引用时在句末标出时间，格式和转写里一样，例如 [12:30]。转写来自语音识别，可能有错字，按上下文理解。」
- 提问（user）：「会议：{标题}（{分类}，{日期}，{源语言}）」，换行后是「转写：」和每行一段的 `[00:12] ……`，最后是「问题：{问题}」。
- 分段要点：「下面是一场讲座转写的一部分（{开始}–{结束}）。列出这一部分的要点，每条一句话，开头标出时间，例如 [05:12]。不要写转写里没有的内容。」
- 摘要：「根据下面的转写（或分段要点），用中文写这场讲座的摘要，用 Markdown：先写一两句话的“概要”，再写“要点”（每条开头带时间）、“术语”（术语：一句解释）、“作业和待办”（没有就省略）。不要编造。」
- 分类：「下面是一场会议的标题和开头的转写。现有分类：{分类列表}。如果属于其中一个，只输出那个分类名；都不合适时输出“新建：”加不超过 6 个字的分类名；判断不了就输出“无”。不要输出别的。」
- 标题：「给这场会议起一个不超过 16 个字的中文标题，格式像“线性代数 · 特征值”。只输出标题。」

## 19. 第 2–5 步完成标准

先用现在的 Dora 版跑同一段录音，记下延迟和内存作为基线。下面的数字是这台 M5（24 GB）上的目标，测完基线再校准。

### 第 2 步：引擎

- 同一段 10 分钟的中文录音，`replay-wav` 的原文和 Dora 版逐段对比，没有变差；英文录音里词与词之间都有空格。
- 说完一句到带译文的 `commit`：p50 不超过 2 秒，p95 不超过 4 秒，并且不比 Dora 版慢。延迟写进日志。
- 连续回放 60 分钟：所有进程合计内存不超过 7 GB，后 30 分钟增长不超过 300 MB。
- 把翻译模型目录改名：引擎照常启动，`/v1/status` 报出缺失的路径，事件里 `translator` 是 `missing`，只出原文。把 ASR 目录改名：`start` 返回 `asr_missing`。
- 转录中杀掉 `asr-worker`：引擎 5 秒内把它拉起来，发一条 `error` 事件，会话继续。

### 第 3 步：实时转录

- 用麦克风录一节 45 分钟的课，中途强制退出 App。重新打开后已提交的段落都在，最多丢正在说的半句。
- 回放和真引擎下，主线程都没有超过一帧（8 ms）的更新（Instruments）。
- 顶栏和设置里的模型状态与 `/v1/status` 一致；改了模型路径，引擎重启并生效。

### 第 4 步：对话模型层

- 每个预设服务商用有效密钥都能通过「测试连接」；密钥错了显示「密钥无效或没有权限」，不是一串 HTTP 错误。
- 在应用支持目录、UserDefaults 和日志里搜不到密钥内容。
- 流式回答：token 到达后 100 ms 内上屏；按停止后 200 ms 内停住，引擎日志显示这条序列已丢弃。
- 一边实时翻译一边让本机模型回答一个长问题：翻译的 p95 延迟比不提问时最多多 300 ms。
- 断网时云端服务商报「连不上」，本机 Qwen3.5-2B 照常可用。

### 第 5 步：摘要、提问和建议

- 本机模型给 60 分钟的课写摘要，记下耗时（先以 2 分钟以内为目标）。每条要点带时间，点时间能跳到对应段落。
- 准备 10 个问题，8 个转写里有答案、2 个没有：有答案的至少 7 个引用的时间对；没答案的 2 个回答「转写里没有提到」。
- 3 场示例会议的分类建议都对，而且只有用户点了才归类。
- 换成任意一个云端服务商，摘要、提问、建议都能用，第一次发送会议内容前有确认。

## 20. 当前进度（2026-10-18）

依据：`Nomi` 仓库到 `a82c4d2` 的提交、工作区里还没提交的改动、读代码和真机试录。没有跑 10 分钟、60 分钟的长测。

### 一句话

能用麦克风实时转录加翻译，边录边存，崩溃后已定稿的段落和录音都还在，能继续录、能问答和摘要，模型能下载和切换。第 3 步的功能已经齐了，差 45 分钟真课的验收（第 22 节第 1 条）。第 4、5 步各做了一部分，第 6–8 步没开始。

### 各步实际状态

| 步骤 | 状态 | 说明 |
|---|---|---|
| 0–1c 界面和设计系统 | 完成 | 第 1c 步留下的两项验收还没做：运行中切换外观和「减弱动态效果」、关键动画逐帧录屏 |
| 2 引擎和 worker | 完成，验收不全 | 后端已经搬进 `Nomi/Backend`，`build-app.sh` 一起编译打包。没做：和 Dora 版对比 10 分钟录音、p50 / p95 延迟、60 分钟内存、杀掉 worker 后自动拉起 |
| 3 实时转录、边录边存 | 功能完成，待长测 | App 拉起并看管引擎（意外退出重启一次）、麦克风选设备、实时 tail / commit、暂停、继续录制追加到原会议、录制前的设置面板（标题、开始时间、分类、输入源、语言）。每提交一段 300 ms 内在后台写盘；录音同时写 `meetings/{id}/audio-N.aac`（每次录制一个文件，暂停的时间不写）。实测：录到一半 `kill -9`，重开后会议和已提交段落都在；录制中途音频文件可读。和方案不同：存储是整份 `meetings.json`，不是 SwiftData；音频是 ADTS `.aac` 32 kbps，不是 `.m4a` 64 kbps（见下面「决定有变的地方」） |
| 4 对话模型层 | 一部分 | 已做：API 配置（OpenAI 兼容和 Anthropic Messages，9 个预设加自定义），密钥只在钥匙串，拉模型列表，本机 Qwen3.5 / Qwen3 问答。没做：流式输出（现在等整段返回）、「测试连接」、引擎的 `/v1/chat/completions`、翻译优先的抢占调度（现在录音中直接禁止本机问答）、首次发送会议内容的隐私确认 |
| 5 用到对话模型的功能 | 一部分 | 已做：详情右栏和提问页能对一场会议提问、生成摘要，回答带 `[mm:ss]`。没做：问答和摘要落盘（现在关掉应用就没了）、时间点击跳转、跨会议 / 按分类提问、分类建议、标题建议、导出带摘要 |
| 6 管理、系统声音、字幕 | 未开始 | 资料页还是占位说明 |
| 7 朗读、导入音频 | 未开始 | |
| 8 停用 Makepad、签名公证 | 未开始 | 现在是临时签名的 debug 包 |

### 原方案之外已经做了的

- 本机模型管理：设置里下载、校验（SHA-256）、中断后已下完的文件不重下、切换、删除到废纸篓，目录还是 `~/.OminiX/models`（见 `docs/local-models.md`）。
- 识别语言可以选「自动识别」。
- 界面语言可选跟随系统 / 简体中文 / English；外观可选跟随系统 / 白色 / 黑色。
- 已有会议可以「继续录制」，段落时间接在原来后面；详情页可以改开始时间。

### 决定有变的地方

这些和第 1–19 节写的不一样，以现状为准。要改回去，先在这里改决定，再动代码。

- 存储：第 8 节的 SwiftData 换成了 `~/Library/Application Support/Nomi/meetings.json` 整份写入。会议多了、课长了以后每次都写整份，迟早要换成按会议、按段落增量写（第 22 节）。
- 界面语言：第 5、6 节写「界面是中文、不跟系统」，现在支持英文界面（`Resources/en.lproj`）。
- 外观：第 12 节写「不做主题开关」，现在设置里有。
- 自动识别源语言：第 17 节放在「以后再做」，已经做了。
- 录音胶囊：第 6、7 节要求 `GlassEffectContainer` + `glassEffectID` 变形。macOS 26 上可交互的玻璃在点击时被替换会让应用崩溃（`mouseEntered` 里 `EXC_BAD_ACCESS`），现在是不可交互的 `.glassEffect(.clear)`，没有变形动画。不要再加回 `.interactive()` 和 `glassEffectID`。
- 本机问答：方案是录音中也能问、翻译优先；现在录音中禁止本机生成。
- 音频格式：第 8 节写的是 `audio.m4a`、64 kbps。现在是 ADTS 封装的 AAC（`.aac`），16 kHz 单声道 32 kbps，一小时约 14 MB，存在 `~/Library/Application Support/Nomi/meetings/{id}/audio-N.aac`。没写完的 `.m4a` 缺索引，崩溃后打不开；ADTS 每一帧独立，进程直接被杀也能读（实测）。一场会议录几次就有几个文件，`Meeting.audioFiles` 按顺序记文件名。

## 21. 已知问题（2026-10-18 复查）

按影响排序。修掉一条就划掉并写上提交号。

### 会出错 / 丢数据

1. ~~录制中的段落只在内存里，停止时才写盘，中途崩溃丢整场。~~ 已修：每次提交后写盘。
2. ~~应用在「准备中」被杀，会留下 0 秒、没有内容的空会议。~~ 已修：没有内容的录制中会议不写盘，启动时清掉已有的空会议。
3. ~~点「开始录制」后应用闪退。~~ 已修，两个原因：麦克风回调闭包在主 actor 上创建，被 Core Audio 线程调用时触发 `swift_task_checkIsolated` 崩溃，现在在主 actor 外安装；切换输入设备后 `installTap(format: nil)` 用的是旧采样率，`engine.start()` 报 -10868，现在传设备当前格式。
4. ~~自动识别语言时经常一个字都不出。~~ 已修：提示词停在 `assistant\n` 时，8-bit 模型的第一个 token 常常就是结束符。现在自动模式在提示词末尾先写 `language`，模型接着写语言名和 `<asr_text>` 正文（`vendor/qwen3-asr-mlx/src/model.rs`）。用 `say` 生成的中英文 wav 在自动和指定语言下结果一致，静音不出字。
5. **引擎只重启一次，worker 挂了不拉起。** 第 19 节要求杀掉 `asr-worker` 后 5 秒内恢复，没实现。
6. **录制中的会议在提问页能被选中。** 本机生成在录音中被禁止，但 API 模式下会拿还没定稿的转写去问。确认想要的行为。

### 功能不对

7. **自动识别模式下的拼接。** 中英混说时句子之间少句号或空格（「looks Every」「哪里Attention」）；有一截灰色的 tail 留在已经结束的段落里没提交。看 `voice-core/src/commit.rs` 里 `auto` 的 buffer 和 Swift `Transcript.swift` 里 automatic 的分支。
8. **右栏「字数」录制中一直是 0。** `Meeting.characterCount` 读的是 `meetings` 里的段落，录制中的段落在 `engine.transcript` 里。
9. **详情页停止后，右上角直接变成「继续录制」，点一下就接着录，不弹设置面板。** 容易误触。至少在刚停止时给个确认，或者和列表页一样先弹面板。
10. **同语言翻译。** 源语言和目标语言相同（比如英文 → 英文）时，模型会改写原句。相同时应该直接不翻译。
11. **问答和摘要不落盘。** 关掉应用就没了（第 5 步）。
12. **会议里的时间 `[mm:ss]` 不能点。**

### 体验

13. 录音胶囊没有变形动画（不可交互玻璃的代价，第 20 节）。可以只给底色和宽度做 `Motion.morph`，不碰 `glassEffectID`。
14. 详情头部胶囊样式已经统一，分类和输入源菜单改成 `.menuStyle(.button)` + `.buttonStyle(.plain)`。以后新加的头部胶囊都走 `metaLabel`。
15. 录制设置面板的标题框：打开时全选，点框外取消焦点。`OutsideClickObserver` 自己会清掉第一响应者，回调里不要再设 `@FocusState = false`，否则焦点会跳到下一个控件（开始时间）。

### 工程

16. `scripts/build-app.sh` 默认打 debug 包，临时签名；钥匙串在每次重新编译后可能重新询问。
17. `meetings.json` 每次整份写。一节 90 分钟的课约几百 KB，在后台串行队列写，暂时没问题；会议多了以后改成按会议分文件。
18. 新录制的会议在第一次提交之前崩溃，音频目录会留下没人引用的文件。

## 22. 接下来

按顺序做，每条做完更新第 20、21 节。

1. **第 3 步验收。** 用麦克风录一节 45 分钟的真课，中途 `kill -9`，重开检查段落和音频；录完用 Instruments 看主线程。顺手量第 19 节第 2 步的延迟和 60 分钟内存。
2. **修第 21 节第 7、8、10 条**，都在转写和语言处理上，改动小，影响每次录音。
3. **worker 和引擎自动拉起**（第 21 节第 5 条）：引擎发现 worker 退出就重启并发 `error`，会话继续；App 侧引擎连续重启加退避。
4. **第 5 步收尾：** 问答和摘要存进 `meetings.json`（或每场一个文件），`[mm:ss]` 做成可点的胶囊跳到段落，导出带摘要。然后做标题建议、分类建议。
5. **第 4 步收尾：** 流式输出、测试连接、第一次把会议内容发给云端前的确认。
6. **第 6 步：** 资料页能播放音频，点段落跳到对应时间；系统声音输入（Core Audio tap）；置顶字幕。
