# The chat agent: faster, cheaper, visible thinking: plan

> Written 2026-11-09. Nothing is built yet; work starts after your go-ahead and your answers in section 9.
> Replaces the earlier `answer-progress-plan.md`. The 0.8.4 release (repetition fix, picture panning)
> waits until this is decided, as you asked.

## 0. In one page

| Goal | What changes |
|---|---|
| Choose the API mode | Each API profile gets **"Chat Completions" or "Responses"**. Responses is greyed out for Anthropic and for any provider whose test call fails. |
| Thinking | Thinking is **on at Low by default** for API models, with Off / Low / Medium / High in the profile. Each provider gets the parameter it understands. The thinking streams live in the chat. |
| Never leave the student waiting blind | A **steps block** shows every step as it runs: reading files, searching the library, searching the web, thinking, writing, making the demo. |
| Loading animation | The **Nomi leaf morphs between a seed and the full logo**, Claude Code style, at the left of the running step. Four variants are in `Design/Animations/loading-preview.html`. |
| Faster and fewer tokens | **Measure** first, then make requests **cache-friendly**: a stable start, real chat turns, Claude cache markers, a cache key per chat. Each search round becomes cheap to resend. |
| Better answers | Low thinking, a cleaner prompt order, and the search results and rounds shown to the model the way it was trained to see them. |

## 1. What mature projects do (research)

