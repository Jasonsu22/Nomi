#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

config="${1:-debug}"
case "$config" in
    debug|release) ;;
    *)
        echo "用法: build-app.sh [debug|release]" >&2
        exit 1
        ;;
esac

bin_dir="$(swift build -c "$config" --show-bin-path)"
binary="$bin_dir/LectureNoteApp"
resource_bundle="$(find "$bin_dir" -maxdepth 1 -name '*.bundle' -print -quit)"
if [[ ! -x "$binary" || -z "$resource_bundle" ]]; then
    echo "找不到编译产物：$bin_dir" >&2
    exit 1
fi

app="$root/build/Nomi.app"
rm -rf "$app" "$root/build/LectureNote.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$binary" "$app/Contents/MacOS/Nomi"
cp -R "$resource_bundle" "$app/Contents/Resources/"
engine_dir="$root/../Moxin-Voice/target/debug"
for name in moxin-engine asr-worker llm-worker; do
    if [[ -x "$engine_dir/$name" ]]; then
        cp "$engine_dir/$name" "$app/Contents/MacOS/$name"
    fi
done
if [[ -f "$engine_dir/mlx.metallib" ]]; then
    cp "$engine_dir/mlx.metallib" "$app/Contents/MacOS/mlx.metallib"
fi
cp "$root/Design/Brand/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Nomi</string>
    <key>CFBundleDisplayName</key>
    <string>Nomi</string>
    <key>CFBundleIdentifier</key>
    <string>local.nomi.preview</string>
    <key>CFBundleExecutable</key>
    <string>Nomi</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Nomi 需要使用麦克风，把听到的讲座转写成文字。</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

touch "$app"
echo "$app"
