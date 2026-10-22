# RWTH VPN — native macOS app

A lightweight native SwiftUI app (Apple Silicon, ~700 KB, no Electron) for the
RWTH Aachen VPN. It drives `openconnect` (the open-source Cisco
AnyConnect/SSL-VPN client) and gives you one-click connect/disconnect,
split/full tunnel, automatic TOTP codes and Keychain-stored credentials.

Closing the window keeps the app in the Dock; a menu bar shield appears only
while a tunnel is up or being established.

Unofficial. Not affiliated with RWTH Aachen University or the IT Center.

## Requirements

- macOS 14 or newer (built and tested on macOS 27, Apple Silicon)
- `openconnect` from Homebrew:

  ```bash
  brew install openconnect
  ```

- The Xcode command line tools (`swiftc`, `codesign`) to build.

## Build and install

```bash
cd rwth-vpn-menubar
./build.sh
cp -R "dist/RWTH VPN.app" /Applications/
open "/Applications/RWTH VPN.app"
```

Build artifacts are ad-hoc signed, which is fine for a local build.

## One-time setup

1. Open **RWTH VPN** → gear (or ⌘,) → **Settings**.
2. Enter your **username** (`ab123456`) and your **VPN password** (the one from
   [IdM SelfService](https://idm.rwth-aachen.de/selfservice/Accounts?2), not your
   SSO password).
3. Optionally paste your **token secret** to get codes generated automatically.
   Either the Base32 secret or the full `otpauth://` enrolment link works. If
   you skip this, you type the 6-digit code into the panel before each connect.
4. Press **Install…** next to "Helper not installed" and confirm the admin
   prompt once. This writes a small root-owned helper plus a `sudoers.d` rule so
   connecting later needs no password prompt.

After that: **Connect** (⌘↩). The menu bar shield turns green when the tunnel is
up, and the app can connect automatically when it opens.

## How it works

- The app runs `/usr/local/libexec/rwth-vpn-helper` through `sudo -n`. That
  helper is root-owned, mode 0755, and accepts only
  `connect <split|full> <ab123456>` or `stop`. It never takes extra
  `openconnect` options, so it cannot be used to run arbitrary commands as root.
  It records its pid and `exec`s openconnect, so the caller's stdin (password,
  then token code) is passed through untouched.
- Credentials travel over stdin (never argv/environment); `openconnect` prompts
  for the password and then for the token code, and the app answers each prompt
  as it appears.
- The VPN password and token secret live in your login Keychain.
- `/etc/sudoers.d/rwth-vpn-helper` contains exactly one NOPASSWD rule for that
  one helper path.
- A session started outside the app (for example before a relaunch) is detected
  through `/var/run/rwth-vpn-helper.pid` and can be disconnected normally.

## Uninstall

1. Settings → **Remove** (removes the helper and the sudoers rule).
2. Quit the app and delete `/Applications/RWTH VPN.app`.

Or manually:

```bash
sudo rm -f /etc/sudoers.d/rwth-vpn-helper /usr/local/libexec/rwth-vpn-helper
```

## Troubleshooting

- **"a password is required"** or **"Update the helper"** — the sudoers rule or
  helper binary is stale. Settings → **Reinstall…**
- **Menu bar icon missing** — it only appears while connecting/connected; the
  Dock icon is always there.
- **"The server rejected the password"** — the password field holds your SSO
  password instead of the VPN password.
- **"Login failed — wrong code or password"** — the code expired (they rotate
  every 30 s) or the password is wrong.
- **"Timed out while connecting"** — network/firewall; check the Log section
  (toggle "Log", then "Copy") for the `openconnect` output.
- **Full tunnel** routes everything through RWTH; **Split** only routes RWTH
  addresses, so local devices stay reachable.
- Quitting the app does not tear the tunnel down; disconnect first if you want
  it closed.

## Development

```bash
./build.sh
"dist/RWTH VPN.app/Contents/MacOS/RWTHVPN" --selftest        # TOTP, Keychain, UI, connect state machine
"dist/RWTH VPN.app/Contents/MacOS/RWTHVPN" --render-preview /tmp   # writes preview PNGs
```

`--selftest` drives the real connect state machine against a fake `openconnect`
(no credentials, no root). `RWTHVPN_DEBUG_COMMAND="path args"` swaps the
privileged helper for an arbitrary command and is only used by that test.

Layout:

```
Sources/App.swift          entry point
Sources/AppDelegate.swift  window, menu bar status item, menus
Sources/VPNModel.swift     session state machine + prompt handling
Sources/Views.swift        SwiftUI panel and settings
Sources/Helper.swift       privileged helper install/uninstall, login item
Sources/TOTP.swift         RFC 6238 TOTP + Base32 + otpauth parsing
Sources/Keychain.swift     Keychain storage
Sources/Preview.swift      dev-only rendering helper
Sources/SelfTest.swift     --selftest
Resources/rwth-vpn-helper.sh
```
