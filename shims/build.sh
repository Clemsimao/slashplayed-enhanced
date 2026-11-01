#!/bin/sh
# Builds every shim dylib for one device platform, unsigned, into build/<platform>/ at the repo root:
#   shims/build.sh <xros|ios>
# The sources are committed, so this works from a clean clone: shims/generated/ (gen_stubs.py's
# output, one set for both platforms; scripts/recon/regen.sh remakes it after a game patch) #includes
# the hand-written files beside it (appkit/, audio/, ...), and its build.sh runs system/build.sh for
# libspSystem and libspdl. Then exports_manifest.py writes build/<platform>/exports.json (what every
# library in rewrite-map.txt provides on the device), which the companion's bind check reads.
set -e
case $1 in
  xros|ios) ;;
  *) echo "usage: $0 <xros|ios>" >&2; exit 1 ;;
esac
cd "$(dirname "$0")"
OUT=../build/$1
rm -rf "$OUT" && mkdir -p "$OUT"
sh generated/build.sh "$1" "$OUT"
# The system python3 is enough: the script uses only json, and reads the SDK's .tbds via llvm-readtapi.
python3 exports_manifest.py "$1" generated/rewrite-map.txt "$OUT" "$OUT/exports.json"
echo "built $(ls "$OUT"/*.dylib | wc -l | tr -d ' ') shims for $1 in build/$1" >&2
