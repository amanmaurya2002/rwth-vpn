# The RWTH VPN handshake, as observed

The RWTH gateway is a Cisco ASA/FTD speaking the AnyConnect SSL-VPN protocol.
This is what the app (via openconnect) actually does. It is documented here so
nobody has to reverse-engineer it again.

## Endpoint

- Host: `vpn.rwth-aachen.de:443`
- Certificate: `C=DE, O=RWTH Aachen University, CN=vpn.rwth-aachen.de`, issued by
  GEANT TLS RSA 1 (publicly trusted)
- `GET /` redirects to `/+CSCOE+/logon.html` and sets `webvpn` cookies, the
  classic AnyConnect portal.

## 1. Group discovery

POST the following XML to `/`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<config-auth client="vpn" type="init" aggregate-auth-version="2">
  <version who="vpn">4.10.07061</version>
  <device-id>mac-intel</device-id>
  <group-select>0</group-select>
  <group-access>https://vpn.rwth-aachen.de</group-access>
</config-auth>
```

The response contains the tunnel groups and a classic login form:

```xml
<opaque is-for="sg">
  <tunnel-group>TunnelGroup_RWTH_Full</tunnel-group>
  <group-alias>RWTH-VPN (Full Tunnel)</group-alias>
</opaque>
<auth id="main">
  <form>
    <input type="text" name="username" label="Username:"></input>
    <input type="password" name="password" label="Password:"></input>
    <select name="group_list" label="GROUP:">
      <option selected="true">RWTH-VPN (Full Tunnel)</option>
      <option>RWTH-VPN (Split Tunnel)</option>
    </select>
  </form>
</auth>
```

`ping` works but new TCP connections can time out for a few minutes after
several failed logins — the ASA rate-limits/blocks the client IP. Do not retry
a wrong password in a loop.

## 2. Password

openconnect sends the form with the chosen `authgroup`, `username` and
`password`. It prints the label of each field it needs, so the app sees:

```
Password:
```

(Over a pipe, no newline after the colon.)

## 3. Token

After a correct password the gateway asks for the one-time password. The label
on this gateway is **`Response:`** (some ASAs use `Answer:`); the form may also
carry a German/English message:

```
Einmal-Passwort eingeben.
Token im IdM Selfservice registrieren.

Enter One-Time-Password.
Set up tokens in IdM Selfservice.
Response:
```

The token is a standard RFC 6238 TOTP, 6 digits, 30 s, SHA-1 — the same code the
RWTH token app shows. The app answers the prompt with the code on stdin.

## 4. Tunnel

On success openconnect reports:

```
Got CONNECT response: HTTP/1.1 200 OK
CSTP connected. DPD 30, Keepalive 20
Established DTLS connection (using GnuTLS). Ciphersuite (DTLS1.2)-(ECDHE-RSA)-(AES-256-GCM).
Configured as 172.21.0.163 + 2a00:8a60:c010:1::1:16da/64, with SSL connected and DTLS connected
Session authentication will expire at Thu, 05 Nov 2026 09:50:39 CET
```

`Configured as` is the line the app uses to switch to "connected"; openconnect
9.21 no longer prints the older `Connected as …`.

The IPv4 address comes from `134.61.96.0/22`-ish ranges depending on the pool;
the IPv6 address is from `2a00:8a60:c010:1::/64`.

## 5. What the helper passes to openconnect

```bash
openconnect \
  --protocol=anyconnect \
  --script=/usr/local/libexec/rwth-vpn/vpnc-script \
  --no-system-trust \
  --cafile=/usr/local/libexec/rwth-vpn/cert.pem \
  --user=<ab123456> \
  --authgroup='RWTH-VPN (Split Tunnel)' \
  vpn.rwth-aachen.de
```

`--script` and `--cafile` are required because the bundled Homebrew build has
`/opt/homebrew/...` paths compiled in, and those do not exist on a Mac without
Homebrew. `--no-system-trust` makes verification deterministic: only the
bundled CA store is used.

## Reproducing the group list

```bash
curl -sS https://vpn.rwth-aachen.de/ \
  -H 'Content-Type: application/xml' \
  --data-binary @- <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<config-auth client="vpn" type="init" aggregate-auth-version="2">
  <version who="vpn">4.10.07061</version>
  <device-id>mac-intel</device-id>
  <group-select>0</group-select>
  <group-access>https://vpn.rwth-aachen.de</group-access>
</config-auth>
XML
```

This only lists the groups; it does not authenticate.
