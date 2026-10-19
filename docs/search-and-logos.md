# 联网搜索与厂商标志

> 2026-10-19 写定。同日已按这份接上：设置里配置搜索厂商，提问前由 Nomi 自己查网页。标志用各厂商公开的 logo，不是手绘替代图。
> 总文档 `docs/swiftui-redesign.md` 第 23 节里「联网只走服务商自带的搜索工具」作废，以这份为准。

Nomi 自己去查网页，再把查到的标题、网址和摘要交给当前选中的对话模型。本机模型和任意云端模型都走这一条。设置里列出已经接好的搜索厂商，每家都能单独保存密钥。大模型 API 和搜索厂商都用同一套标志：彩色 logo 加名字，方便区分。

用户不能自己填一个没接过的搜索地址。各家的请求和返回字段不一样，没有适配器就读不懂。

## 1. 标志

标志是资源文件，不是用文字画出来的字母块。文件放在 `Sources/LectureNoteApp/Resources/ProviderLogos/`，随 `Package.swift` 的 Resources 打进包。显示名和文件名分开：界面上写厂商的名字，资源用下面表格里的文件名。

每张图用厂商公开的原文件，不裁切、不改颜色、不加底色方块。界面按原比例整张放下，行内高度 16 pt，编辑标题里 22 pt，宽度跟着原图走。服务商预设用上下箭头，表示这里可以切换。认不出来的标志不要编。

认不出来的 `providerID`，以及「自定义」，用 SF Symbol `link`，不要编一个假 logo。本机模型用 `provider-qwen.png`。

### 大模型预设

和 `LLMProviderPreset.all` 的 `id` 一一对应。

| id | 界面名字 | 文件名 |
|---|---|---|
| `openai` | OpenAI | `provider-openai.png` |
| `anthropic` | Anthropic | `provider-anthropic.png` |
| `gemini` | Google Gemini | `provider-gemini.png` |
| `deepseek` | DeepSeek | `provider-deepseek.png` |
| `kimi` | Kimi | `provider-kimi.png` |
| `groq` | Groq | `provider-groq.png` |
| `nvidia` | NVIDIA | `provider-nvidia.png` |
| `zhipu` | Zhipu AI | `provider-zhipu.png` |
| `ollama` | Ollama | `provider-ollama.png` |
| `custom` | 自定义 | 无文件，用 SF Symbol `link` |
| （本机） | 本地模型 | `provider-qwen.png` |

### 搜索厂商

| id | 界面名字 | 文件名 | 这一版 |
|---|---|---|---|
| `tavily` | Tavily | `search-tavily.svg` | 接。引导里排第一，标「推荐」 |
| `exa` | Exa | `search-exa.png` | 接 |
| `searxng` | SearXNG | `search-searxng.svg` | 接。自建地址，密钥可空 |
| `brave` | Brave Search | — | 不接。新用户要绑卡 |
| `serper` | Serper | — | 不接。免费次数只给一次，用完要预付费 |
| `firecrawl` | Firecrawl | — | 不接。它主要是抓网页 |
| `linkup` | Linkup | — | 不接。免费额度是否每月重置还不明确 |
| `you` | You.com | — | 不接。免费通道是 MCP，不是一把可粘贴的密钥 |
| `google` | Google Custom Search | — | 不接。已不对新用户开放，2027-01-01 停止 |

商标归各厂商。资源只用在设置、菜单和提问胶囊里，用来认出是哪一家。

### 大模型配置里标志出现的位置

现在这些地方只有文字：

- 设置里「提问与摘要大模型」的每一条 API 配置。勾选圆点右边先放标志，再是名称和模型 ID。标志按这条配置的 `providerID` 取。
- 添加或编辑 API 时，「服务商预设」菜单的每一行是标志加名字。选中后，表单标题旁边也放同一枚标志。
- 提问页和会议详情右栏底部的模型胶囊。API 模式用当前配置的标志加模型名；本地模式用 Qwen 标志加模型名。

不改配置的保存字段。`providerID` 已经够用来取标志。

