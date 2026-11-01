#!/bin/sh
# Runs one experiment on the device (SP_PLATFORM picks it): ./run.sh e1|e2|e3|e4a|e4b|e4c|e4d|e5|e6|e6b|e7|h1|h2|h3|h4|p1|p2
# SP_JIT_MODE picks the prepare strategy (page, pagew, bulk; see jit.py).
# Launches stopped, attaches lldb with jit.py (except e4c), then prints the app's log. The H experiments
# use no lldb (the helper extension is the debugger): the app is launched with no arguments, reading the
# experiment from Documents/spjit-which, as it would be with nothing from the Mac.
set -e
cd "$(dirname "$0")"
. ../../scripts/platform.sh
sp_need_device
BUNDLE_ID=com.strawdynamics.spjittest
EXP=$1
mkdir -p out

case $EXP in h*|p*)
  echo "$EXP" > out/spjit-which
  xcrun devicectl device copy to --device "$SP_DEVICE" --domain-type appDataContainer \
    --domain-identifier $BUNDLE_ID --source out/spjit-which --destination Documents/spjit-which >/dev/null
  xcrun devicectl device process launch --device "$SP_DEVICE" --terminate-existing $BUNDLE_ID >/dev/null
  echo "launched $EXP; waiting for it to finish (up to 3 minutes: a disk image mount can take a while)"
  # The log is shared by every run, so wait for this run's own "done" line: the last "=== $EXP (" header
  # and a "=== $EXP done" after it.
  for _ in $(seq 36); do
    sleep 5
    rm -f out/spjit.log
    xcrun devicectl device copy from --device "$SP_DEVICE" --domain-type appDataContainer \
      --domain-identifier $BUNDLE_ID --source Documents/spjit.log --destination out/spjit.log >/dev/null 2>&1 || continue
    awk -v e="$EXP" 'index($0, "=== " e " (") == 1 { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' \
      out/spjit.log > out/run.log
    head -1 out/run.log | grep -q "^=== $EXP (" && grep -q "^=== $EXP done" out/run.log && break
  done
  cat out/run.log
  exit
esac

if [ "$EXP" = e4c ]; then
  xcrun devicectl device process launch --device "$SP_DEVICE" --terminate-existing --console $BUNDLE_ID "$EXP"
  exit
fi

xcrun devicectl device process launch --device "$SP_DEVICE" --terminate-existing --start-stopped \
  --json-output out/launch.json $BUNDLE_ID "$EXP" >/dev/null
PID=$(python3 -c 'import json; print(json.load(open("out/launch.json"))["result"]["process"]["processIdentifier"])')
echo "launched pid $PID"
# Without the local executable, lldb's attach races with spjit (stale stops, refused register writes).
xcrun lldb -b out/SPJitTest.app/SPJitTest \
  -o "command script import jit.py" \
  -o "device select $SP_DEVICE" \
  -o "device process attach -p $PID" \
  -o "spjit ${SP_JIT_MODE:-page}" 2>&1 | grep -E '^\[spjit\]|error|Error' || true

sleep 3
rm -f out/spjit.log
xcrun devicectl device copy from --device "$SP_DEVICE" --domain-type appDataContainer \
  --domain-identifier $BUNDLE_ID --source Documents/spjit.log --destination out/spjit.log >/dev/null
sed -n "/=== $EXP (pid $PID/,\$p" out/spjit.log
