#!/usr/bin/env python3
"""Phase 1 recon: bucket every import of a macOS Mach-O against the visionOS SDK.

Usage: bucket.py <thin-arm64-binary> <out-dir>

Writes:
  <out>/imports.json   one record per import (symbol, source lib, kind, bucket, where)
  <out>/report.md      human-readable summary grouped by bucket and source lib

Buckets:
  available  exported by the same library (or its re-exports) in the visionOS SDK
  different  exported by visionOS, but from a different library, or listed in KNOWN_DIFFERENT
  missing    not exported anywhere in the visionOS SDK

"stub" is true when the shim must define the symbol itself (missing, or a known difference).
"""
import json
import os
import pickle
import re
import subprocess
import sys
from collections import defaultdict

import yaml

# The device platform (SP_PLATFORM, as in scripts/platform.sh): its SDK, and the clang target the
# generated shims build with. The docs here say visionOS; with ios it's the iPhoneOS SDK instead.
PLATFORMS = {"xros": ("xros", "arm64-apple-xros1.0"), "ios": ("iphoneos", "arm64-apple-ios26.0")}
PLATFORM = os.environ.get("SP_PLATFORM", "xros")
SDK_NAME, SHIM_TARGET = PLATFORMS[PLATFORM]

# Symbols that exist on visionOS but behave differently enough to need a shim anyway.
KNOWN_DIFFERENT = {
    # CVDisplayLink is absent on visionOS; back it with CADisplayLink.
    re.compile(r"^_CVDisplayLink"): "CVDisplayLink -> CADisplayLink",
}

OBJC_PREFIXES = {
    "_OBJC_CLASS_$_": "objc-class",
    "_OBJC_METACLASS_$_": "objc-metaclass",
    "_OBJC_IVAR_$_": "objc-ivar",
    "_OBJC_EHTYPE_$_": "objc-ehtype",
}


