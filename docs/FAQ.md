# FAQ

**Is this the official RWTH VPN client?**
No. It is an unofficial student project. The IT Center supports Cisco Secure
Client only.

**Why is it Apple Silicon only?**
The maintainers build and test on Apple Silicon; x86_64 is out of scope for v1.
Intel Macs should use Cisco Secure Client.

**Why does it need an admin password?**
Creating a VPN tunnel requires root on macOS. Instead of running the whole app
as root, a small helper plus a bundled openconnect client is installed once,
root-owned, and allow-listed in `/etc/sudoers.d`. After that, connecting is
one click.

**Where are my credentials stored?**
In your login Keychain (`dev.local.rwth-vpn`). They are only sent to
`vpn.rwth-aachen.de`. See [PRIVACY.md](../PRIVACY.md).

**Can I skip storing the TOTP secret?**
No. The current CLI connection flow generates the code from the saved secret,
so configure the TOTP secret before connecting.

**Does it work with an institute VPN?**
Not tested. Institute VPNs may use SAML/SSO or host checks that this client
does not implement.

**I get "Login failed" repeatedly.**
Check that you used the VPN password from IdM SelfService, not your SSO
password. If it keeps failing, wait a few minutes: the gateway may temporarily
block your IP after several failed attempts.

**Full tunnel or split tunnel?**
Split (default) routes only RWTH addresses; use it for CampusOffice, the
library, SSH to institute machines, etc. Full routes everything through RWTH,
including your general browsing.

**How do I stop a connection?**
Run `rwth-vpn disconnect`.

**How do I uninstall completely?**
Run `rwth-vpn uninstall` to remove the CLI and helper while keeping credentials.
Use `rwth-vpn uninstall --purge` to remove the saved credentials too.

**How do I update?**
Run `rwth-vpn update`. It verifies the release checksum before replacing the
installed CLI.
