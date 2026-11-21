# Windows ↔ Mac parity tracker

The Windows app is a port of the Mac app (`Sources/LectureNoteApp`, 0.10), file by file. Each Swift
file maps to a TypeScript file (logic and screens) or to Rust (`Windows/app/src-tauri`, things that
touch the PC). Mark a row done when the port matches the Mac's behaviour and its tests are ported.

Layout of the port:
- `Windows/app/src/models/`: `Models/*.swift`, `Live/Transcript.swift`, `Categories/Category.swift` (pure logic, vitest tests)
- `Windows/app/src/engine/`: `Engine/*.swift` (engine, remote models, search, downloads)
- `Windows/app/src/app/`: `App/AppModel*.swift` (the app's state and actions, one store)
- `Windows/app/src/views/`: `Shell/`, `Pages/`, `Meetings/`, `Categories/`, `DesignSystem/` views
- `Windows/app/src-tauri/src/`: audio capture, engine process, files, document text, secrets, voices
- Strings: `src/i18n/en.json`, generated from `Resources/en.lproj/Localizable.strings` (Chinese keys, as on Mac)

Platform swaps (Mac → Windows):
- AVAudioEngine microphone → cpal (Rust). AAC recording → WAV (Mac reads WAV too).
- MLX workers → GGUF workers (`Windows/engine`). FluidAudio speakers → sherpa-onnx (Rust).
- PDFKit → pdf.js (viewer) + Rust text extraction. Vision OCR → Windows.Media.Ocr / vision model.
- Keychain → Windows Credential Manager (keyring). Sparkle → GitHub release check.
- WKWebView answer page → the same AnswerWeb files in an iframe.
- NSPanel citation card, compact window, sheets → React layers in the one window.

Status: see the checklist in `Windows/PARITY-STATUS.md`, updated as each file lands.
