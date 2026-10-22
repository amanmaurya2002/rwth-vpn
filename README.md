# rwth-vpn

A small, unofficial command-line VPN client for RWTH Aachen. It stores
credentials in the macOS Keychain, generates TOTP codes locally, and uses a
small privileged helper to run the bundled OpenConnect client.

The CLI is the only supported product. There is no desktop app or Homebrew
runtime dependency.

> This is a student project and is not affiliated with RWTH Aachen University
> or its IT Center. The officially supported client is
> [Cisco Secure Client](https://help.itc.rwth-aachen.de/en/service/vbf6fx0gom76/article/35d4a399d2984c1f8d3e364e87c366dd/).

## Requirements

- Apple Silicon Mac (M1 or newer)
- macOS 26 or newer
- RWTH VPN account and token from
  [IdM SelfService](https://idm.rwth-aachen.de/selfservice/Accounts?2)

## Install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/amanmaurya2002/rwth-vpn/main/install.sh | bash
```

The installer verifies the release checksum and installs the CLI and its
bundled resources to `~/.local`. If the installer asks you to update `PATH`,
run the printed command and open a new terminal if needed.

## Configure and connect

Configure your RWTH username, VPN password, and TOTP secret interactively:

```bash
rwth-vpn configure
rwth-vpn setup
rwth-vpn connect
```

`setup` asks for administrator authorization once to install or update the VPN
helper. The default tunnel is split tunnel. Use `rwth-vpn connect full` for a
full tunnel.

Useful commands:

```text
rwth-vpn status
rwth-vpn disconnect
rwth-vpn remove
rwth-vpn update
rwth-vpn update --check
rwth-vpn uninstall
rwth-vpn uninstall --purge
```

`remove` removes only the helper and keeps the CLI. `uninstall` removes the
CLI and helper after confirmation but keeps credentials by default.
Add `--purge` to `uninstall` if you also want to delete the saved Keychain
credentials.

## How it works

```text
rwth-vpn ──(sudo -n)──▶ rwth-vpn-helper ──exec──▶ openconnect
    │                         │
    └─ login Keychain          └─ root-owned payload in /usr/local/libexec/rwth-vpn
```

The helper accepts only fixed commands, and the bundled client is relocatable,
so users do not need Homebrew at runtime.

## Build from source

Build the CLI and its bundled resources:

```bash
brew install openconnect          # build-time only
./build.sh
./dist/rwth-vpn help
./dist/rwth-vpn status
./scripts/test-bundled.sh
```

The build outputs `dist/rwth-vpn` and `dist/resources/`. See
[CONTRIBUTING.md](CONTRIBUTING.md) and [docs/RELEASING.md](docs/RELEASING.md).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `command not found: rwth-vpn` | Run `export PATH="$HOME/.local/bin:$PATH"` or open a new Terminal window. |
| `bundle format unrecognized` from `/opt/homebrew/Cellar/rwth-vpn/...` | Remove the obsolete Homebrew package with `brew uninstall rwth-vpn`, then ensure `~/.local/bin` comes first in `PATH`. |
| `Helper is not ready` | Run `rwth-vpn setup`, then `rwth-vpn status`. |
| Login failed | Use the VPN password from IdM SelfService, not your normal SSO password. |

## Privacy and security

No telemetry. Credentials and the token secret live in your login Keychain and
are sent only to `vpn.rwth-aachen.de`. See [PRIVACY.md](PRIVACY.md) and
[SECURITY.md](SECURITY.md).

## Licence

MIT for this project. Bundled OpenConnect dependencies retain their own
licences; see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
