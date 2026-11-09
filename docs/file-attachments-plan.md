# Files in chat: plan

> Written and built 2026-11-09 with the suggested answers in section 5.

## 1. What we want

1. Drag a file from Finder into the chat box, or copy it in Finder (⌘C) and paste it (⌘V), and the
   **file itself** is attached, not its Finder icon.
2. Every file added this way also lands in **Sources › Uncategorized**, so it can be found and used later.
3. Nomi reads the common file types people study with, not only PDF: Word, plain text, Markdown,
   rich text, web pages, spreadsheets, e-books and more.
4. The answer to that question uses the file's text, with source links to the file like any other source.

## 2. What exists today

| Part | Where | Today |
|---|---|---|
| Chat box drop and paste | `Pages/AskComposer.swift` (`SubmitTextView.paste`, `performDragOperation`) → `ChatImages.intake(pasteboard:)` | Images only |
| Image intake | `Models/ChatImage.swift` | Accepts image files and raw bitmaps; 8 images, 10 MB each |
| Sources import | `Pages/SourcesView.swift` (`stage`), `Models/SourceStore.swift` (`stage`, `allowedExtensions`) | pdf, ppt, pptx, key, doc, docx, txt, md, png, jpg, jpeg, heic |
| Reading files | `Models/SourceText.swift` | txt/md, PDF (with text recognition for scanned pages), doc/docx, pptx, images (text recognition). **ppt and key are accepted but nothing is read from them** |
| Feeding a question | `App/AppModel+Chat.swift` (`ask`): sources chosen in the scope → `passageBlocks` → numbered passages in the prompt | Works for Sources picked in the scope |

**Why the Word icon showed up:** when a file is copied or dragged in Finder, the pasteboard carries the
file's location *and* a picture of its icon. `ChatImages.intake(pasteboard:)` finds no image file, then
falls back to "any bitmap on the pasteboard" and takes the icon. The fix is part of step 3.1.

## 3. Design

### 3.1 Getting files into the chat box

- **Drop, paste and the attach button** all go through one intake (`ChatAttachments.intake`), which looks
  at the pasteboard in this order:
  1. **File locations** (Finder copy and drag). Each file is sorted: image → image attachment as today;
     readable document → file attachment; anything else → kept as a file attachment with a
     "Nomi can't read this type" note (see 3.4).
  2. **A real bitmap** (a screenshot, an image copied from a browser) → image attachment, as today.
  3. **Text** → pasted as text, as today.
  The icon bitmap is never used when file locations are present.
- The paperclip button opens a file picker for images *and* documents (today it is images only).
- Limits: 8 attachments per message (images and files together), 50 MB per file (see question 4).
- A folder dropped in is refused with a short note; folder import stays on the Sources page.

### 3.2 How an attached file looks

- A **file chip** in the box above the question, next to image thumbnails: file-type icon, name, size,
  and an × to remove it before sending. Backspace in an empty box removes the last one, as for images.
- After sending, the chip sits above the question bubble on the right, like images do.
  Clicking it opens the file; right-click gives the same menu as demo files (Open, Open with, Save as…,
  Copy path, Reveal in Finder).
- While Nomi copies and reads a large file, the chip shows a small spinner; sending waits for it.

### 3.3 Sources and the answer

- **On send** (not on drop, so a file removed before sending leaves nothing behind), each file is copied
  into the library with `SourceStore.stage(url, categoryID: nil)`, which is the Uncategorized group,
  and added to `model.sources`. A file already in Sources (same name, size and modification date) is
  reused instead of copied twice.
- **That question always uses the attached files**, whatever the scope says: their passages are added to
  the prompt the same way chosen Sources are (`passageBlocks`). Long files are searched for the parts that
  match the question (`LibrarySearch`), so a long book is used in part (question 4).
- The turn remembers its files: `ChatTurn` gets `attachments: [UUID]` (the source IDs), so history,
  follow-up questions and "Continue in Chat" still know about them. Deleting the source later leaves a
  greyed chip that says the file was removed.