**Connecting to APIs and thinking**
- **LobeChat / LobeHub** added the OpenAI Responses API to get streamed reasoning from OpenAI's reasoning
  models ([blog](https://lobehub.com/blog/openai-responses-api-intergration)). Its issues show the
  classic trap: Responses wants `reasoning.effort`, Chat Completions wants `reasoning_effort`, and
  sending the wrong one gives a 400 ([#8116](https://github.com/lobehub/lobehub/issues/8116)).
  The effort setting also vanished for models where it did not apply
  ([#8054](https://github.com/lobehub/lobehub/issues/8054)).
- **Cherry Studio** keeps one set of thinking levels and maps them to each provider's own values
  ([PR #21087](https://github.com/CherryHQ/cherry-studio/pull/21087)). It shows the effort control
  only when the model supports more than one level
  ([#23313](https://github.com/CherryHQ/cherry-studio/issues/23313)). Its bugs show what to avoid:
  - sending a thinking budget to a model that wants a level gives a 400
    ([#21968](https://github.com/CherryHQ/cherry-studio/issues/21968));
  - a thinking budget that fills the whole output limit leaves no answer
    ([#22975](https://github.com/CherryHQ/cherry-studio/issues/22975)).
- **Open WebUI** reads `<think>`/`<thought>` blocks and shows them as a foldable "Thought for N
  seconds" ([docs](https://docs.openwebui.com/features/chat-features/reasoning-models)). It has the
  same `reasoning_effort` mapping problem
  ([discussion #28421](https://github.com/open-webui/open-webui/discussions/28421)).
- **LiteLLM** normalizes the different providers' thinking into one `reasoning_content` field
  ([docs](https://docs.litellm.ai/docs/reasoning_content)). That is the shape Nomi already partly
  reads.
- **OpenAI Responses** streams a readable thinking summary as `response.reasoning_summary_text.delta`
  when `reasoning.summary` is set
  ([community guide](https://community.openai.com/t/responses-api-streaming-the-simple-guide-to-events/1363122)).
  Chat Completions never returns OpenAI's own thinking. So for OpenAI models, Responses is the only
  way to *show* thinking.
- **Anthropic** streams `thinking_delta` events when `thinking` is enabled. `budget_tokens` must be
  at least 1024 and less than `max_tokens`. Thinking between tool calls needs interleaved thinking
  ([docs](https://platform.claude.com/docs/en/build-with-claude/extended-thinking)).

**Showing progress**
- **Vercel AI SDK**: each message is a list of typed parts (text, reasoning, one part per tool with
  a state). A `start-step` marks each model call
  ([stream protocol](https://ai-sdk.dev/docs/ai-sdk-ui/stream-protocol),
  [tool usage](https://sdk.vercel.ai/docs/ai-sdk-ui/chatbot-tool-usage)).
- **assistant-ui**: thinking and tool calls are grouped into one collapsible "chain of thought" that
  shimmers while streaming ([guide](https://www.assistant-ui.com/docs/guides/chain-of-thought)).
- **Open WebUI**: tools emit status events (`description`, `done`). The running status shimmers until
  `done: true`, and every status is kept in a history
  ([events docs](https://docs.openwebui.com/features/plugin/events)).
- **Claude Code**: a star glyph ping-pongs through · ✢ ✳ ✶ ✻ ✽ next to a changing verb and the
  elapsed time, as described by open-source clones
  ([spinner write-up](https://medium.com/@kyletmartinez/reverse-engineering-claudes-ascii-spinner-animation-eec2804626e0)).
  This is the feel you asked for.

**Saving tokens**
- **OpenAI** caches automatically when the first 1024+ tokens match an earlier request exactly, and
  reports `cached_tokens` in the usage. Fixed content goes first and changing content last; a
  timestamp at the start kills the cache
  ([guide](https://developers.openai.com/api/docs/guides/prompt-caching),
  [cookbook](https://developers.openai.com/cookbook/examples/prompt_caching101)).
- **Anthropic** caches only up to blocks marked `cache_control`, up to 4 marks per request
  ([docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)). opencode marks the
  first two system messages and the last two messages
  ([discussion](https://forums.basehub.com/anomalyco/opencode/46)).

## 2. API mode: Chat Completions or Responses

**Settings, per API profile** (Settings › 模型 › the profile):

```
接口模式    ( Chat Completions )  ( Responses )        ← Responses greyed out for Anthropic: "Anthropic 使用 Messages 接口"
深入思考    ( 关 )  ( 低 · 默认 )  ( 中 )  ( 高 )        ← hidden for models that cannot think; local model always off
```

- **Default:**
  - **Chat Completions** for every provider;
  - **Responses** suggested for `api.openai.com` and Azure OpenAI, because only it shows OpenAI's
    thinking.
- **"测试连接" checks the chosen mode.** A 404 or "unsupported" from `/responses` greys the
  option out, with the reason. Many relays (likely including yours) only offer Chat Completions.
- **Responses requests** keep `store: false`: nothing is kept on OpenAI's side, and the full input
  is sent each time, as today. `previous_response_id` would need `store: true`, so it is not used.
- **The reply readers** already understand Responses events (`response.output_text.delta`). They
  learn the reasoning-summary events and the `usage` block.

## 3. Thinking: on at Low, shown live

**What each provider is sent for each level:**

| Provider style | Low (default) | Medium | High | Thinking arrives as |
|---|---|---|---|---|
| OpenAI, Responses | `reasoning: {effort: "low", summary: "auto"}` | `"medium"` | `"high"` | `response.reasoning_summary_text.delta` |
| OpenAI-compatible, Chat Completions (DeepSeek, Qwen, Kimi, OpenRouter, relays) | `reasoning_effort: "low"` | `"medium"` | `"high"` | `delta.reasoning_content` or `delta.reasoning` |
| Anthropic | `thinking: {type: "enabled", budget_tokens: 2048}`, `max_tokens` raised to 8192 + budget | 8000 | 16000 | `thinking_delta` |
| Models that think in text | nothing extra | | | `<think>…</think>` in the answer |
| Local model | off (a 2B model thinking is too slow) | | | |

**Rules learned from the projects above:**
- **If a provider rejects the thinking setting** (a 400 that names `reasoning`, `thinking` or
  `effort`), Nomi retries once without it. It remembers "this model does not take thinking" in the
  profile and greys the control with that note. A student never sees an error just for having
  thinking on.
- **Thinking never eats the whole answer:** the answer's room is always kept on top of the budget.
- **"Off" sends nothing**, rather than `effort: "none"`, which some providers reject.

**In the chat:** see section 4.

## 4. The steps block: what Nomi is doing right now

Above the answer, one line per step, with the leaf animation (section 6) at the left of the step
that is running, and the elapsed seconds the way Claude Code shows them:

```
 ❧ 正在联网搜索「self-attention O(n²)」…  3s        ← animated leaf, shimmering text
 ✓ 读取了 1 个文件 · Lecture3.pdf
 ✓ 在资料库找到 4 段 · 第 3 周课
 ✓ 思考了 4 秒 ›                                      ← click to read the thinking
```

| Step | While running | When done |
|---|---|---|
| Files | 正在读取 Lecture3.pdf… / 正在识别图片中的文字… | 读取了 3 个文件 · names |
| Library | 正在资料库中搜索「query」… | 找到 4 段 · where from |
| Web | 正在联网搜索「query」… | 找到 5 个网页 · sites |
| Thinking | 正在思考… with the thinking streaming in a small grey box, last 4 lines | 思考了 N 秒 › (opens the box) |
| Writing | 正在写回答… until the first word | (the answer itself shows progress) |
| Demo | 正在制作图示… | (the demo card appears) |

- **Each search the model asks for mid-answer** adds its own line, so a lookup round never looks
  frozen.
- **When the answer is done,** the block folds into one line above it, for example
  "用时 14 秒 · 读了 1 个文件 · 搜索 2 次 · 思考了 4 秒 ›". It is saved with the turn, so history
  shows it. The thinking text itself is not saved (question 4).
- **Code:**
  - `ChatRun` gets `steps: [AnswerStep]` and `thinking`.
  - `ask()` calls `beginStep`/`finishStep` around each step, about 15 small call sites.
  - `AnswerStepsView` draws it in `pendingView` (`AskView.swift`).
  - The meeting Q&A panel gets the same line.

This is the Vercel/assistant-ui "parts with state" model and Open WebUI's "status with done", done
natively in SwiftUI. There is no web framework to import; their designs are what we take.

## 5. Speed and tokens

### 5.1 Measure first

Each request is logged in a debug log (Settings › 关于 › 导出诊断) with:
- round, mode, and characters sent;
- time to the first thinking or answer token;
- total time;
- input, cached and output tokens from `usage`. Chat Completions gets
  `stream_options: {include_usage: true}`; Anthropic reports `cache_read_input_tokens`.

Then we compare before and after on the same five questions.

### 5.2 Make requests cache-friendly

| Today | Change | Why |
|---|---|---|
| The system prompt changes between rounds (web used, library searched, passages present) | System prompt **fixed for the whole chat**; the round's state goes in a short note at the end | The very first tokens stay identical, so everything after them can be cached |
| History is pasted inside one big user message and slides each turn | Earlier turns sent as **real user/assistant messages**; older turns leave in **blocks of 4** (then the summary), not one per turn | The start of the request stays the same for several turns in a row |
| Every search round rebuilds the whole prompt | Round 2 is the round-1 request **plus** the model's draft and the search results as new messages | Round 2 re-reads nothing: the whole round-1 request is a cache hit |
| Claude never caches | `cache_control` on the system prompt and on the last earlier turn (2 of the 4 allowed marks) | Claude reads cached input at about a tenth of the price, and faster |
| OpenAI picks a cache server at random | `prompt_cache_key` = the chat's ID | Requests of one chat land on the same cache |
| Date and time in the system prompt | Date only (no time), placed at the end of the system prompt | A changing minute would break the cache every request |

**Expected effect:** on a follow-up question in the same chat, most of the 30–40k input tokens come
from cache. Time to the first word should drop, and input cost should drop a lot. Section 5.1
measures how much; I won't promise a number before measuring.

### 5.3 Send less where it does not help
- **Search results:** keep only the top passages per search (today up to 24,000 characters), and
  tell the model it can search again.
- **The scope** (meetings and files picked): when it is larger than about 30,000 characters, send
  the passages that match the question, the way attached files already work.
- **The demo request** already runs after the answer. It gets the cache marks too, since it repeats
  the answer.

## 6. The loading animation: the Nomi leaf, morphing

Open `Design/Animations/loading-preview.html` to see all four, live, in light and dark, at real size
next to a step line, and inside a mock chat.

- **How it works:** the real logo outline (`Design/Brand/logo-transparent.svg`) is sampled into 96
  points. A round "seed" is the same 96 points on a small circle. The animation blends between the
  two, so the leaf grows out of a dot and curls back into it. The mint highlight fades in as the
  leaf opens.
- **In SwiftUI:**
  - a `LeafMorph: Shape` whose `animatableData` is the blend (0 = seed, 1 = leaf), with the points
    built into the code;
  - driven by `TimelineView(.animation)`, so it stays smooth and uses almost no power;
  - no Lottie or other package needed.
- **The four variants:**
  - **A · Unfurl:** one seed breathes open into the leaf and back.
  - **B · Three seeds** (my pick for the step line): three dots like Claude Code's, with a wave
    passing through them; each hops and opens into the leaf in turn.
  - **C · Orbit:** three small leaves circle, opening at the top.
  - **D · Sway:** the full logo sways on its stem.
- **Text shimmer** on the running step, as in
  [markiv/SwiftUI-Shimmer](https://github.com/markiv/SwiftUI-Shimmer) (MIT). It is about 20 lines,
  so we write it ourselves or take the package.
- **Reduce Motion** in macOS: the leaf stays still and the shimmer stops.
- **Where it is used:**
  - the running step line (16 pt);
  - the moment before the first step (24 pt, variant A);
  - "正在制作图示…";
  - the meeting Q&A panel;
  - the history list's running chat.

## 7. Answer quality

- **Low thinking** by itself helps multi-step questions most.
- **Real chat turns** (5.2) instead of "Previous conversation (reference only)" pasted in one
  message: models follow follow-up questions better in the format they were trained on.
- **Search results as their own message** after the model asked for them, instead of rebuilding the
  prompt and adding "Draft already shown…". This removes repeated or restarted paragraphs after a
  search.
- **Test set:** 10 saved questions (files, library, web, follow-ups, Chinese and English), run
  before and after, compared side by side for correctness, citations, length, time and tokens. The
  results go in `build/agent-bench`, like the transcription bench.

## 8. Work, in order

1. **Measurement log** (5.1) and the 10-question test set; a baseline run. *About 2 hours.*
2. **API mode and thinking settings** (2, 3): profile fields, the test-connection check, per-provider
   mapping, the retry-without-thinking rule, reading every thinking event. Tests use recorded
   streams from each provider style. *About 1 day.*
3. **Steps block and live thinking** (4), with history. *About half a day.*
4. **Leaf animation** in SwiftUI (6) plus the shimmer, placed everywhere listed. *About half a day.*
5. **Cache-friendly requests** (5.2, 5.3) and real chat turns (7). This is the riskiest part, because
   it changes what the model sees, so it comes after the measurement baseline. *About 1 day.*
6. **Run the test set again**, compare, and fix what got worse. Then a test build for you, then
   0.8.4 (or 0.9) when you say so.

## 9. Decisions for you

My suggestion is in bold.

1. **"Reason mode".** I read your "chat mode or reason mode" as **Chat Completions or the Responses
   API**: Anthropic can't use Responses, and that matches "block it like Anthropic". Is that right,
   or did you mean a separate Chat / Think switch? (Thinking has its own setting in section 3
   either way.)
2. **Thinking default: Low for every API model**, changeable per profile? **Suggestion: yes, as you
   said.**
3. **Animation:** A, B, C or D? **Suggestion: B for the step line, A for the moment before the first
   step.**
4. **Thinking text:** shown live and readable after (not saved in history)? **Suggestion: yes,
   folded to 4 lines while streaming; saved only as "思考了 N 秒".**
5. **Version:** ship all of this together with the repetition fix as **0.9**, or the repetition
   fix first as 0.8.4? **Suggestion: 0.8.4 first.** It is done and tested, and a transcription bug
   fix shouldn't wait a week behind the chat work. You asked to hold it, so I will until you say.

## 10. Not in this plan

- Native function calling (the API's own tool format instead of `<tool>` tags). It would help
  quality further, but it changes every provider path. It is better as its own step after this one.
- Thinking for the local model.
- Showing costs in money.
