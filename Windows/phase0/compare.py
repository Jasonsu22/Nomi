"""Summarises a Phase 0 run on the Mac and compares the GGUF models with the Mac app's MLX output.

    python3 compare.py results/mac-<date>

Speech: each clip's transcript against the app's transcript for the same minutes
(clips/<name>.mac.json). The score is character similarity after dropping punctuation and
spaces, so it compares the words, not how they were split into lines.
Translation: lines the app translated, translated again by the GGUF model, side by side.
"""
import difflib
import glob
import json
import os
import re
import sys

out = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))


def words(text):
    return re.sub(r"[\W_]+", "", text.lower())


def similarity(a, b):
    a, b = words(a), words(b)
    if not a and not b:
        return 1.0
    return difflib.SequenceMatcher(None, a, b, autojunk=False).ratio()


print(f"# Phase 0 on this Mac ({os.path.basename(out)})\n")
print("## Speech\n")
print("| Model | Device | Load | Load, interim off | Phrase p90 ms | " + " | ".join(
    os.path.splitext(os.path.basename(p))[0] for p in sorted(glob.glob(os.path.join(here, "clips", "*.wav")))
) + " |")
clips = sorted(glob.glob(os.path.join(here, "clips", "*.wav")))
print("|---|---|---:|---:|---:|" + "---:|" * len(clips))
for path in sorted(glob.glob(os.path.join(out, "asr-*.json"))):
    report = json.load(open(path))
    p90 = max(clip["final_latency_ms_p90"] for clip in report["clips"])
    scores = []
    for clip in report["clips"]:
        reference = os.path.join(here, "clips", os.path.splitext(clip["file"])[0] + ".mac.json")
        if os.path.exists(reference):
            mac = " ".join(line["source"] for line in json.load(open(reference)))
            scores.append(f"{similarity(clip['transcript'], mac):.0%}")
        else:
            scores.append("–")
    print(f"| {report['model']} | {report['device_requested']} ({report['backend']}) | {report['load']:.2f} | "
          f"{report['load_without_interim']:.2f} | {p90:.0f} | " + " | ".join(scores) + " |")
print("\nPercentages: how closely the transcript matches the Mac app's transcript of the same minutes.\n")

print("## Translation\n")
print("| Model | Device | Direction | Mean ms | p90 ms | Tokens/s |")
print("|---|---|---|---:|---:|---:|")
for path in sorted(glob.glob(os.path.join(out, "llm-*.json"))):
    report = json.load(open(path))
    direction = "en-zh" if report["target"] == "zh" else "zh-en"
    if "-mac-" in os.path.basename(path):
        direction += " (lecture lines)"
    print(f"| {report['model']} | {report['device_requested']} | {direction} | {report['total_ms_mean']:.0f} | "
          f"{report['total_ms_p90']:.0f} | {report['tokens_per_second_mean']:.1f} |")

for path in sorted(glob.glob(os.path.join(out, "llm-*-mac-*.json"))):
    report = json.load(open(path))
    reference = {}
    for name in glob.glob(os.path.join(here, "clips", "*.mac.json")):
        for line in json.load(open(name)):
            reference[line["source"].strip()] = line["translation"].strip()
    print(f"\n### {report['model']} on {report['device_requested']}: lecture lines, Mac app vs GGUF\n")
    print("| Source | Mac app (MLX) | GGUF |")
    print("|---|---|---|")
    for sentence in report["sentences"][:8]:
        cell = lambda text: text.replace("|", "\\|").replace("\n", " ")
        print(f"| {cell(sentence['source'])} | {cell(reference.get(sentence['source'].strip(), '–'))} | {cell(sentence['translation'])} |")
