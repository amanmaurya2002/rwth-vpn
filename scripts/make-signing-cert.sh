#!/bin/bash
# Creates a self-signed code-signing identity for release builds.
#
#   ./scripts/make-signing-cert.sh "RWTH VPN Releases"
#
# Why: ad-hoc signatures change with every build, so macOS asks for Keychain
# access again after each update. A stable (self-signed) identity keeps the
# designated requirement stable across releases. It does NOT get past
# Gatekeeper — notarization needs a paid Apple Developer account, which this
# project intentionally avoids.
#
# The .p12 produced here is a secret: put it in GitHub Actions secrets
# (SIGN_P12_BASE64, SIGN_P12_PASSWORD) and never commit it.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="${1:-RWTH VPN Releases}"
OUT="build/signing"
mkdir -p "$OUT"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "identity already exists: $NAME"
else
    echo "==> generating self-signed code-signing certificate: $NAME"
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout "$OUT/key.pem" -out "$OUT/cert.pem" \
        -subj "/CN=$NAME/O=RWTH VPN (unofficial)/C=DE" \
        -addext "basicConstraints=critical,CA:FALSE" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning"

    openssl pkcs12 -export \
        -inkey "$OUT/key.pem" -in "$OUT/cert.pem" \
        -name "$NAME" -out "$OUT/identity.p12" \
        -passout pass:rwth-vpn

    echo "==> importing into the login keychain (you may be asked to allow it)"
    security import "$OUT/identity.p12" \
        -k "$HOME/Library/Keychains/login.keychain-db" \
        -P rwth-vpn -T /usr/bin/codesign

    # codesign needs the key to be usable without a UI prompt for automation.
    security set-key-partition-list -S apple-tool:,apple:,codesign: \
        -s -k "" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || true
fi

echo
echo "Available identities:"
security find-identity -v -p codesigning | sed 's/^/  /'
echo
echo "Build a release with:"
echo "  SIGN_IDENTITY=\"$NAME\" ./scripts/release.sh"
echo
echo "For CI, export the identity (base64) and store it as a secret:"
echo "  base64 -i $OUT/identity.p12 | pbcopy   # -> SIGN_P12_BASE64"
echo "  password: rwth-vpn                      # -> SIGN_P12_PASSWORD"
