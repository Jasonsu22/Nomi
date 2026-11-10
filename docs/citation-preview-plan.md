# Citation previews and jumps: plan

> Written 2026-11-09. Nothing is built yet; work starts after your go-ahead and your answers in section 7.
> Interactive preview: `Design/Previews/citation-preview.html` (also published as a page).

## 1. What we want

1. **Hover a citation and see what it points to.** The card differs by kind:
   - a lecture shows the words spoken at that moment;
   - a PDF shows the page and the passage;
   - a web page shows its title, site and snippet;
   - and so on for each kind in section 3.
2. **Click a lecture citation** and the meeting opens with the transcript scrolled to that moment, the
   line lit for a second (the highlight built today).
3. Every kind of citation gets its own preview: lectures, meeting summaries, PDF, PowerPoint, Word,
   text and other files, pictures, web pages, and earlier chats.

## 2. What happens today, and why every card looks the same

- When an answer finishes, each `[n]` becomes a `ChatCitation` holding only `title`, `detail` (for
  example "31:20" or "第 2 页"), and an ID or URL (`ChatContext.citations`). The passage text, the exact
  second and the page number are dropped.
- The hover card (`CitePreviewCard` in `AnswerBody.swift`) can only show an icon, the title, the detail
  and "Open". So a lecture, a PDF and a web page all look alike.
- Clicking calls `openCitation`, which opens the meeting (`openMeeting(id)`) without a time, so the
  transcript starts at the top. PDFs and other files open in their own app at page 1.

## 3. Design

### 3.1 Cards by kind

| Kind | Top line | Body | Click / Open |
|---|---|---|---|
| **Lecture moment** | clock icon · meeting title · date · **31:20** | The spoken line(s) at that moment as a quote, with the cited sentence in bold; the translation underneath in grey; "▶ 听这一段" plays 10 s of that recording (question 3) | Opens the meeting and jumps the transcript to 31:20, line lit |
| **Meeting summary** | sparkle icon · meeting title · 摘要 | The summary paragraph that was cited | Opens the meeting's Summary tab |
| **PDF / slides** | document icon · file name · **第 3 页** | A small picture of that page (PDFKit) next to the passage, cited sentence marked | Opens the file at that page (question 2) |
| **Word / text / other files** | the file's own icon · name · section | The passage, cited sentence marked | Opens the file |
| **Picture** | photo icon · name | The picture itself, and text read from it if it was used | Opens the picture viewer |
| **Web page** | site icon · site · date if known | Page title in bold, then the search snippet that was cited; a preview image when the site has one (question 4) | Opens the page in the browser |
| **Earlier chat** | chat icon · chat title · date | The earlier question and the start of its answer | Opens that chat |

Common to all of them:
- About 340 pt wide, at most about 8 lines of text, and the same look in light and dark.
- "Open ↗" sits at the top right, and "Copy quote" appears on hover.
- A **missing** source (a deleted file, a removed meeting) says so instead of showing an empty card.

### 3.2 Hover behaviour (from Radix HoverCard, Wikipedia Page Previews, Telerik Citation)

- The card opens after **350 ms** on the chip and closes **250 ms** after the pointer leaves. The
  pointer can travel into the card without it closing.
- Moving straight from one citation to the next **switches the card at once**, with no second wait,
  the way Telerik's citation popover does.
- Esc closes the card. Clicking the chip does the card's main action, as in the table above.

### 3.3 "Found in N sources" row (as in the promo video)

Above an answer that cites material, one row of chips lists each distinct source once, for example
"Lecture 6 · Oct 14", "Syllabus.pdf" and "Chat · Exam prep". The chips hover and click like the inline
ones (question 1).

## 4. Where the data comes from

Previews are built **when you hover**, from Nomi's own data, so old chats get rich cards too:

- **New citations** store a little more: `at` (seconds into the meeting), `page`, and `excerpt` (up to
  about 400 characters of the passage). `ContextBlock` gains `at` and `page` when the passage is made
  (`passageBlocks`, `SourceText`, `LibrarySearch`), so nothing has to be guessed.
