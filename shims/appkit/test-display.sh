#!/bin/bash
# Validate backing pixels, portrait rotation, display callbacks, and real Metal drawable sizes.
# No game or Apple account. --build-only skips the disposable simulator; SIMULATOR=<id> reuses one.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT=$PWD/build/display-test
APP=$OUT/DisplayTest.app
BUNDLE=local.slashplayed.display-test
mkdir -p "$APP"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios26.0-simulator -isysroot "$SDK" \
    -fobjc-arc -fmodules -fmodules-cache-path="$OUT/modules" -O1 -Wno-objc-root-class \
    shims/appkit/tests/display.m -framework UIKit -framework Foundation -framework QuartzCore \
    -o "$APP/DisplayTest"
python3 - "$APP/Info.plist" "$BUNDLE" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier=sys.argv[2], CFBundleExecutable='DisplayTest',
        CFBundleName='Display tests', CFBundlePackageType='APPL', CFBundleVersion='1',
        CFBundleShortVersionString='1.0', MinimumOSVersion='26.0', UIDeviceFamily=[2],
        UILaunchScreen={}, UIApplicationSceneManifest=dict(UIApplicationSupportsMultipleScenes=False),
        UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
            'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']), f)
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
    SIMULATOR=$(xcrun simctl create "Slashplayed display tests" "$DEVICE_TYPE" "$RUNTIME")
    CREATED=1
fi
if ! xcrun simctl list devices booted -j | python3 -c '
import json,sys
sys.exit(0 if any(d["udid"]==sys.argv[1] for ds in json.load(sys.stdin)["devices"].values() for d in ds) else 1)
' "$SIMULATOR"; then xcrun simctl boot "$SIMULATOR"; fi
xcrun simctl bootstatus "$SIMULATOR" -b
xcrun simctl install "$SIMULATOR" "$APP"
DATA=$(xcrun simctl get_app_container "$SIMULATOR" "$BUNDLE" data)
: > "$OUT/results.txt"
for scenario in '0 0' '1920 0' '2560 0' '1 0' '2 0' '0 2' '2560 1 2' '1920 0 inf' '1234 0' '2560 0 invalid hide2560' '2560 0 invalid nativeonly'; do
    rm -f "$DATA/Documents/display-test-result.txt"
    read -r -a args <<< "$scenario"
    xcrun simctl launch --terminate-running-process "$SIMULATOR" "$BUNDLE" "${args[@]}"
    for ((i=0; i<30; i++)); do
        [[ -f "$DATA/Documents/display-test-result.txt" ]] && break
        sleep 1
    done
    [[ -f "$DATA/Documents/display-test-result.txt" ]] || { echo "Display test timed out ($scenario)." >&2; exit 1; }
    result=$(cat "$DATA/Documents/display-test-result.txt")
    echo "$scenario: $result"
    echo "$scenario: $result" >> "$OUT/results.txt"
    [[ $result == PASS:* ]] || exit 1
done
