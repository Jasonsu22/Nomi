# Nomi memory plan

Status: proposal, waiting for approval. No code has been changed for it.
Branch: `perf/chat-responsiveness` (worktree `Nomi-chat-performance`), based on `d37f1b8`.

## 1. Where memory stands today

"Memory" here means everything that decides what the model knows when it answers: the
current chat's earlier turns, other chats, meetings, files, web results, and facts about the
student. Nomi has no single memory system; each of these is handled separately.

| Area | Today | Problem |
| --- | --- | --- |
| Current chat | Last 4 turns, question and answer each cut to 400 characters (`ChatContext.userPrompt`) | Most answers are longer than 400 characters, so "explain point 3" often fails. Cuts land mid-sentence. Demo HTML and tool markers waste the 400 characters. Turn 5 and older is gone unless the model calls `search_library`. |
| Long chats | Nothing | No summary of older turns. |
| Facts about the student | **In progress** in this worktree (`UserMemory`, `AppModel+Memory`, `MemorySettingsSection`, uncommitted) | Reviewed in section 9. |
| Other chats, all meetings, files | **Done** in `59d0b78`: `search_library` with BM25 over character pairs and date ranges | Works for recall questions. Meeting summaries are not searchable. |
| Meetings picked in the scope chip | `ChatContext.pack`: 16,000 characters, ranked by single shared characters | Single characters are noise in Chinese (的, 是), so the relevant part of a long lecture can be dropped. |
| Meeting side panel (summary, Q&A) | `MeetingAssistantState`, in memory only | Lost on restart. The whole transcript is sent with no limit, so a long lecture can overflow a small local model. Q&A history is the last 3 answers in full, no limit. |
| Budgets | One fixed size for every model | Too big for the local 2B model, far too small for API models. |
| Web search for follow-ups | Borrows the previous question only when the new one is under 12 characters | "那它和经典计算机比呢？" is searched without its topic. |

## 2. Goals and non-goals

Goals:

1. A follow-up in a long chat understands what was said earlier, including long answers.
2. Long chats keep their thread through a stored running summary.
3. Meeting summaries and side-panel Q&A survive a restart, and are reused by chat.
4. Every request fits the model it goes to: small for local, large for API.
5. The most relevant part of a long lecture reaches the model.
6. Follow-up web searches carry their topic.
7. The in-progress long-term memory ships safely (section 9).

Non-goals: no vector database, no embeddings model in this round, no new cloud service, no
change to how chats or meetings look, no change to the stored JSON that breaks older files.

## 3. Coordination and order

The in-progress memory work edits `ChatContext.swift`, `AppModel+Chat.swift`,
`AppModel+Assistant.swift`, `ChatSession.swift` and `LocalEngine.swift`. Every phase below
touches some of these. **No phase starts until that work is committed.** Then:

| Phase | Content | Depends on |
| --- | --- | --- |
| P0 | Review fixes for long-term memory (section 9) | memory work committed |
| P1 | Context budgets per model (section 4) | — |
| P2 | Short-term history window (section 5) | P1 |
| P3 | Running chat summary (section 6) | P2 |
| P4 | Saved meeting summaries and side-panel limits (section 7) | P1 |
| P5 | Better passage ranking for the scope chip (section 8.1) | P1 |
| P6 | Follow-up web search queries (section 8.2) | P2 |

Each phase is its own commit with its own tests. P4 and P5 can run in parallel with P2/P3
because they touch different files, except `ChatContext.swift`, which P2, P5 and P6 all
change; those three go one after another.

## 4. P1 — Context budgets per model

### Design

New file `Models/ContextBudget.swift`:

```swift
/// How much text one request may carry, in characters, for the model it goes to.
struct ContextBudget: Equatable, Sendable {
    var history: Int            // earlier turns of this chat, summary included
    var turnAnswer: Int         // longest single earlier answer kept in full
    var scope: Int              // meetings and files picked in the scope chip
    var library: Int            // one library search's results
    var sidePanelTranscript: Int

    static let local = ContextBudget(history: 6_000, turnAnswer: 1_500, scope: 16_000,
                                     library: 9_000, sidePanelTranscript: 18_000)
    static let api = ContextBudget(history: 24_000, turnAnswer: 6_000, scope: 60_000,
                                   library: 24_000, sidePanelTranscript: 90_000)

    static func current(mode: LLMMode, profile: LLMAPIProfile?) -> ContextBudget
}
```

