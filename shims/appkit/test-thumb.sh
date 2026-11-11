#!/bin/bash
# Compile the real AppKit shim into a game-free UIKit fixture and replay synthetic touch input.
# Default: create and remove a disposable iPad simulator. SIMULATOR=<id> reuses an explicitly chosen
# simulator instead. --build-only skips simulator operations. Results and a screenshot stay in build/.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=$PWD/build/thumb-test
APP=$OUT/ThumbInputTest.app
BUNDLE=local.slashplayed.thumb-input-test
mkdir -p "$APP"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios26.0-simulator -isysroot "$SDK" \
    -fobjc-arc -fmodules -fmodules-cache-path="$OUT/modules" -O1 -Wno-objc-root-class \
    shims/appkit/tests/thumb-button.m -framework UIKit -framework Foundation -framework QuartzCore \
    -o "$APP/ThumbInputTest"
python3 - "$APP/Info.plist" "$BUNDLE" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier=sys.argv[2], CFBundleExecutable='ThumbInputTest',
        CFBundleName='Thumb input tests', CFBundlePackageType='APPL', CFBundleVersion='1',
        CFBundleShortVersionString='1.0', MinimumOSVersion='26.0', UIDeviceFamily=[2],
        UILaunchScreen={}, UIRequiresFullScreen=True, UIApplicationSceneManifest=dict(UIApplicationSupportsMultipleScenes=False),
        UISupportedInterfaceOrientations=['UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']), f)
PY
codesign -f -s - "$APP"
if [[ ${1:-} == --build-only ]]; then echo "Built $APP"; exit 0; fi
CREATED=0
cleanup() {
    if (( CREATED )); then
        xcrun simctl shutdown "$SIMULATOR" >/dev/null 2>&1 || true
        xcrun simctl delete "$SIMULATOR" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
if [[ -z ${SIMULATOR:-} ]]; then
    PAIR=$(xcrun simctl list runtimes -j | python3 -c '
import json,re,sys
r=[r for r in json.load(sys.stdin)["runtimes"] if r.get("isAvailable") and re.search(r"\.iOS-\d+-\d+$",r["identifier"])]
if not r: sys.exit("No available iOS simulator runtime. Install one in Xcode Settings > Components.")
runtime=max(r,key=lambda r:tuple(map(int,r["version"].split("."))))
ipads=[d for d in runtime.get("supportedDeviceTypes",[]) if d.get("productFamily")=="iPad"]
if not ipads: sys.exit("The selected simulator runtime has no supported iPad device type.")
print(runtime["identifier"],ipads[0]["identifier"])
')
    read -r RUNTIME DEVICE_TYPE <<< "$PAIR"
    SIMULATOR=$(xcrun simctl create "Slashplayed thumb input tests" "$DEVICE_TYPE" "$RUNTIME")
    CREATED=1
fi
if ! xcrun simctl list devices booted -j | python3 -c '
import json,sys
sys.exit(0 if any(d["udid"]==sys.argv[1] for ds in json.load(sys.stdin)["devices"].values() for d in ds) else 1)
' "$SIMULATOR"; then xcrun simctl boot "$SIMULATOR"; fi
xcrun simctl bootstatus "$SIMULATOR" -b
xcrun simctl install "$SIMULATOR" "$APP"
DATA=$(xcrun simctl get_app_container "$SIMULATOR" "$BUNDLE" data)
rm -f "$DATA/Documents/thumb-test-result.txt"
xcrun simctl launch --terminate-running-process "$SIMULATOR" "$BUNDLE"
for ((i=0; i<40; i++)); do
    [[ -f "$DATA/Documents/thumb-test-result.txt" ]] && break
    sleep 1
done
[[ -f "$DATA/Documents/thumb-test-result.txt" ]] || { echo "Thumb test timed out without a result." >&2; exit 1; }
cp "$DATA/Documents/thumb-test-result.txt" "$OUT/result.txt"
cat "$OUT/result.txt"; echo
xcrun simctl io "$SIMULATOR" screenshot "$OUT/preview.png" >/dev/null
grep -q '^PASS:' "$OUT/result.txt"
