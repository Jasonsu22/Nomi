# Local Qwen3-ASR MLX patch

Source: https://github.com/OminiX-ai/OminiX-MLX/tree/6aac996db8b71fb7dae7a2409c46b4f2ade93092/qwen3-asr-mlx

Vendored from the exact revision used by the workers. Other MLX crates remain pinned to that revision.

Local changes in `src/model.rs`: an empty or `auto` language omits the forced-language assistant prefix; decoding preserves the `<asr_text>` separator in Auto mode and removes the generated language metadata before returning the transcript. Explicit-language behavior is unchanged.

Prompt format and output parsing follow the official Qwen3-ASR implementation:
https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/inference/qwen3_asr.py
https://github.com/QwenLM/Qwen3-ASR/blob/main/qwen_asr/inference/utils.py

Upstream MIT and Apache 2.0 licenses are included.
