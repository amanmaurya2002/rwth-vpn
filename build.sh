#!/bin/bash
# Builds "RWTH VPN.app" into ./dist for Apple Silicon (macOS 26+).
#
#   ./build.sh              build (reuses build/vendor if present)
#   ./build.sh --revendor   re-bundle openconnect from Homebrew first
#   ./build.sh --dmg        also produce dist/RWTH VPN-<version>.dmg
#
# Signing: ad-hoc by default. Set SIGN_IDENTITY to a keychain identity for a
# stable signature across releases (keeps Keychain access without prompts).
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/RWTH VPN.app"
BIN="$APP/Contents/MacOS/RWTHVPN"
CLI_BIN="dist/rwth-vpn"
VENDOR="build/vendor"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DMG=0

for arg in "$@"; do
    case "$arg" in
        --revendor) rm -rf "$VENDOR" ;;
        --dmg) DMG=1 ;;
        *) echo "unknown argument: $arg" >&2; exit 64 ;;
    esac
done

if [ ! -f "$VENDOR/MANIFEST.sha256" ]; then
    echo "==> bundling openconnect"
    ./scripts/bundle-openconnect.py --out "$VENDOR"
fi

echo "==> compiling"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/helper-version.txt "$APP/Contents/Resources/helper-version.txt"
HELPER_VERSION="$(tr -d '[:space:]' < Resources/helper-version.txt)"
sed "s/{{HELPER_VERSION}}/$HELPER_VERSION/" Resources/rwth-vpn-helper.sh \
    > "$APP/Contents/Resources/rwth-vpn-helper.sh"
cp -R "$VENDOR" "$APP/Contents/Resources/openconnect"
cp THIRD-PARTY-NOTICES.md "$APP/Contents/Resources/THIRD-PARTY-NOTICES.md"
cp -R licenses "$APP/Contents/Resources/licenses"

swiftc \
    -O \
    -swift-version 5 \
    -target arm64-apple-macos26.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    Sources/App.swift \
    Sources/AppDelegate.swift \
    Sources/AppInfo.swift \
    Sources/Helper.swift \
    Sources/Icon.swift \
    Sources/Keychain.swift \
    Sources/Preview.swift \
    Sources/SelfTest.swift \
    Sources/TOTP.swift \
    Sources/UpdateController.swift \
    Sources/VPNCore.swift \
    Sources/VPNModel.swift \
    Sources/Views.swift \
    -o "$BIN" \
    -framework AppKit \
    -framework SwiftUI \
    -framework CryptoKit \
    -framework Security

echo "==> compiling CLI"
swiftc \
    -O \
    -swift-version 5 \
    -target arm64-apple-macos26.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    Sources/AppInfo.swift \
    Sources/Keychain.swift \
    Sources/TOTP.swift \
    Sources/VPNCore.swift \
    Sources/Helper.swift \
    Sources/CLI.swift \
    -o "$CLI_BIN" \
    -framework AppKit \
    -framework CryptoKit \
    -framework Security
chmod +x "$CLI_BIN"

chmod +x "$BIN"

echo "==> icon"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
"$BIN" --render-icon "$SCRATCH/icon-1024.png" >/dev/null
ICONSET="$SCRATCH/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SCRATCH/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SCRATCH/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> signing ($SIGN_IDENTITY)"
# Nested Mach-O first: ad-hoc is enough for the bundled client, the app itself
# gets the release identity.
find "$APP/Contents/Resources/openconnect" -type f -perm -111 -print0 \
    | xargs -0 -n1 codesign --force --sign - --timestamp=none >/dev/null 2>&1 || true
codesign --force --sign "$SIGN_IDENTITY" "$APP" >/dev/null 2>&1 || {
    echo "signing failed" >&2
    exit 1
}
codesign --verify --strict "$APP"

echo "==> checking for Homebrew load commands"
LEAKS=0
while IFS= read -r -d '' macho; do
    if otool -L "$macho" | tail -n +2 | grep -q "/opt/homebrew"; then
        echo "error: $macho still links against /opt/homebrew" >&2
        LEAKS=1
    fi
done < <(find "$APP/Contents/Resources/openconnect" -type f -perm -111 -print0)
[ "$LEAKS" = "0" ] || exit 1

if [ "$DMG" = "1" ]; then
    ./scripts/make-dmg.sh
fi

echo "Built app: $APP"
echo "Built CLI: $CLI_BIN"
