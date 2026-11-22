# Nomi for Windows: Phase 0

Before any Windows screen is built, this measures whether a PC can run Nomi's models live, and which model set suits it. The plan is in [docs/windows-plan.md](../../docs/windows-plan.md), section 10.

## What it measures

- **Speech** (Qwen3-ASR 0.6B and 1.7B) on recorded lectures, cut into phrases by Nomi's own phrase cutter (`voice-core`), with the interim passes the live view makes.
- **Translation** (Qwen3.5 0.8B and 2B) of lecture sentences, English→Chinese and Chinese→English, with the Mac's translation prompt and the model's own chat template, thinking off.
- **Both together**, as during a lecture: speech running while a sentence is translated every 4 seconds, in every placement (both on the CPU, speech on the GPU, both on the GPU, …).
- On the GPU through **Vulkan**, which covers Intel, AMD and NVIDIA, and on the **CPU alone**. One build picks the best CPU code at run time (AVX2, AVX-512, …), so it runs on old and new PCs.

The speech and translation programs are separate, as in the app: transcribe.cpp and llama.cpp each carry their own copy of ggml.

## Run it on a Windows PC

1. Download the kit: the `nomi-phase0-windows-x64` artifact from the latest "Windows phase 0" run on GitHub Actions.
2. Put a few lecture recordings in `clips\` as WAV files, any sample rate, 3–10 minutes each. Without them it uses a 35-second public sample, which says much less.
3. Plug the laptop in, close other heavy apps, and double-click `run-phase0.cmd`.
   - Full run: about 30–60 minutes, about 4.8 GB of models downloaded once.
   - `run-phase0.cmd -Quick`: one clip and the small models only, about 10 minutes.
   - `-CpuOnly` skips the GPU even if there is one.
4. Send back the zip it names at the end, `results\<PC>-<date>.zip`.

Models come from huggingface.co, or from hf-mirror.com when that is blocked (mainland China). Nothing is installed. Recordings and results stay on the PC until you send them.

## Reading the results

`summary.md` in the results folder has three tables.

- **Load** is model time divided by audio time. Under 1.0 the model keeps up; the pass marks leave room for translation and the rest of the PC.
- **Load, interim off** counts only the end-of-phrase passes: what a slow PC would do with the grey interim text turned off.
- The last table gives each set and placement one of three results:
  - **Live, with interim text**: speech load ≤ 0.6 and translation p90 ≤ 2 s;
  - **Live, interim text off**: speech load without interim ≤ 0.5 and translation p90 ≤ 2.5 s;
  - **Too slow**.

The pass marks are in `models.json` and are first guesses, to be tuned with real results.

## On a Mac

`bash run-phase0-mac.sh` runs the same programs on Metal and CPU, then `compare.py` checks the GGUF models against the transcript and translations the Mac app (MLX) wrote for the same minutes. Each clip needs a `clips/<name>.mac.json` beside it.

Building needs CMake and Xcode's command-line tools:

```bash
cargo build --release
```

## Files

| File | What it is |
|---|---|
| `asr-bench/` | Speech benchmark (transcribe.cpp) |
| `llm-bench/` | Translation benchmark (llama.cpp) |
| `run-phase0.ps1`, `run-phase0.cmd` | The Windows run |
| `run-phase0-mac.sh`, `compare.py` | The Mac run and comparison with the app |
| `models.json` | Models, download sources, sets and pass marks |
| `sentences-en.txt`, `sentences-zh.txt` | Lecture sentences for translation |
| `../../.github/workflows/windows-phase0.yml` | Builds the Windows kit, and runs a quick CPU check on GitHub's runner |

`clips/`, `models/` and `results/` are not committed: recordings are private, models are large.
