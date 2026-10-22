#!/bin/bash
# Smoke-test the vendored openconnect without touching the network.
set -euo pipefail
cd "$(dirname "$0")/.."

VENDOR=$(cd "${1:-build/vendor}" && pwd -P)
BIN="$VENDOR/openconnect"

[ -x "$BIN" ] || { echo "missing $BIN (run ./build.sh)"; exit 1; }

echo "==> version"
"$BIN" --version

echo "==> load commands"
LEAKS=$(otool -L "$BIN" | tail -n +2 | grep "/opt/homebrew" || true)
if [ -n "$LEAKS" ]; then
    echo "error: binary still links against Homebrew:" >&2
    echo "$LEAKS" >&2
    exit 1
fi

echo "==> dylibs resolve"
"$BIN" --version | grep -q "Using GnuTLS" \
    || { echo "error: bundled GnuTLS did not load" >&2; exit 1; }

echo "==> vpnc-script present"
[ -x "$VENDOR/vpnc-script" ] || { echo "error: vpnc-script missing" >&2; exit 1; }

echo "==> CA bundle present"
[ -s "$VENDOR/cert.pem" ] || { echo "error: cert.pem missing" >&2; exit 1; }

echo "bundled client OK"
