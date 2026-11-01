#!/bin/sh
# Runs SPMetalTest on the device (SP_PLATFORM picks it) (exits in a few seconds) and prints its log.
cd "$(dirname "$0")"
. ../../scripts/platform.sh
sp_need_device
xcrun devicectl device process launch --device "$SP_DEVICE" --terminate-existing --console \
  com.strawdynamics.spmetaltest 2>&1 | grep -v '^$'
