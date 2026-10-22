# Releasing

## Build and verify

1. Update `Sources/AppInfo.swift` and `CHANGELOG.md`.
2. Build and test:

   ```bash
   ./build.sh --revendor
   ./dist/rwth-vpn help
   ./dist/rwth-vpn status
   ./scripts/test-bundled.sh
   ```

3. Package the CLI archive:

   ```bash
   ./scripts/release.sh
   ```

The release contains `rwth-vpn-cli-<version>.tar.gz` and
`SHA256SUMS.txt`. The GitHub workflow publishes those files for the direct
installer and the CLI self-update command.

## Publish

```bash
git add -A
git commit -m "Release v1.2.6"
git tag v1.2.6
git push
git push --tags
```

The release workflow builds the bundled OpenConnect payload, creates the CLI
archive, computes its checksum, and publishes the GitHub release.

## Installer behavior

The direct installer downloads the latest release, verifies its SHA-256
checksum, and installs:

```text
~/.local/bin/rwth-vpn
~/.local/libexec/rwth-vpn/rwth-vpn-cli
~/.local/libexec/rwth-vpn/resources/
```

`rwth-vpn update` uses the same release archive and checksum path to update
the installed CLI in place.
