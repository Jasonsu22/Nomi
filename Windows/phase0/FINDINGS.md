# Phase 0 findings so far

Measured on a MacBook with an Apple M5 (4 performance + 6 efficiency cores), CPU only, on two 5-minute
clips from real lectures: a mixed Chinese/English NLP class and an English lecture. Windows PCs are still
to be measured; these numbers show the method works and where the limits are.

## Speech, CPU only, live timing

"Text ready" is how long after a phrase ends its text appears, queueing included.
"Behind" is how far the model still lags when the clip ends.

| Model | Interim text | Load | Text ready, mean | p90 | max | Behind at end |
|---|---|---:|---:|---:|---:|---:|
| Qwen3-ASR 0.6B | every pass (today's engine) | 0.36–0.57 | 1.0–3.3 s | 2.3–4.7 s | 7.1 s | 1–2 s |
| Qwen3-ASR 0.6B | skip when busy | 0.31–0.44 | 0.9–2.7 s | 1.8–3.7 s | 8.5 s | 1 s |
| Qwen3-ASR 0.6B | off | 0.13 | 0.9–1.7 s | 1.7–2.1 s | 4.3 s | 1 s |
| Qwen3-ASR 1.7B | skip when busy | 0.73–0.84 | 2.6–7.0 s | 6.5–8.9 s | 9.8 s | 2–7 s |
| Qwen3-ASR 1.7B | off | 0.28–0.31 | 2.2–3.7 s | 4.1–4.3 s | 6.9 s | 2–3 s |

- The 0.6B model keeps up on a CPU alone in every mode.
- The 1.7B model on a CPU alone keeps up only with interim text off; with it on, text arrives up to 10 s late
  on the mixed-language class.
- An earlier run of the same 0.6B CPU test measured about three times slower (load 1.1–1.7). The Mac was
  likely busy with other work then. Each measurement needs repeating, and the Windows kit should record what
  else is running.

## Translation, CPU only

| Model | Per sentence | Tokens/s | Quality |
|---|---|---:|---|
| Qwen3.5 2B | 0.4–0.8 s | ~54 | Good |
| Qwen3.5 0.8B | 0.2–0.5 s | ~112 | Weaker: left terms untranslated, mistranslated "key", garbled a sentence |

Translation is not the bottleneck on a CPU. The 0.8B model mainly saves memory.

## Speech on the M5's GPU (Metal), every interim pass

| Model | Load | Load, interim off |
|---|---:|---:|
| Qwen3-ASR 0.6B | 0.31–0.45 | 0.09–0.10 |
| Qwen3-ASR 1.7B | 0.78–0.99 | 0.18–0.21 |

## What this changes in the plan

1. **The engine should skip an interim pass when the model is busy.** Today it runs every one, so on a slow
   device the text falls further behind. End-of-phrase passes always run, so no text is lost; the grey
   text just updates less often. This is a change to `moxin-engine` and helps slow Macs too.
2. **Interim text is the main cost.** Each pass re-reads the growing phrase from its start, so it is 60–80%
   of the speech model's work. The device check should decide between "on", "skip when busy" and "off".
3. **A CPU-only PC is a real target.** With the 0.6B speech model and the 2B translation model, a strong
   laptop CPU keeps up. Weaker CPUs are still unmeasured; for them the Lite set may need interim text off or
   SenseVoice.
4. **The 1.7B speech model belongs on a GPU,** or on a CPU with interim text off.

## Still to measure

- The Huawei laptop (Core Ultra 9 185H, Arc integrated) and the second Windows PC, CPU and Vulkan.
- Both models running together.
- A low-end CPU (4 cores, no AVX-512).
- The Mac app's MLX transcript against these GGUF transcripts (`compare.py`).
