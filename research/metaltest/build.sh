#!/bin/sh
# Metallib retag test: builds our own kernel for macOS and visionOS,
# makes the retagged variants with mtlb.py, bundles them into SPMetalTest.app's libs/, signs and
# installs. Run with run.sh. Env: SP_PLATFORM (scripts/platform.sh), SP_DEVICE, SP_TEAM, SP_SIGN_ID,
# SP_PROFILE (as research/jittest).
set -e
cd "$(dirname "$0")"
. ../../scripts/platform.sh
sp_need SP_TEAM SP_SIGN_ID
BUNDLE_ID=com.strawdynamics.spmetaltest
: "${SP_PROFILE:=$(sp_profile $BUNDLE_ID)}"
OUT=out
APP=$OUT/SPMetalTest.app
L=$OUT/lib

rm -rf $APP $L && mkdir -p $APP/libs $L
# a: controls built for the device platform. b: macOS builds as they come; the deployment target picks the container
# version (10.11/10.13 -> v2.2, 10.14 -> 2.3, 10.15 -> 2.4, 11 -> 2.5, 12 -> 2.6, 13/14 -> 2.7).
# c: the same with the header's macOS flag cleared (mtlb.py retag); nothing else changes.
if [ $SP_PLATFORM = xros ]; then
  xcrun -sdk xros metal -target air64-apple-xros1.0 sptest.metal -o $L/a-xros1.metallib
else
  xcrun -sdk iphoneos metal -target air64-apple-ios16.0 sptest.metal -o $L/a-ios16.metallib
fi
xcrun -sdk $SP_SDK metal -target $SP_METAL_TARGET sptest.metal -o $L/a-$SP_SDK$SP_MINOS.metallib
for v in 10.11 10.14 10.15 11.0 12.0 13.0 14.0; do
  xcrun -sdk macosx metal -mmacosx-version-min=$v sptest.metal -o $L/b-mac$v.metallib
  python3 mtlb.py retag $L/b-mac$v.metallib $L/c-mac$v-hdr.metallib
done
cp $L/*.metallib $APP/libs/

xcrun --sdk $SP_SDK clang -target $SP_TARGET -fobjc-arc -O1 -Wall main.m -o $APP/SPMetalTest \
  -framework Foundation -framework Metal
sp_plist Info.plist $APP/Info.plist $BUNDLE_ID
cp "$SP_PROFILE" $APP/embedded.mobileprovision
cat > $OUT/entitlements.plist <<EOT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>application-identifier</key><string>$SP_TEAM.$BUNDLE_ID</string>
  <key>com.apple.developer.team-identifier</key><string>$SP_TEAM</string>
  <key>get-task-allow</key><true/>
</dict></plist>
EOT
codesign -f -s "$SP_SIGN_ID" --entitlements $OUT/entitlements.plist $APP
sp_need_device
xcrun devicectl device install app --device "$SP_DEVICE" $APP
