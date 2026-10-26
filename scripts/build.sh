#!/bin/bash
# Builds "build/Oanarina Archi Tool.app". CONFIG=release builds a universal binary.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
OUTPUT_DIR="${APP_OUTPUT_DIR:-$ROOT/build}"
APP="$OUTPUT_DIR/Oanarina Archi Tool.app"
cd "$ROOT/app"
mkdir -p "$OUTPUT_DIR"
LOG="$OUTPUT_DIR/build.log"
if [[ "$CONFIG" == release ]]; then ARGS=(-c release --arch arm64 --arch x86_64); else ARGS=(-c debug); fi
if [[ -n "${APP_BUILD_SCRATCH_PATH:-}" ]]; then ARGS+=(--scratch-path "$APP_BUILD_SCRATCH_PATH"); fi
# SwiftPM's universal linker can stamp the minimum OS as the SDK version. Every universal
# distribution build must retain the declared macOS 14 target (website DMG as well as App Store).
if [[ "$CONFIG" == release || "${APP_STORE_SDK_BUILD:-0}" == 1 ]]; then
  SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
  ARGS+=(-Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION")
fi
if ! swift build "${ARGS[@]}" > "$LOG" 2>&1; then
  sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -E "^/.*(error|warning): " | grep -v "warning: (var|immut)" | sed "s|$ROOT/||" | sort -u | head -80
  echo "BUILD FAILED (full log: $LOG)"; exit 1
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
# Bundle resources must be readable by the user installing the DMG, regardless of source file permissions.
chmod -R a+rX "$APP"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "BUILD OK: $APP"