Scope passages, library results and web results are added together in one request, so they
have separate limits instead of one shared "passages" number; local values equal today's
(16,000 and 9,000), so local behaviour does not change in P1.

- Characters, not tokens. Qwen and most API tokenizers spend about one token per 1–1.5 Chinese
  characters and per 3–4 Latin characters, so a character budget is conservative for English
  and close for Chinese. No tokenizer dependency is added.
- Local numbers: the local model's config allows long input, but prompt processing time on
  a 2B model grows with input. 24,000 characters keeps the first token within a few seconds
  on Apple silicon. To be confirmed by measurement in P1 (see acceptance).
- API numbers assume at least a 128k-token window, which every model in the current profiles
  has. A profile can override: add optional `contextCharacters: Int?` to `LLMAPIProfile`
  (decoded with `decodeIfPresent`, no migration). No UI in this round; the field exists so a
  small-window API model can be fixed by editing one value later. When set, `api` is scaled
  by `contextCharacters / 120_000`, never below a quarter of the local values.
- `ChatContext.budget` and `LibrarySearch.budget` become `ContextBudget.local.scope` and
  `.library`, and the chat passes the current model's values. Library search keeps its own
  1,400-character cap per passage.

### Changes

- `ContextBudget.swift` (new), `LLMConfiguration.swift` (profile field),
  `AppModel+Chat.swift` (compute once per question, pass down), `ChatContext.pack`
  (take a budget), `LibrarySearch.run` (callers pass the budget).

### Tests

- `local` and `api` values; a profile override scales every part.
- `pack` respects a smaller budget.

### Acceptance

- Same answers as before for short chats.
- Measure on this Mac: time to first token for a 24,000-character local prompt. If over 8
  seconds, lower `local.total` until it is under.

## 5. P2 — Short-term history window

### Design

New `ChatHistory` in `Models/ChatContext.swift` (or its own file):

```swift
struct HistoryWindow: Equatable {
    var text: String          // "Previous conversation" block for the prompt
    var includedTurns: Set<UUID>
    var omittedOlderTurns: Int  // turns not shown and not covered by the summary
}

enum ChatHistory {
    static func window(_ turns: [ChatTurn], summary: ChatSummary?, budget: ContextBudget) -> HistoryWindow
    static func cleanedAnswer(_ answer: String, limit: Int) -> String
}
```

Rules, newest turn first:

1. Skip turns with an error or an empty answer.
2. `cleanedAnswer` before measuring:
   - Replace each demo/HTML fence with one line, `[交互演示：<title>]` (title from
     `AnswerDocument` widget detection), so a 6,000-character page costs ~15 characters.
   - Remove `<tool …>…</tool>` markers and the visual marker (`ChatTools.parse`,
     `ChatContext.splitVisual`).
   - Keep citation numbers like [2]; they still mean something to the reader.
3. If the cleaned answer is longer than `turnAnswer`, keep its start and end
   (70% / 30% of the limit), joined by `…`, each cut at a sentence end
   (。！？.!?\n). The start usually holds the main point; the end holds the conclusion and
   any list the student will refer to as "the last point".
4. Question: up to 800 characters, same sentence cutting.
5. Add whole turns until `history` is used. The newest turn is always included, cut harder
   if it alone exceeds the budget.
6. Turns before the oldest included one are covered by the running summary (P3) if it exists;
   otherwise `omittedOlderTurns` counts them, and the prompt says
   "N earlier turns are not shown; use search_library to look them up." when the library
   tool is available.
7. The image note ("用户发过一张图片") stays per turn as today.

Output order in the prompt (unchanged labels, so prompts stay recognizable):

```
Summary of earlier conversation:      ← P3, only when present
…
Previous conversation (reference only):
[10-19 14:02] Question: …
Answer: …
```

Dates are added per turn because library search and memory already use dates and the model
handles "earlier today" vs "yesterday" better with them.

### Wiring

