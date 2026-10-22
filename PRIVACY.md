# Privacy

RWTH VPN is a local client. It has no accounts, no telemetry, no analytics and
no update beacon.

## What is stored, and where

| Data | Where | Why |
|---|---|---|
| VPN username | `~/Library/Preferences/dev.local.rwth-vpn.plist` | prefill the form |
| VPN password | login Keychain (`dev.local.rwth-vpn` / `password`) | avoid retyping; sent only to `vpn.rwth-aachen.de` |
| TOTP secret (optional) | login Keychain (`dev.local.rwth-vpn` / `totp`) | generate 6-digit codes locally |
| Tunnel group, preferences | same plist | remember split/full and autostart |
| Diagnostics log | memory only | shown in the Log panel; nothing is uploaded |

Deleting the app does not delete these. Use **Settings → Forget password** and
remove the preferences plist to erase them.

## Network traffic

The only endpoints contacted are `vpn.rwth-aachen.de` (the VPN gateway) and,
when you click it, the GitHub releases/issues page. No third-party servers, no
DNS prefetching, no crash reporting.

## Keychain access

macOS ties Keychain items to the app's code signature. Ad-hoc signed builds
change signature on every rebuild, so macOS may ask once per build whether the
app may read its own saved password. Release builds signed with a stable
self-signed identity do not have this problem.

## Accountability

This is an unofficial student project, not an RWTH service. The IT Center's
[privacy notice](https://www.itc.rwth-aachen.de/cms/it-center/Footer/Service/~myfc/Datenschutzerklaerung/?lidx=1)
covers the VPN service itself; this document covers the client.
