#!/bin/sh
# Fetches everything needed to triage a play session from the headset, then prints a summary:
#   - Documents/spconsole*.log: the shims' console, the last 5 launches (spconsole.log is the latest),
#     each line stamped with the local time. stats: lines every 30 s, lifecycle: lines as they happen.
#   - Documents/<flavor>/Logs and Errors: the client's own logs and error reports.
#   - The system's crash, jetsam and resource reports that mention the app (systemCrashLogs).
# Output: work/triage/<date-time>/ (newest also at work/triage/latest). SP_FLAVOR picks the flavor
# folder (scripts/flavor.sh). Needs the headset awake, unlocked and on the network. The companion does
# the same in Swift (apps/companion/Sources/DeviceLogs.swift, Pull Device Logs): keep the two in step.
set -e
cd "$(dirname "$0")"
. ../../scripts/platform.sh
sp_need SP_BUNDLE_ID
sp_need_device
BUNDLE_ID=$SP_BUNDLE_ID
. ../../scripts/flavor.sh
OUT=../../work/triage/$(date +%Y%m%d-%H%M%S)
mkdir -p $OUT/app $OUT/system
ln -sfn "$(basename $OUT)" ../../work/triage/latest

# list <json out> <prefix> <devicectl domain args...>: paths of the files there, one per line, each
# after <prefix> (the listing's paths are relative to its --subdirectory).
list() {
  out=$1 prefix=$2; shift 2
  timeout 90 xcrun devicectl device info files --device "$SP_DEVICE" "$@" --json-output $out >/dev/null 2>&1 || return 0
  python3 -c 'import json,sys
for f in json.load(open(sys.argv[1]))["result"]["files"]: print(sys.argv[2] + f["relativePath"])' $out "$prefix"
}
APP="--domain-type appDataContainer --domain-identifier $BUNDLE_ID"
fetch() {  # fetch <domain args> <source> <dest>
  timeout 90 xcrun devicectl device copy from --device "$SP_DEVICE" $1 --source "$2" --destination "$3" >/dev/null 2>&1 \
    && echo "  $2" || echo "  $2 (failed)"
}

echo "app container:"
{
  list $OUT/docs.json Documents/ $APP --subdirectory Documents | /usr/bin/grep -E '^Documents/spconsole[.0-9]*log$' || true
  list $OUT/logs.json Documents/$SP_FLAVOR_DIR/Logs/ $APP --subdirectory Documents/$SP_FLAVOR_DIR/Logs --recurse
  list $OUT/errors.json Documents/$SP_FLAVOR_DIR/Errors/ $APP --subdirectory Documents/$SP_FLAVOR_DIR/Errors --recurse
} | while read -r src; do
  [ "${src%/}" = "$src" ] || continue
  mkdir -p "$OUT/app/$(dirname "$src")"
  fetch "$APP" "$src" "$OUT/app/$src"
done

echo "system reports:"
list $OUT/crash.json "" --domain-type systemCrashLogs --recurse | /usr/bin/grep -i -E 'wow|slashplayed|jetsam|exc_?resource' \
  | while read -r f; do
  mkdir -p "$OUT/system/$(dirname "$f")"
  fetch "--domain-type systemCrashLogs" "$f" "$OUT/system/$f"
done

# ---- summary
D=$OUT/app/Documents
echo
echo "== saved in work/triage/$(basename $OUT)"
for log in $D/spconsole.log $D/spconsole.[1-5].log; do
  [ -f "$log" ] || continue
  echo
  echo "== $(basename $log): $(head -1 "$log" | cut -c1-8) to $(tail -1 "$log" | cut -c1-8)"
  # fps: average and the lowest 30 s window; footprint: the highest peak; least memory left.
  /usr/bin/grep 'stats: ' "$log" | python3 -c '
import re, sys
rows = [l for l in sys.stdin]
if not rows: print("  no stats lines"); sys.exit()
fps = [float(re.search(r"([0-9.]+) fps", l).group(1)) for l in rows]
worst = max(int(re.search(r"worst (\d+) ms", l).group(1)) for l in rows)
slow = sum(int(re.search(r"(\d+) over 50 ms", l).group(1)) for l in rows)
peak = max(int(re.search(r"peak (\d+)", l).group(1)) for l in rows)
left = min(int(re.search(r"(\d+) MB left", l).group(1)) for l in rows)
therm = "/".join(sorted(set(re.search(r"thermal (\w+)", l).group(1) for l in rows)))
print(f"  {len(rows)} stats lines: {sum(fps)/len(fps):.1f} fps average, {min(fps):.1f} lowest 30 s, "
      f"worst frame {worst} ms, {slow} frames over 50 ms")
print(f"  footprint peak {peak} MB, least left {left} MB, thermal {therm}")'
  echo "  events:"
  /usr/bin/grep -E 'lifecycle: |MEMORY|crash: |FAULT|hasn.t pumped|objc exception|Fatal|signal' "$log" \
    | cut -c1-160 | sed 's/^/    /' | tail -40
  echo "  last lines:"
  tail -5 "$log" | cut -c1-160 | sed 's/^/    /'
done
ls $OUT/app/Documents/$SP_FLAVOR_DIR/Errors 2>/dev/null | sed 's/^/client error report: /' || true
find $OUT/system -type f 2>/dev/null | sed "s|^$OUT/system/|system report: |"
