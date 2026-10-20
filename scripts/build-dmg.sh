#!/bin/bash
# Packs build/Nomi.app (or the app given as $1) into build/Nomi-<version>-arm64.dmg.
# The DMG window shows a background with "drag Nomi into Applications" and the
# first-launch steps, the Applications shortcut, and an "Open Settings" guide that
# links straight to Privacy & Security. Nomi is not notarized, so students confirm
# it once with "Open Anyway".
#
# The window layout is written by dmgbuild (https://github.com/dmgbuild/dmgbuild),
# installed once into build/.dmgbuild-venv. It writes Finder's layout file itself,
# so it works whatever Finder's tab settings are.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
# Pass another app bundle to package it instead of build/Nomi.app.
app="${1:-$root/build/Nomi.app}"
art="$root/Design/DMG"
logo="$root/Design/Brand/logo-in-app.svg"
guide_name="打开安全设置 · Open Settings.html"
venv="$root/build/.dmgbuild-venv"
dmgbuild_version="1.6.7"

if [[ ! -d "$app/Contents/MacOS" ]]; then
    echo "还没有 build/Nomi.app，先运行 scripts/build-app.sh release。" >&2
    exit 1
fi
# Debug builds and NOMI_DEV_KEYS builds keep API keys in a plain file; never hand those out.
# grep reads all of nm's output (no -q), so pipefail does not see nm cut off early.
if nm "$app/Contents/MacOS/Nomi" 2>/dev/null | grep LocalSecrets >/dev/null; then
    echo "这是调试版或开发密钥模式的版本，不能发给别人。请用 scripts/build-app.sh release 重新编译（不要设 NOMI_DEV_KEYS）。" >&2
    exit 1
fi

# grep reads all of pip's output (no -q), so pipefail does not see pip cut off early.
if ! "$venv/bin/python" -m pip show dmgbuild 2>/dev/null | grep -x "Version: $dmgbuild_version" >/dev/null; then
    echo "Installing dmgbuild $dmgbuild_version into build/.dmgbuild-venv…" >&2
    python3 -m venv "$venv"
    "$venv/bin/python" -m pip install --quiet "dmgbuild==$dmgbuild_version"
fi

version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")"
work="$(mktemp -d "$root/build/dmg-work.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# The guide carries the leaf logo inline, so it is one file that opens in any browser.
python3 -I - "$logo" "$art/open-guide.html" "$work/$guide_name" <<'PY'
import re, sys
logo, source, target = sys.argv[1:4]
svg = open(logo, encoding="utf-8").read()
paths = re.sub(r"(?s)^.*?<svg[^>]*>|</svg>\s*$", "", svg)
paths = re.sub(r"(?s)<title>.*?</title>|<desc>.*?</desc>", "", paths).strip()
page = open(source, encoding="utf-8").read()
assert "{{LOGO_PATHS}}" in page
open(target, "w", encoding="utf-8").write(page.replace("{{LOGO_PATHS}}", paths))
PY

dmg="$root/build/Nomi-$version-arm64.dmg"
rm -f "$dmg"
"$venv/bin/dmgbuild" -s "$art/dmgbuild-settings.py" \
    -D app="$app" -D guide="$work/$guide_name" -D background="$art/background.png" \
    "Nomi" "$dmg" >/dev/null 2> >(grep -v "is deprecated" >&2)
echo "$dmg"