## 2. 设置里的搜索厂商

设置页在 `LLMSettingsSection` 下面加一节，标题是「联网搜索」。一节里一家一行，顺序固定为 Tavily、Exa、SearXNG。只留不用绑卡、免费额度会按月重置，或者自己搭建、不按次计费的。

每一行：

```
(o) [标志] Tavily          推荐
           未配置            [配置]

(•) [标志] Exa
           已保存密钥        [编辑]  [测试]
```

左边的圆点是「提问时用这一家」。只有已经保存了可用配置的行才能点亮。同时只有一家是选中的。Tavily 行的「推荐」用 `AppFont.caption`，颜色 `AppColor.textSecondary`。

点「配置」或「编辑」打开和 API 配置同一风格的表单，不用系统 Form。表单顶部是标志和厂商名字。名字下面先写一句提示，并给出这一家的页面链接，点了用浏览器打开。Tavily、Exa 的提示是「先在这个页面注册账号，创建 API 密钥，再粘贴到下面。」链接分别是 `https://app.tavily.com/home`、`https://dashboard.exa.ai/api-keys`。SearXNG 没有统一账号，提示改为按文档自己搭，链接是 `https://docs.searxng.org/`。再下面是字段：

| 厂商 | 字段 |
|---|---|
| Tavily、Exa | 密钥。地址写死在适配器里，不给用户改 |
| SearXNG | 地址，必填，例如 `http://127.0.0.1:8080`。密钥可留空 |

底部左侧是「测试连接」，右侧是「取消」和「保存」。测试用搜索词 `nomi`，成功则显示「连上了，返回了 N 条结果」，失败显示接口返回的简短原因。测试不写入「当前使用」。

保存时检查地址：只允许 `http` 或 `https`，必须有 host，不能在地址里夹用户名、密码、查询串或片段。SearXNG 以外的厂商没填密钥就不能保存。

密钥进钥匙串，服务名 `local.nomi.search-api`，账户名是厂商 id（`tavily`、`exa`、`searxng`）。地址和「当前使用哪一家」写在 UserDefaults，键是 `nomi.search.baseURL.<id>` 和 `nomi.search.active`。日志里不写密钥，也不写完整搜索词以外的会议正文。

删掉一家配置时，清掉它的钥匙串项和地址。如果删的是当前使用的那一家，`nomi.search.active` 清空，提问里的「联网」自动关掉。

### 第一次打开

不在启动会议页时弹窗，避免挡住录音。

装上这个功能后，用户第一次进入「提问」页，如果还没有任何一家搜索配置，卡片上方放一条可关闭的说明：

> 联网搜索需要你自己的搜索密钥。个人使用可以先用 Tavily，每月有免费额度，不用绑卡。

右边两个按钮：「去设置」「以后再说」。去设置打开设置页并滚到「联网搜索」。「以后再说」写入 `nomi.search.guideDismissed`，这条说明不再出现。设置页本身一直都在，不靠这条引导才能配置。

会议详情右栏的提问不重复放这条说明。那里的「联网」如果还不能用，悬停说明写「先在设置里配置一个搜索服务」。

## 3. 提问时怎么查

「联网」仍然是这一场对话的开关，默认关。开关能点的条件是：已经有一家搜索配置，并且它被选为当前使用。没有配置时开关是灰的，样式和现在的灰色胶囊一样。

打开之后发送问题：

1. 搜索词只用用户的这句话，不把会议转写和资料正文发给搜索服务。
2. 向当前选中的厂商要最多 5 条结果。每条收成标题、网址、摘要。
3. 这 5 条编成和会议段落一样的编号材料，接在已有材料后面。编号接着材料的最后一个号。摘要为空就只留标题和网址。
4. 系统提示里说明：这些是网页搜索结果；材料里没有、网页里有的内容要标明来自哪一条；不要编造没有给出的网址。
5. 当前模型照常回答。本机、MiniMax、Anthropic、OpenAI 都读这段文字，不再调用服务商自己的 `web_search` 工具。

