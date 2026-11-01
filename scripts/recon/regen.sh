#!/bin/bash
# For maintainers, after a game patch: regenerate the committed shim sources (shims/generated/) from
# the clients installed on this Mac. scripts/recon/regen.sh <xros|ios>
# Every installed flavor's client (scripts/flavor.sh: SP_INSTALL) is thinned and bucketed against the
# platform's SDK (bucket.py; needs PyYAML), their imports are merged, and gen_stubs.py rewrites
# shims/generated/ from the merged set. Then the shims are built (shims/build.sh) and every flavor's
# imports are checked to bind (verify_binds.py, and check_exports.py against exports.json). Prints
# what changed in shims/generated/ (git diff): review it like any other source change. Generated stubs only log; a new import the client really
# uses needs a hand-written implementation (gen_stubs.py EXTRA_CODE / EXTRA_INCLUDES).
# shims/generated/ is one set for both platforms: their SDKs bucket the clients' imports the same
# way, so only the build target differs (build.sh's argument). Run this for both platforms; the
# second run must show no diff. If it does, the platforms need separate generated sets.
# Scratch (thinned clients, SDK index caches, imports.json) goes to work/regen/<platform>/, which is
# gitignored: the clients are Blizzard's binaries and must never be committed.
set -euo pipefail
PLATFORM=${1:-}
case $PLATFORM in
  xros|ios) ;;
  *) echo "usage: $0 <xros|ios>" >&2; exit 1 ;;
esac
export SP_PLATFORM=$PLATFORM
cd "$(dirname "$0")/../.."
set +u  # the shared config scripts are plain sh
. scripts/flavor.sh
set -u
[ -n "$SP_FLAVORS" ] || { echo "regen.sh: no WoW client installed under $SP_INSTALL (set SP_INSTALL)" >&2; exit 1; }
python3 -c 'import yaml' 2>/dev/null || { echo "regen.sh: $(command -v python3) lacks PyYAML (pip install pyyaml)" >&2; exit 1; }
WORK=work/regen/$PLATFORM
GEN=shims/generated
mkdir -p "$WORK"

for f in $SP_FLAVORS; do
  echo "bucketing $f" >&2
  mkdir -p "$WORK/$f"
  lipo -thin arm64 "$(sp_flavor_client "$f")" -output "$WORK/$f/wow-arm64"
  # The SDK index takes ~45 s to build; share it (bucket.py rebuilds it if the SDK changed).
  cp -c "$WORK"/*-index.pickle "$WORK/$f/" 2>/dev/null || true
  python3 scripts/recon/bucket.py "$WORK/$f/wow-arm64" "$WORK/$f" >/dev/null
  cp -c "$WORK/$f"/*-index.pickle "$WORK/"
done

# One record per import over every flavor. The same import must bucket the same way in each (same SDK).
python3 - "$WORK" $SP_FLAVORS <<'PY'
import json, os, sys
work, flavors = sys.argv[1], sys.argv[2:]
merged = {}
for f in flavors:
    for r in json.load(open(os.path.join(work, f, "imports.json"))):
        key = (r["symbol"], r["from"], r["install_name"], r["kind"])
        if key in merged and (merged[key]["bucket"], merged[key]["stub"]) != (r["bucket"], r["stub"]):
            sys.exit(f"{key}: bucketed differently for {f}")
        merged.setdefault(key, r)
json.dump(sorted(merged.values(), key=lambda r: (r["from"], r["symbol"])),
          open(os.path.join(work, "imports.json"), "w"), indent=1)
print(f"{len(merged)} distinct imports over {', '.join(flavors)}", file=sys.stderr)
PY

rm -f "$GEN"/libsp*.m "$GEN"/libsp*.reexports "$GEN"/rewrite-map.txt "$GEN"/build.sh
binaries=()
for f in $SP_FLAVORS; do binaries+=("$WORK/$f/wow-arm64"); done
python3 scripts/recon/gen_stubs.py "$WORK" "$GEN" "${binaries[@]}"

shims/build.sh "$PLATFORM"
for f in $SP_FLAVORS; do
  echo -n "$f: " >&2
  python3 scripts/recon/verify_binds.py "$WORK/$f" "$GEN" "build/$PLATFORM"
  # The companion's check (exports.json) must agree with verify_binds.py's.
  echo -n "$f (exports.json): " >&2
  python3 scripts/recon/check_exports.py "build/$PLATFORM/exports.json" "$WORK/$f/wow-arm64"
done

echo "--- shims/generated/ against the last commit:"
if [ -z "$(git status --porcelain -- "$GEN")" ]; then
  echo "no change"
else
  git status --short -- "$GEN"
  git diff --stat -- "$GEN"
  echo "review with: git diff -- $GEN (new files: git status)"
fi
