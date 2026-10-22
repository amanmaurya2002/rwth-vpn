# Contributing

This repository contains a standalone Swift CLI, one shell helper, and the
bundled OpenConnect payload.

## Prerequisites

- Apple Silicon Mac, macOS 26+
- Xcode command line tools (`xcode-select --install`)
- Homebrew with `openconnect` installed for build-time bundling only

## Build and test

```bash
./build.sh
./dist/rwth-vpn help
./dist/rwth-vpn status
./scripts/test-bundled.sh
```

The build produces `dist/rwth-vpn` and `dist/resources/`.

## Layout

```text
Sources/CLI.swift                 CLI commands, updates, and terminal UI
Sources/Helper.swift              privileged helper and payload management
Sources/VPNCore.swift             shared credentials and TOTP access
Sources/TOTP.swift                RFC 6238 TOTP and Base32 parsing
Sources/Keychain.swift            Keychain storage
Resources/rwth-vpn-helper.sh      root helper
Resources/helper-version.txt      helper/payload contract version
scripts/bundle-openconnect.py     vendors OpenConnect and dependencies
```

## Ground rules

- Never put credentials in issues, pull requests, logs, or tests.
- Keep the helper command surface fixed; never accept arbitrary root commands.
- Runtime users must not need Homebrew.
- Bump `Resources/helper-version.txt` when the helper or bundled payload
  changes.
- Keep terminal output clear in both interactive and non-interactive shells.

## Releasing

See [docs/RELEASING.md](docs/RELEASING.md).
