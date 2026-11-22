# Queued prompts and steer mode — plan

Status: proposal, waiting for approval. No code has been changed for it.
Branch: `perf/chat-responsiveness`, after `9002811`.

## 1. What changes for the student

Today the composer cannot send while Nomi is answering: the send button turns into Stop, and
Stop throws the partial answer away and puts the question back in the composer.

After this change the student can keep typing and sending while an answer is coming. What a
new message does depends on a setting:

| Mode | Enter while an answer is coming | The other action |
| --- | --- | --- |
| **Queue** (default) | The message joins a queue shown above the composer. When the current answer finishes, the next queued message is sent automatically, in order. | ⌘Enter: steer now |
| **Steer** | The current answer stops where it is, is kept in the chat as an interrupted answer, and the new message is sent at once. The model sees the partial answer and is told the student redirected it. | ⌘Enter: add to queue |

Both actions are always available; the setting only picks which one plain Enter does.
When nothing is being answered, Enter sends as today in both modes.

## 2. Current behaviour this builds on

- `AppModel.ask` refuses while `chatGeneratingID != nil`; `AskView.send` checks the same.
- One answer runs at a time across all chats (`chatGeneratingID`, `chatTask`).
- Stop (`stopChat`) cancels `chatTask`; the catch path calls `restoreDraft`, which discards the
  partial answer and returns the question and images to the composer. No turn is saved.
- API models stop at once (the URLSession request is cancelled).
- The local engine has no cancel. Disconnecting does not stop the worker; the engine stays
  busy, and a new local request is refused (HTTP 409) until the old reply runs to its end.
- After an answer, the chat summary and memory pass run (`scheduleAfterAnswerWork`), and an
  API answer may get a demo page in the background (`startVisual`).

## 3. Data

### 3.1 Queued prompt (in memory)

```swift
struct QueuedPrompt: Identifiable, Equatable {
    var id = UUID()
    var chatID: UUID
    var text: String
    var images: [ChatImageDraft]
    var createdAt: Date
}
```

`AppModel` gains:

```swift
var chatQueue: [QueuedPrompt] = []          // all chats, oldest first
var queuePaused: Set<UUID> = []             // chats whose queue waits for the student
```

- One list for all chats, so the order across chats is the order the student sent them, and
  only one answer runs at a time, as today.
- **Not saved to disk.** Queued images are temporary drafts (`ChatImages.removeTemporary` on
  quit), and a queue is meant to live seconds to minutes. As built: composer drafts are not
  saved across launches either, so there is no draft to put the first queued text back into;
  on quit the queue is dropped like any unsent draft.

### 3.2 Interrupted answers (saved)

`ChatTurn` gains `var interrupted: Bool? = nil` (decoded with `decodeIfPresent`; old chats load
unchanged). An interrupted turn keeps the answer as shown at the moment of the interruption,
tool markers removed, with its citations.

- The history window (`ChatHistory.window`) shows it as
  `Answer (interrupted by the student): …`, so the model knows it was cut off.
- Library search and the memory pass treat it like any other turn.
- The chat shows a small caption under it: "已打断" / "Interrupted".

## 4. Behaviour

### 4.1 Sending while an answer is coming

`AppModel.ask(…)` gains a `when busy` argument (`.queue` or `.steer`) taken from the setting,
or the other one for ⌘Enter.

- **Nothing running:** send as today.
- **Queue:** append a `QueuedPrompt` for the composer's chat; clear the composer. Images move
  from `composerImages[chatID]` into the queued item.
