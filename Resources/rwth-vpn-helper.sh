#!/bin/bash
# rwth-vpn-helper -- privileged helper for the RWTH VPN app.
#
# Installed as root:wheel 0755 at /usr/local/libexec/rwth-vpn-helper and
# allow-listed in /etc/sudoers.d/rwth-vpn-helper (NOPASSWD) for the local user.
#
# It deliberately exposes only two fixed operations and never accepts extra
# openconnect options, so it cannot be used to run arbitrary commands as root.
#
#   connect <split|full> <ab123456>   connects (credentials read from stdin)
#   stop                              disconnects the active session
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
OC=/opt/homebrew/bin/openconnect
PIDFILE=/var/run/rwth-vpn-helper.pid
SERVER=vpn.rwth-aachen.de

die() { echo "$*" >&2; exit 64; }
usage() { die "usage: $0 connect <split|full> <ab123456> | stop"; }

[ "$(id -u)" -eq 0 ] || die "rwth-vpn-helper must run as root"

case "${1:-}" in
connect)
    group=${2:-}
    user=${3:-}
    case "$group" in
        split) authgroup='RWTH-VPN (Split Tunnel)' ;;
        full)  authgroup='RWTH-VPN (Full Tunnel)' ;;
        *) usage ;;
    esac
    case "$user" in
        [a-z][a-z][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
        *) die "invalid username (expected ab123456)" ;;
    esac
    [ -x "$OC" ] || die "openconnect is not installed at $OC (run: brew install openconnect)"

    # Record our own pid, then become openconnect: same pid, no fork, so the
    # caller's stdin (password, then token code) is passed through untouched.
    # Backgrounding here would redirect stdin to /dev/null and break the login.
    echo "$$" >"$PIDFILE"
    exec "$OC" --protocol=anyconnect \
          --user="$user" \
          --authgroup="$authgroup" \
          "$SERVER"
    ;;
stop)
    [ -f "$PIDFILE" ] || exit 0
    pid=$(cat "$PIDFILE" 2>/dev/null || true)
    case "$pid" in
        '' | *[!0-9]*)
            rm -f "$PIDFILE"
            exit 0
            ;;
    esac
    if ps -p "$pid" -o command= 2>/dev/null | grep -q openconnect; then
        kill -INT "$pid" 2>/dev/null || true
        # Give openconnect a moment to restore routes and DNS.
        n=0
        while [ "$n" -lt 20 ] && kill -0 "$pid" 2>/dev/null; do
            sleep 0.2
            n=$((n + 1))
        done
        kill -TERM "$pid" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
    exit 0
    ;;
*)
    usage
    ;;
esac
