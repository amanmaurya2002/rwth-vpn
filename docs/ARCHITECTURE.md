# Architecture

## Process model

```text
rwth-vpn ── sudo -n ──▶ rwth-vpn-helper ── exec ──▶ openconnect
    │                         │
    └─ login Keychain          └─ root-owned payload
```

The CLI runs as the user. The helper is the only root process and exposes
fixed commands for setup, connection, status, and removal.

## Install layout

| Path | Owner | Purpose |
|---|---|---|
| `/usr/local/libexec/rwth-vpn-helper` | root:wheel 0755 | helper script |
| `/usr/local/libexec/rwth-vpn/` | root:wheel, `go-w` | OpenConnect payload |
| `/etc/sudoers.d/rwth-vpn-helper` | root:wheel 0440 | one NOPASSWD rule |
| login Keychain, service `dev.local.rwth-vpn` | user | username, password, TOTP |

The payload is copied from the verified local installer resources as root.

## Version contract

`Resources/helper-version.txt` is substituted into the helper at build time.
The CLI compares it with `helper version`, together with the payload manifest,
before allowing a connection.

## Connection

`rwth-vpn connect` invokes:

```text
sudo -n /usr/local/libexec/rwth-vpn-helper connect <split|full> <username>
```

The helper runs OpenConnect and receives the password and TOTP response through
stdin. Passwords and token codes are never logged.
