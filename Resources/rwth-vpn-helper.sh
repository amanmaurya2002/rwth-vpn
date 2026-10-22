#!/bin/bash
# rwth-vpn-helper -- privileged helper for the RWTH VPN app.
#
# Installed as root:wheel 0755 at /usr/local/libexec/rwth-vpn-helper and
# allow-listed in /etc/sudoers.d/rwth-vpn-helper (NOPASSWD) for the local user.
#
# The openconnect client it runs is a root-owned copy under
# /usr/local/libexec/rwth-vpn/ that the app installs together with this script.
# The helper never accepts a path or extra openconnect options, so a modified
# or replaced .app cannot turn into root code execution.
#
#   connect <split|full> <ab123456>   connects (password then token on stdin)
#   stop                              disconnects the active session
#   version                           prints helper and payload versions
set -u
PATH=/usr/bin:/bin:/usr/sbin:/sbin
HELPER_VERSION="{{HELPER_VERSION}}"
PAYLOAD=/usr/local/libexec/rwth-vpn
OC="$PAYLOAD/openconnect"
VPNC_SCRIPT="$PAYLOAD/vpnc-script"
CA_BUNDLE="$PAYLOAD/cert.pem"
PIDFILE=/var/run/rwth-vpn-helper.pid
SERVER=vpn.rwth-aachen.de

die() { echo "$*" >&2; exit "${2:-64}"; }
usage() { die "usage: $0 connect <split|full> <ab123456> | stop | version"; }

[ "$(id -u)" -eq 0 ] || die "rwth-vpn-helper must run as root" 77

case "${1:-}" in
version)
    [ -d "$PAYLOAD" ] || die "openconnect payload missing" 69
    echo "helper=$HELPER_VERSION"
    if [ -f "$PAYLOAD/MANIFEST.sha256" ]; then
        echo "manifest=$(shasum -a 256 "$PAYLOAD/MANIFEST.sha256" | awk '{print $1}')"
    else
        echo "manifest="
    fi
    ;;
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
    [ -x "$OC" ] || die "openconnect payload missing; reinstall the helper" 69
    [ -x "$VPNC_SCRIPT" ] || die "vpnc-script missing; reinstall the helper" 69
    [ -f "$CA_BUNDLE" ] || die "CA bundle missing; reinstall the helper" 69

    # Record our own pid, then become openconnect: same pid, no fork, so the
    # caller's stdin (password, then token code) is passed through untouched.
    # Backgrounding here would redirect stdin to /dev/null and break the login.
    echo "$$" >"$PIDFILE"
    exec "$OC" \
        --protocol=anyconnect \
        --script="$VPNC_SCRIPT" \
        --no-system-trust \
        --cafile="$CA_BUNDLE" \
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