- `ChatContext.userPrompt` takes a `HistoryWindow` instead of `[ChatTurn]`.
- `LibraryExclusions.turns` uses `window.includedTurns` instead of `history.suffix(4)`, so a
  turn is never both in the prompt and in search results.
- Meeting side panel (`AppModel+Assistant`) uses the same function for its Q&A history, with
  `MeetingAssistantAnswer` mapped to the same shape.
- `MemoryLearning.prompt` uses `cleanedAnswer` too (section 9, R6).

### Tests

- A 5,000-character answer keeps both ends and cuts at sentence ends.
- An answer with an HTML demo becomes one `[交互演示：…]` line.
- Budget: with 10 long turns only the newest fit; `includedTurns` matches.
- Newest turn always included.
- Error turns skipped.
- Exclusions for library search equal `includedTurns`.

### Acceptance

- Ask a long question, get a numbered list of 8 points, ask "第 7 点再展开一下": the answer
  is about point 7 with local and API models.

## 6. P3 — Running chat summary

### Data

`ChatSession` gains, decoded with `decodeIfPresent`:

```swift
struct ChatSummary: Codable, Equatable, Sendable {
    var text: String
    var throughTurnID: UUID      // last turn the summary covers
    var throughDate: Date
    var coveredTurns: Int
    var modelName: String
    var updatedAt: Date
}
var summary: ChatSummary?
```

### When it runs

After an answer finishes (same place `scheduleMemoryLearning()` is called):

- Let `older` = turns before the oldest turn in the current `HistoryWindow` that are not yet
  covered by `summary`.
- Run when `older.count >= 3` or their cleaned text is over 3,000 characters.
- Never for a chat with fewer than 6 turns.

### How it runs

One background queue for all after-answer work, shared with the memory pass, so a local
model never runs two background generations and a question never waits on more than one:

```swift
/// Work that runs quietly after an answer: the chat summary, then the memory pass.
@MainActor final class AfterAnswerJobs { func schedule(...) ; func waitIfRunning() async }
```

- `AppModel+Memory.scheduleMemoryLearning` becomes one job in this queue rather than its own
  `memoryTask`. `waitForMemory` becomes `afterAnswerJobs.waitIfRunning()`.
- API: runs immediately. Local: waits for a quiet moment (no chat, no side-panel answer), the
  same rule memory already uses; a new question cancels a job that has not started.
- Background generations use `maxTokens: 400` locally.

Prompt (system), in the reply language:

> You keep a running summary of one study conversation for Nomi. Merge the earlier summary
> with the new turns. Keep: the topics covered, conclusions and definitions given, numbers,
> names, dates, decisions the student made, and questions still open. Drop greetings and
> anything already in the summary. Plain sentences or short bullets, at most N characters.

N = 600 (local) or 1,500 (API). User prompt: earlier summary (if any) + `older` turns,
cleaned with `cleanedAnswer(limit: turnAnswer)`.

Result handling:

- Trim to N; reject empty replies; keep the old summary on failure. Retry at the next answer,
  at most 3 attempts per chat until a success.
- Save with `mutate` so the chat is written by the existing background `ChatStore`, without
  moving the chat to the top of history (`updatedAt` unchanged).

### Where it is used

- `HistoryWindow` puts it before the recent turns (section 5).
- `LibrarySearch.chatDocuments` adds one document per chat summary (kind `.chat`,
  detail "对话摘要"), so recall questions can hit the summary of a long chat.

### UI

None beyond what is there. (Optional later: show "已整理前面 N 轮" in the chat's history
popover.)

### Tests

- Trigger rules (3 turns / 3,000 characters / under 6 turns never).
- Old chat JSON without `summary` decodes; a new one round-trips.
- Failure keeps the old summary and counts attempts.
- `updatedAt` unchanged after saving a summary.
- Queue: summary then memory run one after the other; `waitIfRunning` waits for a running job
  and cancels a waiting one.

## 7. P4 — Saved meeting summaries and side-panel limits

### Data

`Meeting` gains an optional record (synthesized `Codable` decodes a missing optional as nil):

