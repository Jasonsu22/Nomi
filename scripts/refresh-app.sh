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
app_bundle="$bin_dir/LectureNoteApp_LectureNoteApp.bundle"
if [[ ! -x "$binary" || ! -d "$app_bundle" ]]; then
    echo "Swift 构建没有产出程序或资源包。" >&2
    exit 1
fi

cp "$binary" "$app/Contents/MacOS/Nomi"
rm -rf "$app/Contents/Resources/"*.bundle
for bundle in "$bin_dir"/*.bundle; do
    [[ -d "$bundle" ]] || continue
    cp -R "$bundle" "$app/Contents/Resources/"
done
touch "$app"
"$root/scripts/sign-app.sh" "$app"
echo "$app"
