#!/bin/bash
# Copies the RemotePairing record that StikDebug already holds into SPJitTest's data container
# (Documents/pairingFile.plist), for testing the helper (h2-h4) before the companion makes its own.
#
#   SP_PLATFORM=ios research/jittest/push-pairing.sh    (SP_DEVICE picks the device)
#
# The record is a credential that can do anything this Mac's pairing can (revoked with Settings >
# Developer > Clear Trusted Computers, which unpairs the Mac too). So it's never read, printed, or logged
# here: devicectl copies it from StikDebug's container to a private directory on the Mac and from there to
# SPJitTest's, only its size is shown, and the Mac's copy is overwritten and deleted (rm -P) on exit.
# SP_STIKDEBUG_BUNDLE_ID names StikDebug's app if it isn't the one this repo's notes use, and
# SP_STIKDEBUG_PAIRING the record's path in its container if it isn't Documents/pairingFile.plist (the
# build on the Vision Pro keeps it at "Library/Application Support/Pairing/pairingFile.plist").
set -euo pipefail
cd "$(dirname "$0")"
. ../../scripts/platform.sh
# SP_PUSH_TO names another test app with the same helper (research/dlopentest).
BUNDLE_ID=${SP_PUSH_TO:-com.strawdynamics.spjittest}
FROM=${SP_STIKDEBUG_BUNDLE_ID:-com.strawdynamics.slashplayed.stikdebug}
SOURCE=${SP_STIKDEBUG_PAIRING:-Documents/pairingFile.plist}
die() { echo "push-pairing: $*" >&2; exit 1; }

sp_need_device
tmp=$(mktemp -d)
chmod 700 "$tmp"
trap '[ -f "$tmp/pairingFile.plist" ] && rm -P "$tmp/pairingFile.plist"; rm -rf "$tmp"' EXIT
xcrun devicectl device copy from --device "$SP_DEVICE" --domain-type appDataContainer --domain-identifier "$FROM" \
  --source "$SOURCE" --destination "$tmp/pairingFile.plist" >/dev/null ||
  die "couldn't copy $SOURCE from $FROM (set SP_STIKDEBUG_BUNDLE_ID or SP_STIKDEBUG_PAIRING if they differ)"
echo "pairing record: $(stat -f %z "$tmp/pairingFile.plist") bytes"
xcrun devicectl device copy to --device "$SP_DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
  --source "$tmp/pairingFile.plist" --destination Documents/pairingFile.plist >/dev/null ||
  die "couldn't copy it into $BUNDLE_ID (is SPJitTest installed? research/jittest/build.sh)"
echo "copied to $BUNDLE_ID's Documents/pairingFile.plist; the Mac's copy is deleted"
