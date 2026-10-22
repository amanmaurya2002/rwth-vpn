#!/bin/sh
set -eu

REPO="amanmaurya2002/rwth-vpn"
API="https://api.github.com/repos/$REPO/releases/latest"
PREFIX="${RWTH_VPN_PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
LIBEXEC_DIR="$PREFIX/libexec/rwth-vpn"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rwth-vpn-install.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

case "$(uname -s):$(uname -m)" in
  Darwin:arm64) ;;
  *) echo "rwth-vpn currently supports Apple Silicon macOS only." >&2; exit 1 ;;
esac

command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
command -v shasum >/dev/null 2>&1 || { echo "shasum is required." >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar is required." >&2; exit 1; }

echo "Finding the latest rwth-vpn release…"
tag="$(curl -fsSL -H 'Accept: application/vnd.github+json' -A 'rwth-vpn-installer' "$API" |
  sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
[ -n "$tag" ] || { echo "Could not determine the latest release." >&2; exit 1; }
version="${tag#v}"
archive="rwth-vpn-cli-$version.tar.gz"
base="https://github.com/$REPO/releases/download/$tag"

echo "Downloading rwth-vpn ${version}..."
curl -fsSL -o "$TMP_DIR/$archive" "$base/$archive"
curl -fsSL -o "$TMP_DIR/SHA256SUMS.txt" "$base/SHA256SUMS.txt"
expected="$(awk -v name="$archive" '$0 ~ name { print $1; exit }' "$TMP_DIR/SHA256SUMS.txt")"
actual="$(shasum -a 256 "$TMP_DIR/$archive" | awk '{print $1}')"
[ -n "$expected" ] && [ "$expected" = "$actual" ] || {
  echo "Checksum verification failed." >&2
  exit 1
}

mkdir -p "$BIN_DIR" "$LIBEXEC_DIR"
tar -xzf "$TMP_DIR/$archive" -C "$TMP_DIR"
install -m 0755 "$TMP_DIR/rwth-vpn-cli" "$LIBEXEC_DIR/rwth-vpn-cli"
rm -rf "$LIBEXEC_DIR/resources"
cp -R "$TMP_DIR/resources" "$LIBEXEC_DIR/resources"
cat > "$BIN_DIR/rwth-vpn" <<EOF
#!/bin/sh
export RWTH_VPN_RESOURCE_ROOT="$LIBEXEC_DIR/resources"
export RWTH_VPN_INSTALL_ROOT="$PREFIX"
export RWTH_VPN_VERSION="$version"
exec "$LIBEXEC_DIR/rwth-vpn-cli" "\$@"
EOF
chmod 0755 "$BIN_DIR/rwth-vpn"

echo "Installed rwth-vpn $version in $BIN_DIR."
case ":${PATH:-}:" in
  *:"$BIN_DIR":*) ;;
  *) echo "Add it to your shell path: export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac
echo "Next: rwth-vpn setup && rwth-vpn connect"