def sh(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


# ---------------------------------------------------------------- tbd index


class _TbdLoader(yaml.SafeLoader):
    pass


_TbdLoader.add_multi_constructor("!", lambda loader, suffix, node: loader.construct_mapping(node))


def _syms_from_section(entries):
    out = set()
    for e in entries or []:
        out.update(e.get("symbols") or [])
        out.update(e.get("weak-symbols") or [])
        out.update(e.get("thread-local-symbols") or [])
        for c in e.get("objc-classes") or []:
            out.add("_OBJC_CLASS_$_" + c)
            out.add("_OBJC_METACLASS_$_" + c)
        for c in e.get("objc-eh-types") or []:
            out.add("_OBJC_EHTYPE_$_" + c)
        for c in e.get("objc-ivars") or []:
            out.add("_OBJC_IVAR_$_" + c)
    return out


class TbdIndex:
    """install-name -> (exported symbols, re-exported install names) for one SDK."""

    def __init__(self, sdk):
        self.exports = defaultdict(set)
        self.reexports = defaultdict(set)
        for root in ("System/Library/Frameworks", "usr/lib"):
            for dirpath, dirnames, filenames in os.walk(os.path.join(sdk, root)):
                # Skip nested private frameworks and headers; they only slow the walk down.
                dirnames[:] = [d for d in dirnames if d not in ("Headers", "Modules", "PrivateHeaders")]
                for f in filenames:
                    if f.endswith(".tbd"):
                        self._load(os.path.join(dirpath, f))

    def _load(self, path):
        with open(path) as fh:
            for doc in yaml.load_all(fh, Loader=_TbdLoader):
                if not doc or "install-name" not in doc:
                    continue
                name = doc["install-name"]
                self.exports[name] |= _syms_from_section(doc.get("exports"))
                self.exports[name] |= _syms_from_section(doc.get("reexports"))
                for e in doc.get("reexported-libraries") or []:
                    self.reexports[name].update(e.get("libraries") or [])

    def closure(self, name):
        seen, stack = set(), [name]
        while stack:
            n = stack.pop()
            if n in seen:
                continue
            seen.add(n)
            stack.extend(self.reexports.get(n, ()))
        return seen

    def provider(self, name, sym):
        """The library in name's re-export closure that actually exports sym, or None."""
        for n in sorted(self.closure(name)):
            if sym in self.exports.get(n, ()):
                return n
        return None

    def find_anywhere(self, sym):
        if not hasattr(self, "_by_symbol"):
            self._by_symbol = defaultdict(list)
            for n in sorted(self.exports):
                for s in self.exports[n]:
                    self._by_symbol[s].append(n)
        return self._by_symbol.get(sym, [])

    def install_name_for(self, short):
        """This SDK's install name for a library short name (frameworks may or may not be versioned)."""
        if not hasattr(self, "_by_short"):
            self._by_short = {}
            for n in sorted(self.exports, key=len):
                self._by_short.setdefault(short_name(n), n)
        return self._by_short.get(short)


def short_name(install_name):
    # Matches dyld_info's "(from X)" naming: AppKit, libSystem, libc++abi, libobjc.
    return os.path.basename(install_name).split(".")[0]


# ---------------------------------------------------------------- binary


def read_imports(binary):
    """[(symbol, source short name)] from dyld_info -imports."""
    out = []
    for line in sh("dyld_info", "-imports", binary).splitlines():
        m = re.match(r"\s+(?:0x[0-9A-Fa-f]+\s+)?(\S+)\s+\(from (\S+)\)", line)
        if m:
            out.append((m.group(1), m.group(2)))
    return out


def read_dylibs(binary):
    """short name -> full install name for every LC_LOAD_DYLIB."""
    out = {}
    for line in sh("otool", "-L", binary).splitlines()[1:]:
        path = line.strip().split(" (")[0]
        out[short_name(path)] = path
    return out


def read_kinds(imports, dylibs, symkind):
    """symbol -> function|data, from where the running macOS's copy of each symbol lives."""
    by_lib = defaultdict(list)
    for sym, src in imports:
        if src in dylibs and not any(sym.startswith(p) for p in OBJC_PREFIXES):
            by_lib[dylibs[src]].append(sym)
    kinds = {}
    for lib, syms in by_lib.items():
        out = subprocess.run([symkind, lib], input="\n".join(syms), check=True,
                             capture_output=True, text=True).stdout
        for line in out.splitlines():
            sym, kind = line.split()
            kinds[sym] = kind
    return kinds


def classify_kind(sym, kinds):
    for prefix, kind in OBJC_PREFIXES.items():
        if sym.startswith(prefix):
            return kind
    return kinds.get(sym, "absent")


def load_xros_index(out_dir):
    """The device SDK's TbdIndex, cached in out_dir per SDK path (parsing the SDK takes ~40 s)."""
    sdk = sh("xcrun", "--sdk", SDK_NAME, "--show-sdk-path").strip()
    cache = os.path.join(out_dir, f"{SDK_NAME}-index.pickle")
    if os.path.exists(cache):
        with open(cache, "rb") as fh:
            cached_sdk, index = pickle.load(fh)
        if cached_sdk == sdk:
            return index
    index = TbdIndex(sdk)
    with open(cache, "wb") as fh:
        pickle.dump((sdk, index), fh)
    return index


# ---------------------------------------------------------------- main


def main():
    binary, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    xros = load_xros_index(out_dir)
    symkind = os.path.join(out_dir, "symkind")
    subprocess.run(["clang", "-O1", os.path.join(os.path.dirname(__file__), "symkind.c"), "-o", symkind],
                   check=True)

    imports = read_imports(binary)
    dylibs = read_dylibs(binary)
    kinds = read_kinds(imports, dylibs, symkind)

    records = []
    for sym, src in imports:
        xros_install = xros.install_name_for(src)
        rec = {
            "symbol": sym,
            "from": src,
            "install_name": dylibs.get(src),
            "kind": classify_kind(sym, kinds),
        }
        same = xros.provider(xros_install, sym) if xros_install else None
        note = next((n for rx, n in KNOWN_DIFFERENT.items() if rx.search(sym)), None)
        if note:
            rec.update(bucket="different", where=None, note=note, stub=True)
        elif same:
            rec.update(bucket="available", where=same, stub=False)
        else:
            elsewhere = xros.find_anywhere(sym)
            if elsewhere:
                rec.update(bucket="different", where=elsewhere[0], note="exported by a different library", stub=False)
            else:
                rec.update(bucket="missing", where=None, stub=True)
        records.append(rec)

    with open(os.path.join(out_dir, "imports.json"), "w") as fh:
        json.dump(records, fh, indent=1)
    write_report(records, os.path.join(out_dir, "report.md"), binary)

    counts = defaultdict(int)
    for r in records:
        counts[r["bucket"]] += 1
    print(f"{len(records)} imports: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))


def write_report(records, path, binary):
    by_bucket = defaultdict(lambda: defaultdict(list))
    for r in records:
        by_bucket[r["bucket"]][r["from"]].append(r)
    lines = [f"# Import buckets for `{os.path.basename(binary)}` vs visionOS SDK", ""]
    lines.append("| source | available | different | missing |")
    lines.append("|---|---|---|---|")
    for src in sorted({r["from"] for r in records}):
        row = [str(len(by_bucket[b].get(src, ()))) for b in ("available", "different", "missing")]
        lines.append(f"| {src} | " + " | ".join(row) + " |")
    for bucket in ("missing", "different", "available"):
        lines += ["", f"## {bucket}", ""]
        for src in sorted(by_bucket[bucket]):
            lines.append(f"### {src}")
            for r in sorted(by_bucket[bucket][src], key=lambda r: r["symbol"]):
                extra = ""
                if bucket == "different":
                    extra = f" -> `{r['where']}` ({r['note']})" if r["where"] else f" ({r['note']})"
                lines.append(f"- `{r['symbol']}` [{r['kind']}]{extra}")
            lines.append("")
    with open(path, "w") as fh:
        fh.write("\n".join(lines))


if __name__ == "__main__":
    main()
