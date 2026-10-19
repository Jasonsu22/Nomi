#!/bin/bash
# Rebuild the Swift app and copy both the binary and the resource bundle into
# build/Nomi.app. Copying only the binary leaves English strings stale.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

app="$root/build/Nomi.app"
if [[ ! -d "$app/Contents/MacOS" ]]; then
    echo "还没有 $app，先跑一次 scripts/build-app.sh。" >&2
    exit 1
fi

swift build -c debug
bin_dir="$(swift build -c debug --show-bin-path)"
binary="$bin_dir/LectureNoteApp"
bundle="$(find "$bin_dir" -maxdepth 1 -name '*.bundle' -print -quit)"
if [[ ! -x "$binary" || -z "$bundle" ]]; then
    echo "Swift 构建没有产出程序或资源包。" >&2
    exit 1
fi

cp "$binary" "$app/Contents/MacOS/Nomi"
rm -rf "$app/Contents/Resources/"*.bundle
cp -R "$bundle" "$app/Contents/Resources/"
touch "$app"
echo "$app"
