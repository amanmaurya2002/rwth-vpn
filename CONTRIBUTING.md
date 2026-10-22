# Contributing

Thanks for helping. This is a small codebase on purpose: two thousand lines of
Swift, one shell helper, no third-party frameworks.

## Prerequisites

- Apple Silicon Mac, macOS 14+
- Xcode command line tools (`xcode-select --install`)
- Homebrew + `brew install openconnect` **for building only** — the release
  build bundles openconnect so users do not need it

## Build and test

```bash
./build.sh                                  # dist/RWTH VPN.app
"dist/RWTH VPN.app/Contents/MacOS/RWTHVPN" --selftest
./scripts/test-bundled.sh                   # checks the vendored client
./build.sh --dmg                            # also produce a DMG
```

`--selftest` is the main safety net. It runs without credentials or root and
covers TOTP vectors, Base32/`otpauth` parsing, Keychain round-trip, helper
payload integrity, the UI layout, the full connect state machine against a fake
gateway, prompt variants, failure paths and credential redaction.

## Debug flags

| Flag / env | Purpose |
|---|---|
| `--selftest` | run the test suite |
| `--debug-connect` | drive the real state machine; credentials from `RWTHVPN_USER`, `RWTHVPN_PASS`, `RWTHVPN_TOTP`, `RWTHVPN_GROUP` |
| `RWTHVPN_DEBUG_COMMAND="/path/to/client"` | replace the privileged helper with any executable (used by tests) |
| `--render-preview <dir>` | render UI screenshots without screen-recording permission |
| `--render-icon <file>` | render the 1024 px app icon |

Never point `--debug-connect` at a real account in CI or in a committed script.

## Layout

```
Sources/App.swift          entry point and CLI modes
Sources/AppDelegate.swift  window, menu bar status item, menus, About
Sources/VPNModel.swift     session state machine, prompt handling, Keychain use
Sources/Views.swift        SwiftUI window and settings sheet
Sources/Helper.swift       privileged helper install/update, payload, login item
Sources/TOTP.swift         RFC 6238 TOTP, Base32, otpauth parsing
Sources/Keychain.swift     Keychain storage (disabled in tests)
Sources/AppInfo.swift      versions, links, disclaimer
Sources/SelfTest.swift     --selftest
Resources/rwth-vpn-helper.sh   root helper ({{HELPER_VERSION}} substituted at build)
Resources/helper-version.txt   helper/payload contract version
scripts/bundle-openconnect.py  vendors openconnect + dylibs + CA bundle
```

## Ground rules

- **No credentials in issues, PRs or logs.** The app must never print the
  password or the token code; `--selftest` asserts this.
- Keep the helper minimal. It must never accept a binary path or extra
  openconnect flags — that would be a local root escalation.
- The app must work with **no Homebrew installed**. Anything executed at
  runtime comes from the app bundle and is installed root-owned.
- Bump `Resources/helper-version.txt` when the helper CLI or the payload
  changes; the app then offers "Update helper" automatically.
- Prefer plain SwiftUI/AppKit and Foundation; new dependencies need a very good
  reason.
- English only. Match the existing tone (short, factual, no marketing).

## Pull requests

- One topic per PR, with a short description of the user-visible change.
- Run `./build.sh` and `--selftest` before pushing; CI runs the same.
- Update `CHANGELOG.md` for user-visible changes.
- For UI changes, include before/after screenshots (`--render-preview`).

## Commit messages

Imperative mood, one line summary, body for the "why". Example:

```
Stop backgrounding openconnect in the helper

bash redirects a background job's stdin to /dev/null, so openconnect hit EOF
at the password prompt and the login never completed.
```

## Releasing

See [docs/RELEASING.md](docs/RELEASING.md).
