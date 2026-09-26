#!/bin/bash
# Builds "build/Oanarina Archi Tool.app". CONFIG=release builds a universal binary.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
APP="$ROOT/build/Oanarina Archi Tool.app"
cd "$ROOT/app"
mkdir -p "$ROOT/build"
LOG="$ROOT/build/build.log"
if [[ "$CONFIG" == release ]]; then ARGS=(-c release --arch arm64 --arch x86_64); else ARGS=(-c debug); fi
if ! swift build "${ARGS[@]}" > "$LOG" 2>&1; then
  sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -E "^/.*(error|warning): " | grep -v "warning: (var|immut)" | sed "s|$ROOT/||" | sort -u | head -80
  echo "BUILD FAILED (full log: build/build.log)"; exit 1
fi
BIN="$(swift build "${ARGS[@]}" --show-bin-path)"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ArchiApp" "$APP/Contents/MacOS/Oanarina Archi Tool"
cp "$BIN/archi-cli" "$APP/Contents/MacOS/archi-cli"
cp "$ROOT/app/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/app/Resources/." "$APP/Contents/Resources/" 2>/dev/null || true
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
mkdir -p "$APP/Contents/Resources/Samples" && cp -R "$ROOT/assets/demo/." "$APP/Contents/Resources/Samples/"
mkdir -p "$APP/Contents/Resources/tutorials" && cp -R "$ROOT/tutorials/." "$APP/Contents/Resources/tutorials/"
cp "$ROOT"/docs/*.md "$APP/Contents/Resources/" 2>/dev/null || true
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "BUILD OK: $APP"
