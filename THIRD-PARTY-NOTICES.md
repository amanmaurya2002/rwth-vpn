# Third-party notices

The app itself is MIT licensed (see `LICENSE`). Release builds bundle an
unmodified openconnect client and its dependencies so that users do not need
Homebrew. Those components keep their own licences.

| Component | Licence | Source |
|---|---|---|
| [openconnect](https://www.infradead.org/openconnect/) 9.x | LGPL-2.1-or-later | https://gitlab.com/openconnect/openconnect |
| [GnuTLS](https://www.gnutls.org/) 3.8.x | LGPL-2.1-or-later | https://gitlab.com/gnutls/gnutls |
| [nettle](https://www.lysator.liu.se/~nisse/nettle/) | LGPL-3.0-or-later / GPL-2.0-or-later | https://git.lysator.liu.se/nettle/nettle |
| [GMP](https://gmplib.org/) | LGPL-3.0-or-later / GPL-2.0-or-later | https://gmplib.org/ |
| [p11-kit](https://p11-glue.github.io/p11-glue/p11-kit.html) | BSD-3-Clause | https://github.com/p11-glue/p11-kit |
| [stoken](https://github.com/cernekee/stoken) | LGPL-2.1-or-later | https://github.com/cernekee/stoken |
| [LibTomCrypt](https://www.libtom.net/LibTomCrypt/) | Public domain (WTFPL) | https://github.com/libtom/libtomcrypt |
| [LibTomMath](https://www.libtom.net/LibTomMath/) | Public domain (WTFPL) | https://github.com/libtom/libtommath |
| [gettext](https://www.gnu.org/software/gettext/) (libintl) | LGPL-2.1-or-later | https://www.gnu.org/software/gettext/ |
| [libidn2](https://www.gnu.org/software/libidn/#libidn2) | LGPL-3.0-or-later | https://gitlab.com/libidn/libidn2 |
| [libunistring](https://www.gnu.org/software/libunistring/) | LGPL-3.0-or-later | https://git.savannah.gnu.org/git/libunistring.git |
| [libtasn1](https://www.gnu.org/software/libtasn1/) | LGPL-2.1-or-later | https://gitlab.com/gnutls/libtasn1 |
| [vpnc-script](https://gitlab.com/openconnect/vpnc-scripts) | GPL-2.0-or-later | https://gitlab.com/openconnect/vpnc-scripts |
| CA bundle (Mozilla CA list) | MPL-2.0 | https://curl.se/ca/cacert.pem |

Full licence texts are in `licenses/` and are copied into the app bundle
(`Contents/Resources/licenses`).

## LGPL compliance

openconnect, GnuTLS and the other LGPL libraries are bundled unmodified as
separate executables and dynamic libraries. They are invoked as a subprocess
and are not linked into the app binary. Every release records the exact
versions and SHA-256 of the bundled files in `VERSIONS.txt` inside the app
bundle, and the build can be reproduced with `scripts/bundle-openconnect.py`
against the same Homebrew versions. You may replace the bundled binaries with
your own builds; the root-owned copy at `/usr/local/libexec/rwth-vpn/` is
installed from the app bundle, and `scripts/bundle-openconnect.py` documents
the exact load-path rewriting.

## GPL compliance (vpnc-script)

`vpnc-script` is a shell script, so the file itself is its source. It is
invoked by openconnect as a separate process; it is not linked into the app.
The GPL-2.0 text is included in `licenses/GPL-2.0.txt`.