回答下面的引用胶囊：网页来源用地球图标，标题加域名，点了用浏览器打开。会议时间和资料胶囊保持现在的样子。

搜索失败或 0 条结果时，仍把问题发给模型，但不附带网页段落。输入框下方用现有的错误样式写「联网搜索没有返回结果，这次只根据会议和资料回答。」或接口的简短错误。不让模型假装查过网。

生成过程中点停止，搜索请求和模型请求一起取消。

这一版不改流式输出。搜索返回之后，模型仍然整段回来再上屏。流式是总文档第 22 节第 10 条，和这次分开做。

## 4. 三家适配器

应用内部只认三样：`title`、`url`、`snippet`。超时 15 秒。非 2xx 时把响应里的简短错误原样给界面，密钥打成 `••••`。

| 厂商 | 请求 | 结果从哪取 |
|---|---|---|
| Tavily | `POST https://api.tavily.com/search`，JSON 里带 `query`、`max_results`、`search_depth: basic`，密钥用 Bearer | `results[].title`、`url`、`content` |
| Exa | `POST https://api.exa.ai/search`，头 `x-api-key`，要 highlights | `results[].title`、`url`，摘要用 highlight |
| SearXNG | `GET {地址}/search?q=&format=json`。填了密钥就放在 `Authorization: Bearer` | `results[].title`、`url`、`content` |

SearXNG 的公共实例大多关了 JSON。测试连接如果得到 403，提示「这台 SearXNG 没有打开 JSON。在它的设置里把 json 加进 search.formats。」

## 5. 界面文案

中文是 `tr()` 的键，英文写进 `en.lproj`。

| 中文 | English |
|---|---|
| 联网搜索 | Web Search |
| 推荐 | Recommended |
| 未配置 | Not configured |
| 已保存密钥 | Key saved |
| 配置 | Configure |
| 测试连接 | Test Connection |
| 去设置 | Open Settings |
| 以后再说 | Not Now |
| 连上了，返回了 %d 条结果 | Connected. %d results came back. |
| 先在设置里配置一个搜索服务 | Configure a search provider in Settings first. |
| 联网搜索没有返回结果，这次只根据会议和资料回答。 | Web search returned nothing. This answer uses only your meetings and files. |
| 这台 SearXNG 没有打开 JSON。在它的设置里把 json 加进 search.formats。 | This SearXNG instance does not have JSON enabled. Add json to search.formats in its settings. |
| 联网搜索需要你自己的搜索密钥。个人使用可以先用 Tavily，每月有免费额度，不用绑卡。 | Web search needs your own search key. For personal use, start with Tavily: it has a free monthly allowance and does not require a card. |
| 先在这个页面注册账号，创建 API 密钥，再粘贴到下面。 | Create an account on this page, make an API key, and paste it below. |
| SearXNG 没有统一账号。按文档搭好自己的服务，把地址填在下面。 | SearXNG has no shared account. Follow the docs to run your own instance, then enter its address below. |

已有的「联网」「编辑」「取消」「保存」继续用原来的键。

## 6. 这一版不做

- 不接 Brave。新用户要绑卡。
- 不接 Serper。免费次数只给一次，用完要预付费，额度还会过期。
- 不接 Firecrawl、Linkup、You.com、Google。
- 不让用户手写任意厂商的 URL 和 JSON 字段。
- 不把会议和资料正文发给搜索服务。
- 不让模型先改写搜索词。那会多一次生成。
- 不再调用 Anthropic 或 OpenAI 官方的 `web_search` 工具。已经配好的搜索厂商对所有模型生效。
- 不做流式吐字。
- 不在启动会议页弹强制绑定。

## 7. 实现时的顺序

1. 放入第 1 节的 SVG，设置里的大模型列表、预设菜单和提问胶囊带上标志。
2. 搜索配置的存储、钥匙串和三家适配器，加「测试连接」。
3. 设置页「联网搜索」一节，以及提问页第一次进入时的那条说明。
4. 发送问题前查询，把结果编进材料，引用胶囊打开网页。没有配置时「联网」保持灰色。
