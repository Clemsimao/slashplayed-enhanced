#!/bin/sh
# Makes Xcode register a device and (re)write a development profile, "iOS Team Provisioning Profile:
# <bundle id>", for each app the build scripts install. The profiles cover iOS and visionOS and every
# registered device; the build scripts find them by bundle id (sp_profile in scripts/platform.sh).
# Run with the device connected, unlocked and in Developer Mode:
#   ./regen.sh <device UDID>
# The team (SP_TEAM) and the client's bundle ID (SP_BUNDLE_ID) come from config/local.env
# (scripts/config.sh).
# Xcode replaces a profile with a new file (new UUID) when it adds a device.
set -e
cd "$(dirname "$0")"
[ -n "$1" ] || { echo "usage: $0 <device UDID>" >&2; exit 1; }
. ../../../scripts/platform.sh
sp_need SP_TEAM SP_BUNDLE_ID
xcodegen generate --quiet
# The JIT helper extension (apps/client/helper), in the client, jittest, and dlopentest, needs a profile of its own:
# the team wildcard profile predates devices registered since, and an extension's App ID is its own bundle ID.
IDS="$SP_BUNDLE_ID $SP_BUNDLE_ID.helper com.strawdynamics.sploader com.strawdynamics.spjittest com.strawdynamics.spjittest.helper
  com.strawdynamics.spmetaltest com.strawdynamics.spdlopentest com.strawdynamics.spdlopentest.helper"
# The client gets the memory entitlements (project.yml); the test apps get none.
for id in $IDS; do
  extra=
  [ $id = $SP_BUNDLE_ID ] || extra="CODE_SIGN_ENTITLEMENTS="
  echo "$id"
  xcodebuild -project SPProfiles.xcodeproj -scheme SPProfiles -destination "id=$1" \
    -derivedDataPath ../../../work/signing -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM=$SP_TEAM PRODUCT_BUNDLE_IDENTIFIER=$id $extra build 2>&1 | grep -E ' error: |^\*\* ' || true
done
for id in $IDS; do
  p=$(sp_profile $id)
  security cms -D -i "$p" 2>/dev/null | grep -q "$1" && has=yes || has=no
  echo "$id: $(basename "$p") device=$has"
done
