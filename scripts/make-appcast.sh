#!/bin/bash
# Signs the release DMG for Sparkle and writes the update feed.
#
#   bash scripts/build-app.sh release
#   bash scripts/build-dmg.sh
#   bash scripts/make-appcast.sh [release-notes.md]
#
# Writes build/updates/appcast.xml and build/updates/Nomi-arm64.dmg. Attach both to the
# GitHub release tagged v<version>, and mark it Latest: the app reads
# https://github.com/Jasonsu22/Nomi/releases/latest/download/appcast.xml once a day.
#
# The EdDSA private key lives in the login Keychain (Sparkle's generate_keys); a backup is in
# ~/Library/Application Support/Nomi-release/. Without it no update can be signed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/Nomi.app"
tools="$root/.build/artifacts/sparkle/Sparkle/bin"
notes="${1:-}"

if [[ ! -x "$tools/generate_appcast" ]]; then
    echo "缺少 Sparkle 工具，先运行 swift package resolve。" >&2
    exit 1
fi
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
dmg="$root/build/Nomi-$version-arm64.dmg"
if [[ ! -f "$dmg" ]]; then
    echo "没有找到 $dmg，先运行 scripts/build-dmg.sh。" >&2
    exit 1
fi

updates="$root/build/updates"
rm -rf "$updates"
mkdir -p "$updates"
# The feed points at the release asset by this stable name.
cp "$dmg" "$updates/Nomi-arm64.dmg"
if [[ -n "$notes" ]]; then
    cp "$notes" "$updates/Nomi-arm64.${notes##*.}"
fi

"$tools/generate_appcast" \
    --download-url-prefix "https://github.com/Jasonsu22/Nomi/releases/download/v$version/" \
    --embed-release-notes \
    --maximum-deltas 0 \
    "$updates"

echo "写好了 $updates/appcast.xml 和 Nomi-arm64.dmg。把两者附到 GitHub Release v$version，并设为 Latest。"
