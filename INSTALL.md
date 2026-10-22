# Install RWTH VPN

The app is distributed as a DMG on the
[Releases page](../../releases/latest). It is **not notarized**, because
notarization requires a paid Apple Developer account and this project is a
student project. macOS therefore blocks the first launch until you explicitly
allow it. That is expected, not a sign of a broken download.

You need an **Apple Silicon** Mac with **macOS 14 or newer**.

## 1. Download and copy the app

1. Download `RWTH VPN-<version>.dmg` from Releases.
2. Double-click the DMG.
3. Drag **RWTH VPN** to the **Applications** folder next to it.
4. Eject the DMG.

## 2. Allow the app to run (one time)

### macOS 15 and newer

Control-clicking no longer bypasses Gatekeeper — Apple removed that in macOS 15.
Use System Settings:

1. Open **RWTH VPN** from Applications. You will see *"Apple could not verify
   RWTH VPN is free of malware"* (or *"…is damaged"* if the download was
   incomplete). Click **Done** / **Cancel**.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the **Security** section. You will see a message about RWTH VPN
   being blocked, with an **Open Anyway** button.
4. Click **Open Anyway**, authenticate with Touch ID or your password.
5. Confirm with **Open Anyway** in the second dialog.

The app now starts. You only do this once.

### macOS 14

Control-click the app in Finder and choose **Open**, then **Open** again in the
dialog. If that is not offered, use the macOS 15 steps above.

### Terminal alternative

```bash
xattr -dr com.apple.quarantine "/Applications/RWTH VPN.app"
open "/Applications/RWTH VPN.app"
```

Only do this for a DMG you downloaded from this repository's Releases page.

> Screenshots to add: `docs/images/gatekeeper-dialog.png`,
> `docs/images/gatekeeper-open-anyway.png`.

## 3. Set up the VPN account and token

If you have not used the RWTH VPN before:

1. Open [IdM SelfService](https://idm.rwth-aachen.de/selfservice/Accounts?2).
2. Activate the **VPN** account and set the **VPN password**. This is *not*
   your SSO password.
3. Register a token (authenticator app / TOTP) for the VPN. RWTH documents this
   in the [MFA guide](https://help.itc.rwth-aachen.de/en/service/vbf6fx0gom76/article/34c748946f63455090ede2dd5a7a49e5/).

The token secret is the Base32 string behind the QR code, or the full
`otpauth://totp/...?secret=...` link. Pasting either into the app enables
automatic codes. If you cannot get the secret, leave the field empty and type
the 6-digit code before each connection.

## 4. First launch

1. Open **RWTH VPN**. The main window appears.
2. Open **Settings** (gear icon, or ⌘,).
3. Fill in:
   - **Username** — `ab123456`
   - **VPN password** — from IdM SelfService
   - **Token secret** — optional, see above
4. Click **Install…** next to "Helper needs setup". macOS asks for an
   administrator password — this installs:
   - `/usr/local/libexec/rwth-vpn-helper` (the small privileged helper)
   - `/usr/local/libexec/rwth-vpn/` (openconnect, its libraries, CA bundle)
   - `/etc/sudoers.d/rwth-vpn-helper` (one NOPASSWD rule for that helper)
5. Click **Connect**.

The first connection may ask for Keychain access — choose **Always Allow** so
the app can reuse the saved password.

## 5. Verify

- The shield in the menu bar turns green.
- The status card shows the tunnel address and the session expiry.
- `curl https://www.rwth-aachen.de` works, and in split mode your local
  network still works.

## Uninstall

Settings → **Remove** removes the helper, payload and sudoers rule. Then quit
the app and delete it from Applications. See the README for removing Keychain
items and preferences.
