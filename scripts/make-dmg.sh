#!/bin/bash
# Packages dist/RWTH VPN.app into a compressed DMG with an /Applications link.
# The app must already be built (./build.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/RWTH VPN.app"
[ -d "$APP" ] || { echo "build the app first: ./build.sh" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/RWTH VPN-$VERSION.dmg"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "RWTH VPN" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "DMG: $DMG"