```swift
struct MeetingAssistantRecord: Codable, Equatable, Sendable {
    struct Answer: Codable, Equatable, Sendable, Identifiable {
        var id: UUID; var question: String; var answer: String
        var modelName: String; var createdAt: Date
    }
    var summary: String?
    var summaryModelName: String?
    var summaryAt: Date?
    var summaryCoversUntil: TimeInterval?   // transcript time the summary saw
    var answers: [Answer] = []              // newest 50 kept
}
var assistant: MeetingAssistantRecord?
```

### Behaviour

- Opening a meeting: `MeetingAssistantState` is filled from `meeting.assistant` the first time
  it is created (`AppModel+Assistant`, where `assistantStates[meetingID]` is made).
- After a summary or an answer finishes: write into `meetings[index].assistant`, then
  `persistMeetings(inBackground: true)`. For the live meeting, `persistMeetings` builds the
  saved copy from `meeting`, so the record is kept; verify with a test.
- Deleting a meeting removes it with the meeting. "Regenerate summary" replaces it.
- A summary older than the transcript (`summaryCoversUntil` < meeting duration − 60 s, e.g.
  recording resumed) shows a small "转写有更新，可以重新生成摘要" line. No automatic rerun.

### Side-panel limits

- Q&A: rank transcript paragraphs with `LibrarySearch` for the question and keep the best ones
  within `sidePanelTranscript`, sent in time order with their timestamps. Short transcripts
  are sent whole, as today.
- Summary of a transcript longer than `sidePanelTranscript`: split into consecutive chunks
  that fit, summarize each (≤ 800 characters, with timestamps), then summarize the chunk
  summaries into the final one. Local models cap this at 4 chunks; beyond that, use the 4
  chunks evenly spaced plus their timestamps and say so in the summary's first line.
  Progress shows in the existing draft area ("正在整理第 2/4 段…").
- History for side-panel Q&A uses `HistoryWindow` (section 5).

### Reuse by chat

- `ChatContext.pack`: when a meeting picked in the scope chip does not fit in `passages`, its
  saved summary is added first as its own passage ("会议摘要"), then the best paragraphs.
- `LibrarySearch.meetingDocuments`: one extra document per saved summary (detail "摘要"), so
  "上周那节课讲了什么" hits the summary first.

### Tests

- Old `meetings.json` decodes; record round-trips; 50-answer cap.
- Live meeting keeps its record across `persistMeetings`.
- Q&A selection respects the budget and keeps time order.
- Chunk planning: sizes, the 4-chunk cap for local, timestamps preserved.
- Stale-summary detection.

## 8. Retrieval fixes

### 8.1 P5 — Scope-chip passage ranking

- `ChatContext.pack` stops using `tokens(in:)` (single characters). It ranks with the BM25
  scorer already in `LibrarySearch` (character pairs for Chinese, words for Latin): expose
  `LibrarySearch.score(query:documents:)` and call it from `pack`.
- Neighbours: when a paragraph is picked, its previous and next paragraph from the same
  meeting are added if they fit, because a lecture point often spans paragraphs.
- Output stays in original order, so citations read naturally.
- No score at all (e.g. "总结一下"): keep today's behaviour (start of each item until the
  budget), plus the saved meeting summary first when present (P4).

Tests: a Chinese question about a term on page 3 of a long transcript picks that page; common
characters alone (的、是、了) never decide ranking; neighbours added; order kept.

### 8.2 P6 — Follow-up web search queries

`ChatContext.searchQuery(question:history:)` becomes:

1. A question is a follow-up when it is short (< 20 characters) **or** starts with or contains
   a reference word (它、这个、那个、这、那、他们、它们、继续、再、还有、呢 at the end,
   it, this, that, they, them, more, also).
2. For a follow-up, build: top 4 search terms (BM25 terms from `LibrarySearch.searchTerms`)
   of the previous question + the chat summary's first sentence when present, then the
   question itself, capped at 300 characters.
3. Otherwise the question alone, as today.
4. API models: when the model itself calls `web_search` with its own query, that query wins
   (already the case in the tool round); this only shapes the search the app runs first.

Tests: "那它和经典计算机比呢？" after "什么是量子计算机" includes 量子; a standalone question is
unchanged; a long new-topic question that contains 这 is not padded when it already has
≥ 3 search terms of its own.

## 9. P0 — Review of the in-progress long-term memory