- **Steer, same chat:** interrupt (4.3), then send the new message at once, ahead of the queue.
- **Steer, another chat is answering:** treated as Queue. Interrupting a different chat's
  answer from here would surprise the student; the composer hint says so ("另一段对话正在回答，
  已排队").

### 4.2 Advancing the queue

When an answer finishes successfully (`finishChat` with no error):

1. If the chat that just finished has an unpaused item, send it next; otherwise the oldest
   unpaused item of any chat.
2. A local model sends the next item before the after-answer work (summary, memory), which
   already waits for a quiet moment; for a local model the background demo is skipped while
   the queue is not empty, because it would hold the only worker. API demos run as today.
3. The next item uses the model, scope and Web switch of its chat at the moment it is sent.

The queue does not advance, and the chat's queue is marked paused, when:

- the answer failed (error shown) — the student may want to fix the model or key first;
- the student pressed Stop;
- `canGenerateAssistant` is false (model missing, switching models).

A paused queue shows "已暂停" with a Resume button. Sending anything new in that chat resumes it.

### 4.3 Interrupting (steer)

1. Remember what the answer showed so far (`pendingAnswer`, `pendingCitations`).
2. Cancel the running request: API at once; local through the engine cancel (section 6).
3. If something was shown, save it as a turn with `interrupted = true`. If nothing had appeared
   yet, save nothing (the question is simply superseded); the old question is kept as a turn
   with an empty interrupted answer only if it had images, so they are not lost.
4. Send the new message. Its prompt adds one line after the history:
   "The student interrupted your previous answer to say the message below. Take it into
   account; continue or change course as it asks, without repeating what was already said."
5. Demo pages and after-answer work are not started for the interrupted turn.

### 4.4 Stop

Unchanged: Stop discards the partial answer and puts the question back in the composer. It
also pauses this chat's queue, so the next queued message is not sent behind the student's
back right after they asked to stop.

### 4.5 Other cases

| Case | Behaviour |
| --- | --- |
| Chat deleted | Its queued items are removed and their images discarded. |
| Switching chats | Each chat shows only its own queue; items keep running in order in the background. |
| Meeting-embedded chat | Same queue and modes; the list sits above that composer. |
| Empty text with images | Allowed in the queue, as for a normal send. |
| Editing a queued item | Moves it back into the composer (text and images) and removes it from the queue. |
| Recording running | No conflict; chat already runs during recordings. |

## 5. Interface

### 5.1 Composer while an answer is coming

- The text field stays enabled.
- Two buttons on the right: **Stop** (square) and **Send**. Send shows the action Enter will
  take: `text.line.first.and.arrowtriangle.forward` style "queue" icon in Queue mode, an
  `arrow.uturn.right` "steer" icon in Steer mode; disabled when the field is empty.
- A one-line hint under the field: "Enter 排队 · ⌘Enter 立即打断" or "Enter 立即打断 · ⌘Enter 排队".
- When nothing is running, the composer looks exactly as today.

### 5.2 Queue list

Shown above the composer, only when the current chat has queued items:

```
排队中 2 条                                   全部清除
1  解释一下量子纠缠的应用                  ✎  ⤴  ✕
2  🖼 1  再给我一个例子                        ✎  ⤴  ✕
```

- Up to three rows visible, then it scrolls. Text is one line, truncated.
- ✎ edit (moves into the composer), ⤴ send now (steer with this item), ✕ remove.
- Rows can be reordered by dragging.
- Paused: header reads "已暂停 · 2 条" with a "继续" button.
- Same light card style as the composer; no new colours.

### 5.3 Settings

In Settings → 提问与摘要大模型 (Questions & Summaries), a new row:

| Label | Control |
| --- | --- |
| 回答中发送新消息 / Sending while Nomi is answering | Segmented: **排队 / Queue** · **打断并引导 / Steer** |

Caption: "排队：等这条回答结束后依次发送。打断并引导：立即停下当前回答，保留已写的部分，按新消息继续。"
Stored as `nomi.chat.busySend` (`queue` default, `steer`).

## 6. Local engine cancel

Steer is only useful on local models if the answer stops quickly. Add a real cancel:

- **Worker (`llm-worker`):** installs a `SIGUSR1` handler that sets an atomic flag. The token
  loop checks the flag after each token and, when set, ends the reply early with a normal
  `Result` containing the text so far plus `"cancelled": true`. The flag is cleared at the start
  of every request. No change to the frame protocol beyond that optional field.
- **Engine (`moxin-engine`):** `POST /v1/assistant/cancel` sends `SIGUSR1` to the chat worker
  that is answering (`Busy.assistant_pid`, already tracked). Also, when the HTTP client of a
  reply disconnects (`tx.send` fails), the engine sends the same signal, so a cancelled request
  frees the worker within one token.
- **App (`LocalEngine`):** `cancelGeneration()` calls the endpoint; `AppModel` calls it on Stop
  and on steer, and the after-answer queue uses it to drop a background job when a question
  arrives (closing the R4 follow-up from the memory plan).

## 7. Files

| File | Change |
| --- | --- |
| `Models/ChatQueue.swift` (new) | `QueuedPrompt`, `BusySendMode`, pure queue rules (next item, pause rules) |
| `App/AppModel+ChatQueue.swift` (new) | enqueue, advance, pause/resume, steer, cleanup on delete and quit |
| `App/AppModel+Chat.swift` | `ask(…, whenBusy:)`, interrupted turn saving, steer prompt line, advance after finish, pause on stop/error, skip local demo while queued |
| `App/AppModel.swift` | `chatQueue`, `queuePaused`; restore first queued text on quit |
| `Models/ChatSession.swift` | `ChatTurn.interrupted` |
| `Models/ChatHistory.swift` | label interrupted answers |
| `Pages/AskView.swift` | composer buttons and hint, ⌘Enter, queue list |
| `Pages/AskComposer.swift` | report ⌘Enter separately from Enter |
| `Pages/ChatQueueList.swift` (new) | the queue list view |
| `Pages/LLMSettingsSection.swift` | the setting row |
| `Engine/LocalEngine.swift` | `cancelGeneration()` |
| `Backend/moxin-engine/src/main.rs` | cancel endpoint, cancel on disconnect |
| `Backend/workers/llm-worker/src/main.rs` | SIGUSR1 flag, early `Result` |
| `Resources/en.lproj/Localizable.strings` | new strings (and the parse test guards the file) |

## 8. Tests

Pure rules (`ChatQueueTests`):
- Next item: same chat first, then oldest across chats; paused chats skipped.
- Pause on error, on Stop, when the model is unavailable; resume on Resume or a new send.
- Steer in another chat falls back to queue.
- Deleting a chat removes its items.
- ⌘Enter swaps the action in both modes.

Turns and prompts:
- An interrupted turn is saved with the shown text and `interrupted = true`; old chats decode.
- The history window labels it; the steer line is added only after an interruption.
- Nothing shown yet → no empty turn (except the images case).

Engine:
- Rust unit test: the worker's token loop stops after the flag is set and returns the partial
  text with `cancelled`.
- Manual: a local reply stops within a second after Stop or steer, and the next question is
  accepted without HTTP 409.

UI (manual, both modes, API and local model):
- Queue three messages during an answer; they run in order; edit, reorder, remove, send now.
- Steer mid-answer; the partial answer stays with the caption; the new answer follows the
  redirection.
- Stop with items queued: queue paused, Resume continues.

## 9. Phases

| Phase | Content | Size |
| --- | --- | --- |
| Q1 | Local engine cancel (worker, engine, app) | 1 day |
| Q2 | Queue model, advancing, pause rules, Settings row | 1 day |
| Q3 | Composer changes, ⌘Enter, queue list UI | 1 day |
| Q4 | Steer: interrupted turns, prompt line, history label | 0.5–1 day |
| Q5 | Tests, both modes on API and local, polish | 0.5 day |

Each phase is its own commit. Q1 stands alone and also fixes the slow local Stop today.

## 10. Open questions

- **Q1 Steer and the partial answer:** keep it as an interrupted turn (proposed), or discard it
  like Stop and only send the new message?
- **Q2 Queue on quit:** memory only, with the first queued text put back in the composer
  (proposed), or save the queue with the chat (text only; queued images would be dropped)?
- **Q3 Default mode:** Queue (proposed) or Steer?
- **Q4 Shortcut:** ⌘Enter for the other action (proposed), or ⌥Enter?
