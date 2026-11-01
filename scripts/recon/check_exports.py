#!/usr/bin/env python3
"""Offline bind check of a thinned client against a built exports.json (shims/exports_manifest.py).

Usage: check_exports.py <exports.json> <thinned-client>

What the companion's bind check does, for maintainers: every import (dyld_info -imports, "(from X)")
is looked up under the install name X has in the client's load commands. Unlike verify_binds.py it
needs no SDK index, PyYAML or imports.json, only Xcode's command-line tools. The two must agree;
shims/build.sh plus this is the check regen.sh's verify_binds.py run stands for on a user's Mac.
Exits non-zero and lists anything unresolved.
"""
import json
import os
import re
import subprocess
import sys


def sh(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: check_exports.py <exports.json> <thinned-client>")
    manifest, client = sys.argv[1:]
    libraries = json.load(open(manifest))["libraries"]

    # short name ("AppKit", "libSystem", "libc++abi") -> install name, as bucket.short_name derives it
    install_name = {}
    for line in sh("otool", "-L", client).splitlines()[1:]:
        path = line.strip().split(" (")[0]
        install_name[os.path.basename(path).split(".")[0]] = path

    symbols = {}
    total, unresolved = 0, []
    for line in sh("dyld_info", "-imports", client).splitlines():
        m = re.match(r"\s+(?:0x[0-9A-Fa-f]+\s+)?(\S+)\s+\(from (\S+)\)", line)
        if not m:
            continue
        sym, src = m.groups()
        total += 1
        lib = libraries.get(install_name.get(src, ""))
        if lib is None:
            unresolved.append((src, sym, "not in the rewrite map"))
            continue
        if src not in symbols:
            symbols[src] = set(lib["symbols"])
        if sym not in symbols[src]:
            unresolved.append((src, sym, lib["target"]))

    for src, sym, target in unresolved:
        print(f"UNRESOLVED {src}/{sym} -> {target}")
    print(f"{total - len(unresolved)}/{total} imports resolve")
    sys.exit(1 if unresolved else 0)


if __name__ == "__main__":
    main()
