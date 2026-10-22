#!/bin/bash
# Local release build: CLI archive and checksums under dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(sed -n 's/.*static let cliVersion = "\(.*\)".*/\1/p' Sources/AppInfo.swift)"

./build.sh --revendor

CLI_TARBALL="dist/rwth-vpn-cli-$VERSION.tar.gz"
CLI_STAGE="$(mktemp -d)"
trap 'rm -rf "$CLI_STAGE"' EXIT
cp "dist/rwth-vpn" "$CLI_STAGE/rwth-vpn-cli"
cp -R "dist/resources" "$CLI_STAGE/resources"
tar -czf "$CLI_TARBALL" -C "$CLI_STAGE" rwth-vpn-cli resources
shasum -a 256 "$CLI_TARBALL" > "dist/SHA256SUMS.txt"

echo
echo "Release artefacts for v$VERSION:"
ls -lh "$CLI_TARBALL" "dist/SHA256SUMS.txt"
