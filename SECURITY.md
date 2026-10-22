# Security

## Reporting a vulnerability

Please do not open a public issue for security problems. Use GitHub's
**Security → Report a vulnerability** (private advisory) on this repository, or
contact a maintainer directly. We aim to acknowledge within 72 hours.

## Threat model

The app needs root to create the `utun` interface. That is the only privileged
operation, and it is isolated behind a small helper:

- `/usr/local/libexec/rwth-vpn-helper` — root:wheel 0755, allow-listed by a
  single NOPASSWD rule in `/etc/sudoers.d/rwth-vpn-helper`.
- The helper accepts only `connect <split|full> <ab123456>`, `stop` and
  `version`. It takes no paths and no extra openconnect options, so it cannot
  be used to execute arbitrary commands as root.
- The openconnect binary, its libraries, the CA bundle and `vpnc-script` live
  in a root-owned directory `/usr/local/libexec/rwth-vpn/`. The app cannot
  modify them after installation, and moving or replacing the `.app` has no
  effect on what runs as root.
- Installation runs as root only after `codesign --verify --strict` on the app
  bundle. A tampered bundle is refused before anything is copied.

Credentials never appear in process arguments or environment variables. They
are written to the helper's stdin and answered to openconnect's prompts.

## Known trade-offs

- The sudoers rule grants the local user passwordless execution of the helper.
  That is intentional (one-click connect) and limited to the three commands
  above.
- The TOTP secret is stored in the login Keychain when the user opts in. That
  trades a second factor stored on the same device for convenience; the app
  works without it (manual code entry).
- Builds are not notarized (no Apple Developer Program). macOS will warn on
  first launch; the README explains the "Open Anyway" flow. Notarization adds
  malware scanning, not a security boundary.
- Ad-hoc signed builds get a new code signature on every rebuild, so Keychain
  ACL prompts reappear. Release builds can be signed with a stable self-signed
  identity (`scripts/make-signing-cert.sh`).

## Out of scope

- Compromised RWTH credentials or a compromised Mac.
- Malicious gateways: the app trusts the server certificate chain in the
  bundled CA store.
