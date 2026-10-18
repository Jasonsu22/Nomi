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

# Build the backend from this repository; a missing worker must fail packaging.
cargo_args=(build --locked --manifest-path "$root/Backend/Cargo.toml" --target-dir "$root/Backend/target" -p moxin-engine -p asr-worker -p llm-worker)
if [[ "$config" == release ]]; then
    cargo_args+=(--release)
fi
cargo "${cargo_args[@]}"
swift build -c "$config"
bin_dir="$(swift build -c "$config" --show-bin-path)"
binary="$bin_dir/LectureNoteApp"
resource_bundle="$(find "$bin_dir" -maxdepth 1 -name '*.bundle' -print -quit)"
engine_dir="$root/Backend/target/$config"
for name in moxin-engine asr-worker llm-worker; do
    if [[ ! -x "$engine_dir/$name" ]]; then
        echo "缺少后端程序：$engine_dir/$name" >&2
        exit 1
    fi
done
if [[ ! -x "$binary" || -z "$resource_bundle" || ! -f "$engine_dir/mlx.metallib" ]]; then
    echo "缺少应用资源或 MLX Metal 库，停止打包。" >&2
    exit 1
fi

app="$root/build/Nomi.app"
rm -rf "$app" "$root/build/LectureNote.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$binary" "$app/Contents/MacOS/Nomi"
cp -R "$resource_bundle" "$app/Contents/Resources/"
for name in moxin-engine asr-worker llm-worker; do
    cp "$engine_dir/$name" "$app/Contents/MacOS/$name"
done
cp "$engine_dir/mlx.metallib" "$app/Contents/MacOS/mlx.metallib"
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
