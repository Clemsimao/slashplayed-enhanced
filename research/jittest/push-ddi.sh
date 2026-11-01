#!/bin/bash
# Copies the developer disk image's cryptex from this Mac's Xcode into SPJitTest's data container
# (Documents/DDI), so the helper can mount it on the device itself after a reboot (h3, h4), with no Mac.
#
#   SP_PLATFORM=ios research/jittest/push-ddi.sh       (SP_DEVICE picks the device; SP_DDI_FORCE=1 recopies)
#
# These are Apple's files, from the user's own Xcode to the user's own device: never into the repo, CI, or a
# release. Only the cryptex the device mounts is copied (BuildManifest.plist and the four Cryptex1 payloads
# its "Developer Disk Image Cryptex" identity names, ~17 MB for iOS, ~13 MB for visionOS), not the
# personalized image for OS versions before 26.4. That identity is chip-independent (one per platform, no
# ApChipID), which is why the xrOS image can be personalized for the headset like the iOS one for an iPhone.
#
# The image's version is Xcode's, not the device OS's: one image serves every OS version that Xcode
# supports (Xcode 27.1's mounts on iPadOS 26.6 and iOS 27.0.1 alike). It's recopied when Xcode updates it:
# Documents/DDI/version.txt holds the Xcode build and image build it came from, and is written last, so an
# interrupted copy doesn't look complete.
set -euo pipefail
cd "$(dirname "$0")"
. ../../scripts/platform.sh
# SP_PUSH_TO names another test app with the same helper (research/dlopentest).
BUNDLE_ID=${SP_PUSH_TO:-com.strawdynamics.spjittest}
die() { echo "push-ddi: $*" >&2; exit 1; }

case $SP_PLATFORM in
  ios) SRC=/Library/Developer/DeveloperDiskImages/iOS_DDI ;;
  xros) SRC=/Library/Developer/DeveloperDiskImages/xrOS_DDI ;;
esac
[ -f "$SRC/Restore/BuildManifest.plist" ] && [ -f "$SRC/version.plist" ] ||
  die "no developer disk image at $SRC: install Xcode's $SP_PLATFORM platform support (Xcode > Settings > Components)"
version="Xcode $(plutil -extract ProductBuildVersion raw "$SRC/version.plist"), image $(plutil -extract BuildVersion raw "$SRC/version.plist")"

# The files the cryptex identity names, relative to Restore/ (as idevice's cryptex1_assets_load reads them).
files=$(python3 -I - "$SRC/Restore/BuildManifest.plist" <<'EOF'
import plistlib, sys
manifest = plistlib.load(open(sys.argv[1], "rb"))
ids = [i for i in manifest["BuildIdentities"] if i["Info"]["Variant"].endswith("Developer Disk Image Cryptex")]
if len(ids) != 1:
    sys.exit(f"expected one Developer Disk Image Cryptex identity, found {len(ids)}")
print("BuildManifest.plist")
for key in ["Cryptex1,GenericDmg", "Cryptex1,GenericTrustCache", "Cryptex1,CryptexInfoPlist", "Cryptex1,GenericVolume"]:
    print(ids[0]["Manifest"][key]["Info"]["Path"])
EOF
) || die "couldn't read the cryptex's files from $SRC/Restore/BuildManifest.plist"
for f in $files; do [ -f "$SRC/Restore/$f" ] || die "$SRC/Restore/$f is missing"; done

sp_need_device
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
copy_to() {
  xcrun devicectl device copy to --device "$SP_DEVICE" --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" --source "$1" --destination "$2" >/dev/null ||
    die "devicectl couldn't copy $1 to $2 (is SPJitTest installed? research/jittest/build.sh)"
}
if [ -z "${SP_DDI_FORCE:-}" ] && xcrun devicectl device copy from --device "$SP_DEVICE" --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" --source Documents/DDI/version.txt --destination "$tmp/have.txt" >/dev/null 2>&1 &&
    [ "$(cat "$tmp/have.txt")" = "$version" ]; then
  echo "the device already has this image ($version)"
  exit 0
fi
for f in $files; do
  echo "copying $f ($(stat -f %z "$SRC/Restore/$f") bytes)"
  copy_to "$SRC/Restore/$f" "Documents/DDI/Restore/$f"
done
echo "$files" > "$tmp/files.txt"
copy_to "$tmp/files.txt" Documents/DDI/files.txt
echo "$version" > "$tmp/version.txt"
copy_to "$tmp/version.txt" Documents/DDI/version.txt
echo "copied the developer disk image ($version) to $BUNDLE_ID's Documents/DDI"
