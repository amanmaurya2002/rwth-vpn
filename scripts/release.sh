#!/bin/bash
# Local release build: app + DMG + zip + checksums under dist/.
#
#   SIGN_IDENTITY="RWTH VPN Releases" ./scripts/release.sh
#
# Without SIGN_IDENTITY the app is ad-hoc signed (Gatekeeper still blocks it on
# download; the README explains the "Open Anyway" flow either way).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)

./build.sh --revendor --dmg

APP="dist/RWTH VPN.app"
DMG="dist/RWTH VPN-$VERSION.dmg"
ZIP="dist/RWTH VPN-$VERSION.zip"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
shasum -a 256 "$DMG" "$ZIP" > "dist/SHA256SUMS.txt"

echo
echo "Release artefacts for v$VERSION:"
ls -lh "$DMG" "$ZIP" "dist/SHA256SUMS.txt"
echo
echo "Next:"
echo "  1. Update CHANGELOG.md and commit"
echo "  2. git tag -s v$VERSION -m 'v$VERSION' && git push --tags"
echo "  3. Let the GitHub release workflow publish the DMG"
