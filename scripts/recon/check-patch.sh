#!/bin/sh
# After a game patch: does the flavor's new client still work with the current shims? Thins the
# installed client into work/patchcheck/<flavor>/, buckets its imports (bucket.py) and compares them
# with the ones recorded for the flavor when its shims were last checked: Classic Era's in work/recon
# (where the shims were last checked), every other flavor's in work/<flavor>/recon. New imports
# that visionOS exports from the same library need no shim change (Retail 12.1.0 -> 12.1.5 added 18
# such: libc++ mutexes, a few libSystem functions); any other new import does. Then verify_binds.py
# checks every import resolves against the committed shims (shims/generated, built into build/xros).
# regen.sh isn't run: without new imports to shim it would write the same shims, and with them a
# developer has to look first.
# When the client passes, its imports and thinned binary become the flavor's new record.
# Exit status: 0 it works with the current shims; 2 it needs a developer (the output says why);
# anything else, the check itself failed.
set -e
cd "$(dirname "$0")"
. ../flavor.sh
WORK=../../work
case $SP_FLAVOR in
  classic_era) REF=$WORK/recon ;;
  *) REF=$WORK/$SP_FLAVOR/recon ;;
esac
OUT=$WORK/patchcheck/$SP_FLAVOR
rm -rf $OUT && mkdir -p $OUT/recon
lipo -thin arm64 "$SP_CLIENT" -output $OUT/wow-arm64
# The SDK index takes ~45 s to build; reuse the shims' (it's rebuilt if the SDK changed).
cp -c $WORK/recon/*-index.pickle $OUT/recon/ 2>/dev/null || true
python3 bucket.py $OUT/wow-arm64 $OUT/recon
[ -d ../../build/xros ] || ../../shims/build.sh xros

# Imports compare by what comes from the binary (symbol, library, kind): the buckets also depend on
# the SDK, and verify_binds.py covers that.
if ! python3 - $REF/imports.json $OUT/recon/imports.json <<'PY'
import json, sys
def load(p):
    return {(r["symbol"], r["from"], r["install_name"], r["kind"]): r for r in json.load(open(p))}
old, new = load(sys.argv[1]), load(sys.argv[2])
added, removed = new.keys() - old.keys(), old.keys() - new.keys()
if not added and not removed:
    print(f"imports unchanged ({len(new)})")
needs_shim = [k for k in added if new[k]["bucket"] != "available"]
for label, rows in (("added", added), ("removed", removed)):
    if not rows:
        continue
    print(f"{len(rows)} imports {label}:")
    for k in sorted(rows)[:30]:
        r = (new if label == "added" else old)[k]
        print(f"  {r['from']} {r['symbol']} ({r['kind']}, {r['bucket']})")
    if len(rows) > 30:
        print(f"  ... and {len(rows) - 30} more")
if needs_shim:
    print(f"{len(needs_shim)} new imports aren't exported by the same visionOS library: the shims need work")
    sys.exit(2)
PY
then
  echo "the $SP_FLAVOR client needs new shims (its recorded imports: $REF/imports.json)"
  exit 2
fi
python3 verify_binds.py $OUT/recon ../../shims/generated ../../build/xros || exit 2
cp $OUT/recon/imports.json $OUT/recon/report.md $REF/
cp $OUT/wow-arm64 $(dirname $REF)/wow-arm64
echo "recorded the $SP_FLAVOR client's imports in $REF"
