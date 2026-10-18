#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

bin_dir="$(swift build -c debug --show-bin-path)"
binary="$bin_dir/LectureNoteApp"
resource_bundle="$(find "$bin_dir" -maxdepth 1 -name '*.bundle' -print -quit)"
if [[ ! -x "$binary" || -z "$resource_bundle" ]]; then
    echo "找不到编译产物：$bin_dir" >&2
    exit 1
fi

app="$root/build/LectureNote.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$binary" "$app/Contents/MacOS/LectureNote"
cp -R "$resource_bundle" "$app/Contents/Resources/"

iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
logo="$root/Design/logo.png"
sips -z 16 16 "$logo" --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32 "$logo" --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$logo" --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64 "$logo" --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$logo" --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256 "$logo" --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$logo" --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512 "$logo" --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$logo" --out "$iconset/icon_512x512.png" >/dev/null
cp "$logo" "$iconset/icon_512x512@2x.png"
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>LectureNote</string>
    <key>CFBundleDisplayName</key>
    <string>LectureNote</string>
    <key>CFBundleIdentifier</key>
    <string>local.lecturenote.preview</string>
    <key>CFBundleExecutable</key>
    <string>LectureNote</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "$app"
