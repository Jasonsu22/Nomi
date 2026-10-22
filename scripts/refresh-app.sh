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

# Sparkle (auto-update) ships as a framework next to the executable.
sparkle="$root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$sparkle" ]]; then
    echo "缺少 Sparkle.framework，先运行 swift package resolve。" >&2
    exit 1
fi
mkdir -p "$app/Contents/Frameworks"
rm -rf "$app/Contents/Frameworks/Sparkle.framework"
ditto "$sparkle" "$app/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$app/Contents/MacOS/Nomi" 2>/dev/null || true
rm -rf "$app/Contents/Resources/"*.bundle
for bundle in "$bin_dir"/*.bundle; do
    [[ -d "$bundle" ]] || continue
    cp -R "$bundle" "$app/Contents/Resources/"
done
touch "$app"
"$root/scripts/sign-app.sh" "$app"
echo "$app"
