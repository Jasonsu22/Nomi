#!/bin/bash
# Phase 0 on a Mac: the same programs on Metal and CPU, and a comparison of the GGUF models'
# output with the transcript the Mac app (MLX) wrote for the same minutes.
#
#   bash run-phase0-mac.sh
#
# Expects models/ (see models.json) and clips/*.wav, each with a clips/<name>.mac.json beside it
# holding the app's transcript lines for that clip (start, end, source, translation).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"
out="results/mac-$(date +%Y%m%d-%H%M)"
mkdir -p "$out"
asr=target/release/asr-bench
llm=target/release/llm-bench
clips=(clips/*.wav)
audio=()
for clip in "${clips[@]}"; do audio+=(--audio "$clip"); done

for model in Qwen3-ASR-0.6B-Q8_0 Qwen3-ASR-1.7B-Q8_0; do
  for device in gpu cpu; do
    echo "== speech $model on $device"
    "$asr" run --model "models/$model.gguf" --device "$device" "${audio[@]}" --json "$out/asr-$model-$device.json" 2> "$out/asr-$model-$device.log" || echo "failed"
  done
done
for model in Qwen3.5-0.8B-Q4_K_M Qwen3.5-2B-Q4_K_M; do
  for device in gpu cpu; do
    echo "== translation $model on $device"
    "$llm" run --model "models/$model.gguf" --device "$device" --target zh --sentences sentences-en.txt --json "$out/llm-$model-$device-en-zh.json" 2> "$out/llm-$model-$device-en-zh.log" || echo "failed"
    "$llm" run --model "models/$model.gguf" --device "$device" --target en --sentences sentences-zh.txt --json "$out/llm-$model-$device-zh-en.json" 2> "$out/llm-$model-$device-zh-en.log" || echo "failed"
  done
done
# The app's own lecture lines, translated again, to compare with what the Mac app wrote.
python3 -c "import json;lines=[l['source'].strip() for l in json.load(open('clips/english-lecture.mac.json')) if len(l['source'].strip())>20][:10];open('$out/mac-lines-en.txt','w').write(chr(10).join(lines))"
for model in Qwen3.5-0.8B-Q4_K_M Qwen3.5-2B-Q4_K_M; do
  "$llm" run --model "models/$model.gguf" --device gpu --target zh --sentences "$out/mac-lines-en.txt" --json "$out/llm-$model-mac-gpu.json" 2> "$out/llm-$model-mac-gpu.log" || echo "failed"
done
python3 compare.py "$out" | tee "$out/summary.md"
