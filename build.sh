#!/bin/bash
# Builds the standalone rwth-vpn CLI into ./dist for Apple Silicon macOS.
set -euo pipefail
cd "$(dirname "$0")"

CLI_BIN="dist/rwth-vpn"
RESOURCE_DIR="dist/resources"
VENDOR="build/vendor"

for arg in "$@"; do
    case "$arg" in
        --revendor) rm -rf "$VENDOR" ;;
        *) echo "unknown argument: $arg" >&2; exit 64 ;;
    esac
done

if [ ! -f "$VENDOR/MANIFEST.sha256" ]; then
    echo "==> bundling openconnect"
    ./scripts/bundle-openconnect.py --out "$VENDOR"
fi

echo "==> compiling CLI"
mkdir -p dist
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

echo "==> packaging resources"
rm -rf "$RESOURCE_DIR"
mkdir -p "$RESOURCE_DIR"
cp Resources/helper-version.txt "$RESOURCE_DIR/helper-version.txt"
HELPER_VERSION="$(tr -d '[:space:]' < Resources/helper-version.txt)"
sed "s/{{HELPER_VERSION}}/$HELPER_VERSION/" Resources/rwth-vpn-helper.sh \
    > "$RESOURCE_DIR/rwth-vpn-helper.sh"
cp -R "$VENDOR" "$RESOURCE_DIR/openconnect"
cp THIRD-PARTY-NOTICES.md "$RESOURCE_DIR/THIRD-PARTY-NOTICES.md"
cp -R licenses "$RESOURCE_DIR/licenses"

echo "Built CLI: $CLI_BIN"
echo "Resources: $RESOURCE_DIR"
