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

# Development key mode keeps API keys in a private file after the first keychain
# approval, so rebuilds stop asking. It is on for debug builds and off for release
# builds unless NOMI_DEV_KEYS=1. Never give anyone a build made with it on.
dev_keys="${NOMI_DEV_KEYS:-}"
if [[ -z "$dev_keys" ]]; then
    [[ "$config" == debug ]] && dev_keys=1 || dev_keys=0
fi
swift_args=(-c "$config")
if [[ "$dev_keys" == 1 ]]; then
    swift_args+=(-Xswiftc -DNOMI_DEV_KEYS)
fi

# Build the backend from this repository; a missing worker must fail packaging.
cargo_args=(build --locked --manifest-path "$root/Backend/Cargo.toml" --target-dir "$root/Backend/target" -p moxin-engine -p asr-worker -p llm-worker)
if [[ "$config" == release ]]; then
    cargo_args+=(--release)
fi
cargo "${cargo_args[@]}"
swift build "${swift_args[@]}"
bin_dir="$(swift build "${swift_args[@]}" --show-bin-path)"
binary="$bin_dir/LectureNoteApp"
app_bundle="$bin_dir/LectureNoteApp_LectureNoteApp.bundle"
engine_dir="$root/Backend/target/$config"
for name in moxin-engine asr-worker llm-worker; do
    if [[ ! -x "$engine_dir/$name" ]]; then
        echo "缺少后端程序：$engine_dir/$name" >&2
        exit 1
    fi
done
if [[ ! -x "$binary" || ! -d "$app_bundle" || ! -f "$engine_dir/mlx.metallib" ]]; then
    echo "缺少应用资源或 MLX Metal 库，停止打包。" >&2
    exit 1
fi

# NOMI_APP_PATH builds elsewhere, so a running copy is not replaced mid-recording.
app="${NOMI_APP_PATH:-$root/build/Nomi.app}"
rm -rf "$app" "$root/build/LectureNote.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

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
for bundle in "$bin_dir"/*.bundle; do
    [[ -d "$bundle" ]] || continue
    cp -R "$bundle" "$app/Contents/Resources/"
done
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
    <string>0.6</string>
    <key>CFBundleVersion</key>
    <string>8</string>
    <key>SUFeedURL</key>
    <string>https://github.com/Jasonsu22/Nomi/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>4D8hKp8gvQHZMGNmcGkzmQE5Iri0XgIg+6a4kTYpNUI=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
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
"$root/scripts/sign-app.sh" "$app"
if [[ "$dev_keys" == 1 ]]; then
    echo "开发密钥模式：API 密钥会存到本机文件，不要把这个版本发给别人。" >&2
fi
echo "$app"
