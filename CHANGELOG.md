# Changelog

## 1.2.1

- Fixed the standalone installer status message on POSIX shells.

## 1.2.0

- Added a Homebrew-free one-line CLI installer.
- Added `rwth-vpn uninstall` with optional `--purge` credential removal.

## 1.1.0

- Added a lightweight `rwth-vpn` CLI with shared Keychain credentials and
  helper management.
- Added a Homebrew formula and CLI release archive.

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-22

First release.

### Added
- Native SwiftUI app window with Dock icon; the menu bar shield appears only
  while a tunnel is connecting, connected or disconnecting.
- Split and full tunnel profiles (`RWTH-VPN (Split Tunnel)` /
  `RWTH-VPN (Full Tunnel)`).
- Automatic TOTP codes from a Base32 secret or `otpauth://` link, with a live
  countdown; manual code entry when no secret is stored.
- Credentials and the TOTP secret stored in the login Keychain; optional
  connect-on-launch and launch-at-login.
- Bundled, relocatable openconnect client with its own CA bundle, so no
  Homebrew installation is required.
- Privileged helper with a root-owned payload under
  `/usr/local/libexec/rwth-vpn/` and a single sudoers rule.
- Helper version/manifest drift detection and one-click update.
- Session details (tunnel address, session expiry) and a copyable log.

### Fixed
- Login prompt handling: RWTH answers with `Response:`, other gateways use
  `Answer:`/`Challenge:`; all are supported now.
- The helper no longer backgrounds openconnect, which redirected its stdin to
  `/dev/null` and broke the password prompt.
- Tunnel state is detected from `Configured as …` (openconnect 9.x) as well as
  the older `Connected as …`.
- Race where the first password prompt could arrive before the stdin pipe was
  registered.

### Security
- Credentials are only ever written to the helper's stdin.
- The app bundle is signature-verified before the root-owned payload is
  installed.