Read at the state of 03:17; recheck once committed. The design is sound (small items, kinds,
pinning, secret filter, budget, settings UI, tests). Issues to fix:

| # | Issue | Fix |
| --- | --- | --- |
| R1 | Memory is on by default, and with an API model every 3 turns sends recent questions and answers to the API in an extra request. That is a new data flow and a new cost the student did not choose. | Default on for local models, off for API until the student turns it on. The Settings text says that learning uses the selected model, and for API that the recent conversation is sent to it. |
| R2 | The pass reads Nomi's answers, which include web results. A web page can say "always reply in English" and that could become a lasting "preference". | Learn from the student's own messages; pass answers only as context and tell the model not to store anything that appears only in Nomi's answer or a source. Reject items that read as instructions about tools, links, or sources. |
| R3 | The secret filter blocks any item containing "token", so "struggles with tokenization in NLP" is dropped. | Match `api token`, `access token`, `token:` / `token=` and long random strings instead of the bare word. Same for 密钥 (keep), but allow 秘钥 only with a following key-like string. |
| R4 | A local question waits for a running memory pass (up to 400 tokens). With the engine allowing one chat job at a time, this adds seconds to the next answer. | Move the pass into `AfterAnswerJobs` (P3), cap local background `maxTokens` at 300, and only start it after 30 s of quiet (already done). Engine follow-up: stop a generation when its HTTP client disconnects, so a cancelled background job frees the worker. |
| R5 | On an API failure the same turns are retried after every answer, with no limit. | Back off: after a failure, wait for 3 more turns before retrying; give up on a batch after 3 failures and move `learnedThrough` past it. |
| R6 | `MemoryLearning.prompt` cuts answers at 400 characters and includes demo HTML. | Use `ChatHistory.cleanedAnswer` (P2). |
| R7 | `memory.json` holds personal facts; it is written with default permissions. | Write with 0600, like the dev key file. |
| R8 | Memory is added to the meeting summary prompt (`memoryPrompt(for: meeting.title)`). A preference such as "answers in bullet points" is fine, but "studying for the CPA exam" can steer a neutral summary. | For summaries pass only `style` and `preference` kinds. |

To verify once committed: the note under answers (`AskView.memoryNote`), the Settings section,
`MemoryTests`.

## 10. Data compatibility

All new stored fields are optional and decoded with `decodeIfPresent` or synthesized optional
decoding: `ChatSession.summary`, `Meeting.assistant`, `LLMAPIProfile.contextCharacters`,
`ChatTurn.memoryNote` (already). Old files load unchanged; files written by the new version
load in the old version too (unknown keys are ignored by `JSONDecoder`).

## 11. Privacy

- Everything stays on this Mac: chats, meeting records, `memory.json`.
- New network use: the memory pass calls the selected model; for API models that sends recent
  conversation to the API, so it follows the memory switch (R1) and the Settings text names it.
  The chat summary (P3) only resends turns of the same chat that the same model already received
  when they were asked, so it is always on. Local models send nothing.
- No new secrets are stored.

## 12. Risks

| Risk | Mitigation |
| --- | --- |
| Larger API prompts cost more per question | History and passages only grow when there is something to fill them; short chats cost the same. The profile override can lower it. |
| Summaries drop a detail the student asks about later | Recent turns stay verbatim; older turns are still in `search_library`. |
| Local background jobs slow the next answer | One job at a time, 30 s quiet wait, 300-token cap, cancel-before-start. |
| Chunked meeting summaries are slow on local models | Capped at 4 chunks with progress shown. |
| Changing `ChatContext` while others edit it | Phases P2, P5, P6 run one after another, after the memory work is committed. |

## 13. Estimate

| Phase | Size |
| --- | --- |
| P0 review fixes | 0.5 day |
| P1 budgets | 0.5 day |
| P2 history window | 1 day |
| P3 running summary + shared job queue | 1–1.5 days |
| P4 meeting records + side-panel limits | 1.5 days |
| P5 ranking | 0.5 day |
| P6 follow-up queries | 0.5 day |

About 6 days of work, each phase committed and tested on its own, with the app rebuilt and
checked by hand after P2, P3 and P4.
