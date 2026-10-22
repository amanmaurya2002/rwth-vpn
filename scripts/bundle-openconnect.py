#!/usr/bin/env python3
"""Copy openconnect and its Homebrew dylibs into a flat, relocatable folder.

The shipped app must not depend on Homebrew being installed, so every Mach-O
gets its absolute /opt/homebrew load commands rewritten to @loader_path and is
re-signed ad-hoc. Output layout (flat, everything next to each other):

    openconnect
    libopenconnect.5.dylib
    libgnutls.30.dylib
    ...
    vpnc-script
    VERSIONS.txt       human readable build record
    MANIFEST.sha256    deterministic, used for drift detection

Usage:
    scripts/bundle-openconnect.py --out build/vendor
"""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import sys

SYSTEM_PREFIXES = ("/usr/lib/", "/System/")


def run(argv: list[str], check: bool = True) -> str:
    result = subprocess.run(argv, text=True, capture_output=True)
    if check and result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise SystemExit(f"command failed: {' '.join(argv)}")
    return result.stdout


def brew_prefix(formula: str) -> str:
    return run(["brew", "--prefix", formula]).strip()


def dependencies(path: str) -> list[str]:
    lines = run(["otool", "-L", path]).splitlines()[1:]
    deps = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        deps.append(line.split(" (")[0])
    return deps


def sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def collect(binary: str, homebrew: str) -> tuple[list[tuple[str, str]], dict[str, str]]:
    """Transitive non-system dependencies.

    Homebrew ships versioned files behind unversioned symlinks (for example
    libhogweed.7.dylib -> libhogweed.7.0.dylib), and different binaries refer to
    different names. We keep one real file per library plus symlinks for every
    alias so all load commands can stay literal @loader_path/<name>.
    """
    canonical: dict[str, str] = {}
    order: list[tuple[str, str]] = []
    aliases: dict[str, str] = {}
    queue = [binary]
    while queue:
        current = queue.pop(0)
        real = os.path.realpath(current)
        name = os.path.basename(current)
        if real in canonical:
            if canonical[real] != name:
                aliases.setdefault(name, canonical[real])
            continue
        canonical[real] = name
        order.append((real, name))
        for dep in dependencies(real):
            if dep.startswith(homebrew):
                queue.append(dep)
    return order, aliases


def rewrite(path: str, homebrew: str, is_dylib: bool) -> None:
    for dep in dependencies(path):
        if not dep.startswith(homebrew):
            continue
        target = f"@loader_path/{os.path.basename(dep)}"
        run(["install_name_tool", "-change", dep, target, path])
    if is_dylib:
        run(["install_name_tool", "-id", f"@loader_path/{os.path.basename(path)}", path])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="build/vendor")
    parser.add_argument("--openconnect", default=None)
    args = parser.parse_args()

    if shutil.which("brew") is None:
        raise SystemExit("Homebrew is required to bundle openconnect (brew install openconnect)")

    root = brew_prefix("openconnect").rsplit("/opt/", 1)[0]  # /opt/homebrew
    openconnect_prefix = brew_prefix("openconnect")
    binary = args.openconnect or os.path.join(openconnect_prefix, "bin", "openconnect")
    if not os.path.exists(binary):
        raise SystemExit(f"openconnect not found at {binary}\nRun: brew install openconnect")

    files, aliases = collect(binary, root)

    out = os.path.abspath(args.out)
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out, exist_ok=True)

    print(f"bundling {len(files)} binaries into {out}")
    for real, name in files:
        target = os.path.join(out, name)
        shutil.copy2(real, target)
        os.chmod(target, 0o755)
        rewrite(target, root, is_dylib=target.endswith(".dylib"))
        run(["codesign", "--force", "--sign", "-", "--timestamp=none", target])

    for alias, canonical_name in aliases.items():
        link = os.path.join(out, alias)
        if not os.path.exists(link):
            os.symlink(canonical_name, link)
            print(f"  alias {alias} -> {canonical_name}")

    script_source = os.path.join(root, "etc", "vpnc", "vpnc-script")
    if not os.path.exists(script_source):
        raise SystemExit(f"vpnc-script not found at {script_source}")
    shutil.copy2(script_source, os.path.join(out, "vpnc-script"))
    os.chmod(os.path.join(out, "vpnc-script"), 0o755)

    # GnuTLS has Homebrew's trust store path compiled in
    # (/opt/homebrew/etc/gnutls/cert.pem), which does not exist on a Mac
    # without Homebrew. Ship a CA bundle and pass it with --cafile.
    ca_candidates = [
        os.path.join(root, "etc", "ca-certificates", "cert.pem"),
        "/etc/ssl/cert.pem",
    ]
    ca_source = next((path for path in ca_candidates if os.path.exists(path)), None)
    if ca_source is None:
        raise SystemExit("no CA bundle found (looked for Homebrew ca-certificates and /etc/ssl/cert.pem)")
    shutil.copy2(ca_source, os.path.join(out, "cert.pem"))
    print(f"  CA bundle: {ca_source}")

    # Verify nothing still points into Homebrew.
    leftovers = []
    for _, name in files:
        for dep in dependencies(os.path.join(out, name)):
            if dep.startswith(root):
                leftovers.append(f"{name} -> {dep}")
            elif dep.startswith("@loader_path/") and not os.path.exists(os.path.join(out, dep.split("/", 1)[1])):
                leftovers.append(f"{name} -> {dep} (missing)")
    if leftovers:
        raise SystemExit("unrewritten dependencies:\n  " + "\n  ".join(leftovers))

    version = run([os.path.join(out, "openconnect"), "--version"]).splitlines()[0].strip()
    formula_versions = run(
        ["brew", "list", "--versions", "openconnect", "gnutls", "nettle", "gmp", "p11-kit",
         "stoken", "gettext", "libidn2", "libunistring", "libtasn1", "libtomcrypt", "libtommath"],
        check=False,
    ).strip()

    manifest_lines = []
    for name in sorted(os.listdir(out)):
        path = os.path.join(out, name)
        if os.path.isfile(path) and name not in ("VERSIONS.txt", "MANIFEST.sha256"):
            manifest_lines.append(f"{sha256(path)}  {name}")
    manifest = "\n".join(manifest_lines) + "\n"
    with open(os.path.join(out, "MANIFEST.sha256"), "w", encoding="utf-8") as handle:
        handle.write(manifest)

    with open(os.path.join(out, "VERSIONS.txt"), "w", encoding="utf-8") as handle:
        handle.write(f"{version}\n\n")
        handle.write("Bundled from Homebrew:\n")
        handle.write((formula_versions or "unknown") + "\n\n")
        handle.write("Files (sha256):\n")
        handle.write(manifest)
        handle.write("\nopenconnect is LGPL-2.1; see THIRD-PARTY-NOTICES.md for sources.\n")

    print(version)
    print(f"manifest sha256: {hashlib.sha256(manifest.encode()).hexdigest()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
