#!/usr/bin/env python3
"""Writes exports.json: what every library the client links resolves to on the device.

Usage: exports_manifest.py <xros|ios> <rewrite-map.txt> <built-dylib-dir> <out.json>

Run by shims/build.sh after the dylibs are built. The companion's bind check reads it (it ships one per
platform): a client import binds iff its symbol is listed under the install name it's imported from.
That replaces running verify_binds.py (and the SDK's .tbd files, and PyYAML) on the user's Mac.

{"platform": "xros", "sdk": "27.0",
 "libraries": {"<client's install name>": {"target": "<rewrite-map target>", "symbols": [...]}}}

One entry per rewrite-map line, keyed by the install name in the client's load commands (dyld_info
-imports names it by short name: "(from AppKit)"; map that through the client's otool -L). "symbols"
is everything the target exports, flattened through its re-exports, the same rule verify_binds.py
applies:
- a shim (@rpath/...): its own exports trie (definitions plus -reexported_symbols_list entries, from
  dyld_info -exports), plus all of every LC_REEXPORT_DYLIB (an SDK library, or another built shim:
  libspSystem re-exports libspdl);
- an SDK library (an import that isn't remapped): its .tbd's exports plus its re-exported libraries'.
The .tbds are read through llvm-readtapi's JSON output (tbd v5), so only Xcode is needed. Only the
libraries reachable from the map are read. Lists are sorted, so the file diffs cleanly between builds.
"""
import json
import os
import re
import subprocess
import sys

SDKS = {"xros": "xros", "ios": "iphoneos"}

# tbd v5 symbol kinds -> the names the client imports them under (matches bucket.py's v4 reading).
OBJC_KINDS = {
    "objc_class": ("_OBJC_CLASS_$_", "_OBJC_METACLASS_$_"),
    "objc_eh_type": ("_OBJC_EHTYPE_$_",),
    "objc_ivar": ("_OBJC_IVAR_$_",),
}
PLAIN_KINDS = ("global", "weak", "thread_local")


def sh(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def tbd_symbols(sections):
    out = set()
    for section in sections or []:
        for part in ("data", "text"):
            for kind, names in (section.get(part) or {}).items():
                if kind in PLAIN_KINDS:
                    out.update(names)
                elif kind in OBJC_KINDS:
                    out.update(p + n for n in names for p in OBJC_KINDS[kind])
                else:
                    sys.exit(f"exports_manifest.py: unknown tbd symbol kind '{kind}'; teach this script")
    return out


class Sdk:
    """install name -> (exported symbols, re-exported install names), read from the SDK's .tbds on demand."""

    def __init__(self, sdk_name):
        self.path = sh("xcrun", "--sdk", sdk_name, "--show-sdk-path").strip()
        self.version = sh("xcrun", "--sdk", sdk_name, "--show-sdk-version").strip()
        self.libs = {}

    def _load(self, tbd):
        doc = json.loads(sh("xcrun", "llvm-readtapi", "--filetype=tbd-v5", tbd))
        # An umbrella's .tbd inlines its sub-libraries (libSystem.B.tbd holds /usr/lib/system/*).
        for lib in [doc["main_library"]] + (doc.get("libraries") or []):
            syms = tbd_symbols(lib.get("exported_symbols")) | tbd_symbols(lib.get("reexported_symbols"))
            reexports = {n for e in lib.get("reexported_libraries") or [] for n in e.get("names") or []}
            for name in lib["install_names"]:
                self.libs[name["name"]] = (syms, reexports)

    def lib(self, name):
        if name not in self.libs:
            # /usr/lib/libSystem.B.dylib -> usr/lib/libSystem.B.tbd; X.framework/X -> X.framework/X.tbd
            stem = name[:-len(".dylib")] if name.endswith(".dylib") else name
            tbd = os.path.join(self.path, stem.lstrip("/") + ".tbd")
            if not os.path.exists(tbd):
                sys.exit(f"exports_manifest.py: no {tbd} for {name} (a library the map or a shim needs "
                         f"isn't in the {self.version} SDK, or it's inlined in a .tbd not read yet)")
            self._load(tbd)
            if name not in self.libs:
                sys.exit(f"exports_manifest.py: {tbd} doesn't define {name}")
        return self.libs[name]


def shim_lib(path):
    """(own exported symbols, LC_REEXPORT_DYLIB install names) of a built shim; as verify_binds.py reads it."""
    syms = set()
    for line in sh("dyld_info", "-exports", path).splitlines():
        m = re.match(r"\s+0x[0-9A-F]+\s+(\S+)", line) or re.match(r"\s+\[re-export\]\s+(\S+)", line)
        if m:
            syms.add(m.group(1))
    reexports = set(re.findall(r"cmd LC_REEXPORT_DYLIB\n\s+cmdsize \d+\n\s+name (\S+)", sh("otool", "-l", path)))
    return syms, reexports


def main():
    if len(sys.argv) != 5 or sys.argv[1] not in SDKS:
        sys.exit("usage: exports_manifest.py <xros|ios> <rewrite-map.txt> <built-dylib-dir> <out.json>")
    platform, map_path, built_dir, out_path = sys.argv[1:]
    sdk = Sdk(SDKS[platform])

    def lib(name):
        if name.startswith("@rpath/"):
            path = os.path.join(built_dir, name[len("@rpath/"):])
            if not os.path.exists(path):
                sys.exit(f"exports_manifest.py: {name} isn't built ({path} missing)")
            return shim_lib(path)
        return sdk.lib(name)

    closures = {}

    def closure_symbols(name):
        if name not in closures:
            seen, stack, syms = set(), [name], set()
            while stack:
                n = stack.pop()
                if n in seen:
                    continue
                seen.add(n)
                own, reexports = lib(n)
                syms |= own
                stack.extend(reexports)
            closures[name] = sorted(syms)
        return closures[name]

    libraries = {}
    for line in open(map_path):
        if line.strip():
            orig, target = line.strip().split(" -> ")
            libraries[orig] = {"target": target, "symbols": closure_symbols(target)}

    with open(out_path, "w") as fh:
        json.dump({"platform": platform, "sdk": sdk.version, "libraries": libraries}, fh, indent=0)
        fh.write("\n")


if __name__ == "__main__":
    main()