- Answers link back to the file with the usual citation chips; clicking opens it in Sources.
- API privacy note: the existing "relevant text goes to the service you choose" rule applies; nothing new is sent.

### 3.4 Reading more file types

One reader, `SourceText`, is used by both the chat box and the Sources page, so both accept exactly the
same list. Additions, using only what macOS already provides plus small readers of our own:

| Type | Extensions | How it is read |
|---|---|---|
| Plain text family | txt, md, markdown, csv, tsv, json, xml, yaml, yml, tex, srt, vtt, log, and common code files (py, swift, js, ts, java, c, cpp, h, go, rs, rb, sh, sql, html as text if not a page) | Read as text; encoding guessed (UTF-8, UTF-16, then GB18030 for older Chinese files, then Latin-1) |
| Rich text and pages | rtf, rtfd, html, htm, odt, webarchive | `NSAttributedString` document reader, the same one TextEdit and `textutil` use |
| Word | doc, docx | As today (`NSAttributedString`) |
| PowerPoint | pptx | As today (unzip, read slide XML), plus speaker notes |
| Excel | xlsx | Our own reader in the same style as pptx: unzip, read `sharedStrings.xml` and each sheet, one passage per sheet as rows of cells. Avoids adding CoreXLSX and its three dependencies |
| E-books | epub | Unzip, read the chapters in spine order through the HTML reader |
| PDF | pdf | As today, including text recognition for scanned pages |
| Images | png, jpg, jpeg, heic, gif, webp, tiff | Image attachment for the model; in Sources, text recognition as today |
| Apple iWork and old Office | key, pages, numbers, ppt, xls | No reader exists in macOS. Shown with a note: "Export to PDF or a newer Office format first" (question 3) |

Reading happens off the main thread and is cached (`SourceTextCache`), so a big file never freezes typing.

### 3.5 Dragging files back out

Attachment chips and rows on the Sources page become draggable: drag one to Finder, the desktop or another
app to get a copy of the file (question 2).

## 4. Work, in order

1. **Fix the icon bug** on its own (small, can ship first): never use the icon bitmap when file locations
   are on the pasteboard.
2. **Readers**: extend `SourceText` and `SourceStore.allowedExtensions` with the table in 3.4; one list
   shared by Sources and chat. Tests with a small sample file of every type in `Tests/Fixtures`.
3. **Chat intake and chips**: `ChatAttachments.intake`, file chips in the composer, the attach button,
   limits and notes. Tests for drop, Finder copy-paste, mixed images and files, limits.
4. **Send path**: stage into Sources on send, de-duplicate, force the files into the question's passages,
   `ChatTurn.attachments`, chips in history. Tests that the passages reach the prompt and the source is
   Uncategorized.
5. **Drag out** of chips and Sources rows.
6. **Check in the app**: drag, copy-paste and attach each type; ask about each; check Sources; build the test
   copy for you to try.

Rough size: steps 1–2 about half a day, 3–4 about a day, 5–6 about half a day.

## 5. Decisions for you

My suggestion is in bold; tell me any you want different.

1. **Chats inside a meeting.** A file attached in a meeting's chat goes to Uncategorized, or to that
   meeting's category (and is linked to the meeting)? **Suggestion: the meeting's category and linked to the
   meeting; Uncategorized everywhere else.**
2. **"Drag them into the Finder".** Did you mean dragging files *out* of Nomi to Finder (3.5), or only
   *from* Finder into Nomi? **Suggestion: both.**
3. **Keynote, Pages, Numbers, old .ppt/.xls.** A clear "export first" note, or a rougher text-recognition
   pass over the file's preview picture (first page or slide only)? **Suggestion: the note.**
4. **Size.** 50 MB per file, and for long files only the parts that match the question are sent?
   **Suggestion: yes.**

## 6. Not in this plan

- Folders, zip archives, audio and video files.
- Editing files inside Nomi.
- Sending the original file to an API as a file upload; only its text is used, as with Sources today.
