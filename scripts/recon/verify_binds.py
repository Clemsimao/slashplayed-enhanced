#!/usr/bin/env python3
"""Phase 1 check: would every import bind on visionOS after the load-command rewrite?

Usage: verify_binds.py <recon-out-dir> [<shim-dir> <built-dylib-dir>]

Resolves each import through the rewrite map (<shim-dir>/rewrite-map.txt, default
<recon-out-dir>/shims; shims/generated in the repo): against a built shim's own exports (in
<built-dylib-dir>, default <shim-dir>/build; build/<platform> from shims/build.sh) plus the
re-exported visionOS libraries it names, or against the visionOS SDK's .tbd files directly.
Exits non-zero and lists anything unresolved.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import bucket  # noqa: E402


def shim_exports(path):
    """(own exported symbols, re-exported install names) of a built shim dylib."""
    syms = set()
    for line in bucket.sh("dyld_info", "-exports", path).splitlines():
        m = re.match(r"\s+0x[0-9A-F]+\s+(\S+)", line)
        if m:
            syms.add(m.group(1))
        m = re.match(r"\s+\[re-export\]\s+(\S+)", line)  # symbol re-exported from another library
        if m:
            syms.add(m.group(1))
    out = bucket.sh("otool", "-l", path)
    reexported = set(re.findall(r"cmd LC_REEXPORT_DYLIB\n\s+cmdsize \d+\n\s+name (\S+)", out))
    return syms, reexported


def main():
    out_dir = sys.argv[1]
    sys.modules["__main__"].TbdIndex = bucket.TbdIndex  # for unpickling
    xros = bucket.load_xros_index(out_dir)
    records = json.load(open(os.path.join(out_dir, "imports.json")))
    shim_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(out_dir, "shims")
    built_dir = sys.argv[3] if len(sys.argv) > 3 else os.path.join(shim_dir, "build")

    target_for = {}
    for line in open(os.path.join(shim_dir, "rewrite-map.txt")):
        orig, new = line.strip().split(" -> ")
        target_for[bucket.short_name(orig)] = new

    shims = {}
    unresolved = []
    for r in records:
        sym, target = r["symbol"], target_for[r["from"]]
        if target.startswith("@rpath/"):
            if target not in shims:
                shims[target] = shim_exports(os.path.join(built_dir, os.path.basename(target)))
            own, reexported = shims[target]
            ok = sym in own or any(xros.provider(lib, sym) for lib in reexported)
        else:
            ok = xros.provider(target, sym) is not None
        if not ok:
            unresolved.append((r["from"], sym, target))

    for src, sym, target in unresolved:
        print(f"UNRESOLVED {src}/{sym} -> {target}")
    print(f"{len(records) - len(unresolved)}/{len(records)} imports resolve")
    sys.exit(1 if unresolved else 0)


if __name__ == "__main__":
    main()