- **Old citations** (saved before this) are filled in at hover time:
  - the time comes from the "31:20" in `detail`;
  - the quote comes from the meeting paragraph at that time;
  - a file's passage comes from `SourceTextCache` by page;
  - a web snippet is not recoverable, so its card shows the title and site only.
- **Which sentence is the cited one:** the answer sentence that carries `[n]` is compared word by word
  with the passage, and the best one to three sentences are bolded. This is the same idea as
  NotebookLM showing the exact quoted text.
- **Lecture jump:** `openCitation` calls `openMeeting(id)` and then `jumpTranscript(id, to: at)`, which
  is already wired to scroll and light the line.
- **Web extras:** the site icon and preview image come from Apple's LinkPresentation
  (`LPMetadataProvider`), fetched once per link and cached. This happens only if you agree (question 4),
  because it contacts the site when you hover.
- **PDF page picture:** `PDFKit` renders the page at 2× thumbnail size, cached per file and page.
  QuickLook (`QLThumbnailGenerator`) gives a first-page picture for Keynote, Pages and the like.

## 5. Work, in order

1. **Data:** `ContextBlock.at/page`, `ChatCitation.at/page/excerpt` (optional, so old chats still
   load), and the hover-time lookup for old citations. Tests for each kind, including a deleted source.
2. **Lecture jump:** `openCitation` jumps to the moment. A test that a citation at 31:20 jumps to the
   paragraph open at 31:20.
3. **Cards:** a `CitationPreviewCard` per kind, replacing `CitePreviewCard`; PDF page pictures; the
   cited-sentence marking.
4. **Hover timing:** the delays and instant switching in 3.2, plus Esc.
5. **"Found in N sources" row** (if yes to question 1).
6. **Extras by your answers:** audio clip, PDF at page, web preview images.
7. **Check in the app** with a real chat that cites a lecture, a PDF, a Word file and a web page; all
   tests; then a test build for you.

Rough size: steps 1–2 about half a day, 3–4 about a day, 5–6 about half a day.

## 6. References

- [Wikipedia Page Previews](https://medium.com/freely-sharing-the-sum-of-all-knowledge/how-we-designed-page-previews-for-wikipedia-and-what-could-be-done-with-them-in-the-future-7a5fa6b07b96):
  a hover delay so cards don't pop up by accident, plus an excerpt and a thumbnail
  ([preview model](https://doc.wikimedia.org/Popups/master/js/js/module-preview_model.html)).
- [Radix Hover Card](https://www.radix-ui.com/primitives/docs/components/hover-card.md): the open and
  close delays, and how the pointer can enter the card.
- [AI SDK Elements: Inline Citation](https://ai-sdk.dev/elements/components/inline-citation) and
  [assistant-ui inline citation](https://www.assistant-ui.com/elements/inline-citation): chips with a
  hover preview of the source.
- [Telerik Citation](https://www.telerik.com/design-system/docs/components/citation/): moving between
  source previews without closing them.
- [NotebookLM citations](https://support.google.com/notebooklm/answer/14276569?hl=en): hovering shows
  the quoted text, and clicking goes to that passage.
- [Apple LinkPresentation](https://developer.apple.com/videos/play/wwdc2019/262): native rich link
  metadata on macOS.

## 7. Decisions for you

My suggestion is in bold.

1. **"Found in N sources" row** above answers, as in the video? **Suggestion: yes.**
2. **PDF citations open at the cited page.** Nomi can show the PDF in its own viewer at that page;
   Preview and other apps can't be told a page. **Suggestion: open in Nomi's viewer at the page, with
   "Open in Preview" next to it.**
3. **"▶ 听这一段"** on lecture cards plays 10 s of the recording from that moment. **Suggestion: yes.**
   The audio is already saved with each meeting.
4. **Web cards fetch the site's icon and preview image** when you hover (this contacts the site).
   **Suggestion: yes, cached, with a setting to turn it off.**
