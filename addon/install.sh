#!/bin/sh
# Copies the SPHover addon into the headset client's install root (Documents/_classic_era_ or the
# flavor's folder, see apps/client/seed.sh and scripts/flavor.sh), where the client looks for
# Interface/AddOns. The TOC lists every flavor's Interface number (apps/client/flavors.plist), so it's
# copied as it is. Survives reinstalls. The device is SP_PLATFORM's (scripts/platform.sh, scripts/config.sh).
set -e
cd "$(dirname "$0")"
. ../scripts/flavor.sh
. ../scripts/platform.sh
sp_need SP_BUNDLE_ID
sp_need_device
for f in SPHover/SPHover.toc SPHover/SPHover.lua; do
  xcrun devicectl device copy to --device "$SP_DEVICE" --domain-type appDataContainer \
    --domain-identifier "$SP_BUNDLE_ID" --source "$f" \
    --destination "Documents/$SP_FLAVOR_DIR/Interface/AddOns/$f" >/dev/null
  echo "copied $f"
done
