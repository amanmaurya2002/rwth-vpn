# FAQ

**Is this the official RWTH VPN client?**
No. It is an unofficial student project. The IT Center supports Cisco Secure
Client only. This app exists because that client is heavy and re-prompts for
credentials and codes.

**Why is it Apple Silicon only?**
The maintainers build and test on Apple Silicon; x86_64 is out of scope for v1.
Intel Macs should use Cisco Secure Client.

**Why does macOS say the app is damaged / cannot be verified?**
The app is not notarized (no Apple Developer Program). Follow
[INSTALL.md](../INSTALL.md): System Settings → Privacy & Security → Open Anyway.
If the DMG was truncated, the message can also mean a broken download — compare
the SHA-256 with `SHA256SUMS.txt`.

**Why does it need an admin password?**
Creating a VPN tunnel requires root on macOS. Instead of running the whole app
as root, a small helper plus a bundled openconnect client is installed once,
root-owned, and allow-listed in `/etc/sudoers.d`. After that, connecting is
one click.

**Where are my credentials stored?**
In your login Keychain (`dev.local.rwth-vpn`). They are only sent to
`vpn.rwth-aachen.de`. See [PRIVACY.md](../PRIVACY.md).

**Can I skip storing the TOTP secret?**
Yes. Leave the token field empty and type the 6-digit code before connecting.
Storing the secret is opt-in convenience.

**Does it work with an institute VPN?**
Not tested. Institute VPNs may use SAML/SSO or host checks that this client
does not implement.

**I get "Login failed" repeatedly.**
Check that you used the VPN password from IdM SelfService, not your SSO
password. If it keeps failing, wait a few minutes: the gateway may temporarily
block your IP after several failed attempts.

**The keychain prompt appears after every update.**
Ad-hoc signed builds change identity. Releases signed with the project's
self-signed certificate keep Keychain access; otherwise click "Always Allow"
once per version. See [docs/ARCHITECTURE.md](ARCHITECTURE.md).

**Full tunnel or split tunnel?**
Split (default) routes only RWTH addresses; use it for CampusOffice, the
library, SSH to institute machines, etc. Full routes everything through RWTH,
including your general browsing.

**Does the app keep running when I close the window?**
Yes, it stays in the Dock. The menu bar shield only appears while a session is
connecting/connected. Quitting does not tear the tunnel down; reopen and
disconnect, or run `sudo /usr/local/libexec/rwth-vpn-helper stop`.

**How do I uninstall completely?**
Settings → Remove, then delete the app. Remove preferences with
`defaults delete dev.local.rwth-vpn` and use **Forget password** for the
Keychain items.

**Why is there no auto-update?**
Silently replacing an unsigned app is a security trade-off this project is not
ready to make. Settings → **Check for updates** opens the Releases page.
