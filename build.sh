#!/bin/bash
# Builds "RWTH VPN.app" into ./dist. Requires the Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/RWTH VPN.app"
BIN="$APP/Contents/MacOS/RWTHVPN"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/rwth-vpn-helper.sh "$APP/Contents/Resources/rwth-vpn-helper.sh"

swiftc \
    -O \
    -swift-version 5 \
    -target arm64-apple-macos14.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    Sources/*.swift \
    -o "$BIN" \
    -framework AppKit \
    -framework SwiftUI \
    -framework CryptoKit \
    -framework Security

chmod +x "$BIN"

# Dock icon: render once at 1024 px, then let iconutil build the .icns.
"$BIN" --render-icon "$SCRATCH/icon-1024.png" >/dev/null
ICONSET="$SCRATCH/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SCRATCH/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SCRATCH/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built: $APP"
