#!/bin/bash
# A separate Mac App Store candidate; never replaces the direct-download app or DMG.
# prepare: local ad-hoc sandbox preview. package: distribution-signed installer for Transporter.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-prepare}"
case "$MODE" in prepare|package) ;; *) echo "Usage: $0 [prepare|package]" >&2; exit 2 ;; esac
NAME="Oanarina Archi Tool"
WORK="$ROOT/build/app-store/$MODE"
APP="$WORK/$NAME.app"
OUT="$ROOT/dist/app-store"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/app/Info.plist")"
BASE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$ROOT/app/Info.plist")"
BUILD="${APP_STORE_BUILD_NUMBER:-$((BASE_BUILD + 1))}"
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || { echo 'APP_STORE_BUILD_NUMBER must be a positive integer.' >&2; exit 2; }
mkdir -p "$WORK" "$OUT"
ENTITLEMENTS="$WORK/AppStore.entitlements"
cp "$ROOT/app/ArchiTool-AppStore.entitlements" "$ENTITLEMENTS"

if [[ "$MODE" == package ]]; then
  : "${APP_STORE_APPLICATION_IDENTITY:?Set a Mac App Store application signing identity}"
  : "${APP_STORE_INSTALLER_IDENTITY:?Set a Mac App Store installer signing identity}"
  : "${APP_STORE_PROFILE:?Set the Mac App Store provisioning profile path}"
  [[ -f "$APP_STORE_PROFILE" ]] || { echo 'Provisioning profile not found.' >&2; exit 1; }
  security cms -D -i "$APP_STORE_PROFILE" > "$WORK/profile.plist"
  python3 "$ROOT/scripts/app-store-profile.py" "$WORK/profile.plist" "$ROOT/app/Info.plist" "$ENTITLEMENTS"
  IDENTITY="$APP_STORE_APPLICATION_IDENTITY"
else
  IDENTITY="-"
fi

CONFIG=release APP_STORE_SDK_BUILD=1 APP_BUILD_SCRATCH_PATH="$ROOT/build/app-store/swift" APP_OUTPUT_DIR="$WORK" "$ROOT/scripts/build.sh"
python3 "$ROOT/scripts/stamp-app-store.py" "$APP/Contents/Info.plist" "$BUILD"
cp "$ROOT/app/Resources/PrivacyInfo.xcprivacy" "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT/docs/APP-STORE-PERMISSION.txt" "$APP/Contents/Resources/AppStoreDistributionPermission.txt"
if [[ "$MODE" == package ]]; then cp "$APP_STORE_PROFILE" "$APP/Contents/embedded.provisionprofile"; fi

SIGN=(--force --options runtime --sign "$IDENTITY")
if [[ "$MODE" == package ]]; then SIGN+=(--timestamp); fi
codesign "${SIGN[@]}" \
  --identifier com.oanarina.architool.cli --entitlements "$ROOT/app/ArchiCLI-AppStore.entitlements" "$APP/Contents/MacOS/archi-cli"
codesign "${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
python3 "$ROOT/scripts/verify-app-store.py" "$APP"

if [[ "$MODE" == package ]]; then
  # Developer ID is a different distribution channel and cannot sign an App Store upload.
  codesign -dvv "$APP" > "$WORK/application-signature.txt" 2>&1
  grep -Eq '^Authority=(Apple Distribution:|3rd Party Mac Developer Application:|Mac App Distribution:)' "$WORK/application-signature.txt" || {
    echo 'The application signature is not a Mac App Store distribution identity.' >&2; exit 1;
  }
  codesign --display --extract-certificates="$WORK/signing-cert" "$APP"
  python3 "$ROOT/scripts/app-store-profile.py" "$WORK/profile.plist" "$ROOT/app/Info.plist" "$ENTITLEMENTS" "$WORK/signing-cert0"
  PKG="$OUT/Oanarina-Archi-Tool-$VERSION-$BUILD.pkg"
  productbuild --component "$APP" /Applications --sign "$APP_STORE_INSTALLER_IDENTITY" "$PKG"
  pkgutil --check-signature "$PKG" | tee "$WORK/installer-signature.txt"
  grep -Eq '(3rd Party Mac Developer Installer:|Mac Installer Distribution:)' "$WORK/installer-signature.txt" || {
    echo 'The installer signature is not a Mac App Store installer identity.' >&2; exit 1;
  }
  echo "STORE PACKAGE PREPARED: $PKG"
  echo 'Review licensing and store metadata before uploading with Transporter. This script does not upload.'
else
  ZIP="$OUT/Oanarina-Archi-Tool-$VERSION-$BUILD-sandbox-preview.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "LOCAL SANDBOX PREVIEW: $ZIP"
  echo 'Ad-hoc signed for local testing only; not notarized and not an App Store upload.'
fi
