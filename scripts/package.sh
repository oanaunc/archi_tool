#!/bin/bash
# Builds a universal Developer ID-signed, notarized DMG in dist/.
# NOTARY_PROFILE defaults to the keychain profile "oanarina-notary"; set NOTARY_PROFILE= (empty) to skip notarization.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="Oanarina Archi Tool"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/app/Info.plist")"
IDENTITY="${SIGNING_IDENTITY:-16B4420E76E5FB9B5EB8C984B5A54C07D7E8B739}"
NOTARY_PROFILE="${NOTARY_PROFILE-oanarina-notary}"
APP="$ROOT/build/$NAME.app"
DMG="$ROOT/dist/Oanarina-Archi-Tool-$VERSION.dmg"
mkdir -p "$ROOT/dist"

CONFIG=release "$ROOT/scripts/build.sh"

# Sign inner executables first, then the bundle, with the hardened runtime.
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP/Contents/MacOS/archi-cli"
codesign --force --timestamp --options runtime --entitlements "$ROOT/app/ArchiTool.entitlements" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$2"
  cat "$2"
  python3 - "$2" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
if r.get("status") != "Accepted":
    sys.exit("Notarization did not succeed: " + str(r.get("status")))
PY
}

if [[ -n "$NOTARY_PROFILE" ]]; then
  ditto -c -k --keepParent "$APP" "$ROOT/dist/notarize.zip"
  notarize "$ROOT/dist/notarize.zip" "$ROOT/build/notary-app.json"
  xcrun stapler staple "$APP"
fi

STAGE="$(mktemp -d "$ROOT/build/dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/LICENSE" "$STAGE/License (GPL-3.0).txt"
rm -f "$DMG"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

if [[ -n "$NOTARY_PROFILE" ]]; then
  notarize "$DMG" "$ROOT/build/notary-dmg.json"
  xcrun stapler staple "$DMG"
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  echo "NOTARIZED OK"
else
  echo 'Signed build only: NOT notarized.'
fi
(cd "$ROOT/dist" && shasum -a 256 "$(basename "$DMG")" > SHA256SUMS.txt)
ls -la "$DMG"; cat "$ROOT/dist/SHA256SUMS.txt"
