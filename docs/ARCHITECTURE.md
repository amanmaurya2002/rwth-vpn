# Architecture

## Process model

```
┌─────────────────┐   sudo -n    ┌──────────────────────┐   exec   ┌─────────────┐
│ RWTH VPN.app    │ ───────────▶ │ rwth-vpn-helper      │ ───────▶ │ openconnect │
│ (user, no root) │   stdin:     │ (root, 0755, fixed   │          │ (root)      │
│                 │   password,  │  command set only)   │          │             │
│                 │   token      │                      │          │ vpnc-script │
└─────────────────┘              └──────────────────────┘          └─────────────┘
        │                                   │
        │ Keychain                          │ root-owned payload
        │ (password, TOTP)                  │ /usr/local/libexec/rwth-vpn/
        ▼                                   ▼
   login keychain                     openconnect + dylibs + cert.pem + vpnc-script
```

The app is a normal user process. It never runs privileged code; the only root
surface is the helper, which exposes three fixed commands and no free-form
arguments.

## Install layout

| Path | Owner | Purpose |
|---|---|---|
| `/usr/local/libexec/rwth-vpn-helper` | root:wheel 0755 | helper script |
| `/usr/local/libexec/rwth-vpn/` | root:wheel, `go-w` | openconnect, dylibs, `cert.pem`, `vpnc-script`, `MANIFEST.sha256`, `VERSIONS.txt` |
| `/etc/sudoers.d/rwth-vpn-helper` | root:wheel 0440 | one NOPASSWD rule for the helper |
| `~/Library/LaunchAgents/dev.local.rwth-vpn.loginitem.plist` | user | optional launch at login |
| login Keychain, service `dev.local.rwth-vpn` | user | password + TOTP secret |

The payload is copied from the app bundle as root. Root ownership means a
replaced or moved `.app` cannot change what runs as root. Before copying, the
installer runs `codesign --verify --strict` on the bundle.

## Version contract

`Resources/helper-version.txt` is the contract version. It is substituted into
the helper at build time and read back through `helper version`, which prints:

```
helper=1.0.0
manifest=<sha256 of /usr/local/libexec/rwth-vpn/MANIFEST.sha256>
```

The app compares both values with its own bundle. Mismatch → "Update helper",
and `connect()` refuses to start instead of failing halfway through the login.
The manifest covers every payload file, so a changed openconnect build also
triggers an update.

## Connect state machine

`VPNModel` spawns `sudo -n <helper> connect <split|full> <user>` and reads the
merged stdout/stderr. It reacts to prompts rather than sleeping:

1. `Password:` → write the stored password to stdin (once; a second prompt
   means the password was rejected, so it fails fast instead of retrying).
2. `Response:` / `Answer:` / `Challenge:` / any other prompt after the password
   → write the TOTP code.
3. `Configured as <ip>` (openconnect 9.x) or `Connected as <ip>` (older) →
   status `connected`.
4. `Session authentication will expire at …` → shown in the header.
5. Process exit → `disconnected`, or `failed` with the last meaningful line.

A 90 s watchdog aborts a stuck connection by closing stdin, which makes
openconnect unwind. The app cannot signal a root process directly, so
`disconnect` asks the helper to `stop` (SIGINT, then SIGTERM).

## Why not NetworkExtension?

A true system VPN extension would need Apple's Network Extension entitlement,
a paid developer account and a reimplementation of the AnyConnect protocol
inside the extension. That is out of scope for a student project. The subprocess
approach keeps the app small and auditable.

## Why not SMAppService?

`SMAppService.daemon` requires a properly signed and notarized helper with a
team identifier. Without the Apple Developer Program, the sudoers-based helper
is the practical option, and its contract is small enough to audit. The
trade-off is one admin prompt when the helper or payload changes.

## Keychain

The password and TOTP secret are generic-password items in the login keychain.
Reads happen lazily after the window appears, never during `--selftest` or
preview rendering (`Keychain.isEnabled = false`). Ad-hoc signed builds change
their code signature on every rebuild, so macOS may ask once per build; release
builds signed with a stable self-signed identity avoid that.
