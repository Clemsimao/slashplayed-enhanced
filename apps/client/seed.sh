#!/bin/sh
# Puts the installed game's files in the app's Documents/, laid out like the Mac install root, which
# the libSystem shim maps the client's install root onto (see shims/system/spsystem.c):
#   Documents/.build.info, Documents/Data/                         (the Mac's World of Warcraft/)
#   Documents/_classic_era_/.flavor.info, _classic_era_/WTF/Config.wtf  (the Mac's _classic_era_/)
# (or the flavor's own folder, scripts/flavor.sh). The flavors share Data/: it holds all of them.
# Config.wtf gets the region and locale the Battle.net launcher would set (portal "us", enUS), and
# is only written if the device doesn't have one yet; so is Library/spidentity, the small identity file
# login needs from the Mac (shims/ident/mac-identity.c; without it the device's login fails). Data/ (7.4 GB with Anniversary) is only
# copied with --data. The app's data container survives reinstalls, so this is needed once.
# SP_DATA_PRODUCTS (e.g. "wow_classic_era wow_anniversary") limits --data to the archives those
# products' builds use (casc_archives.py), for a device without room for the whole store (~150 GB
# with every game): every other file in Data/ is copied, but only those data.NNN archives.
set -e
cd "$(dirname "$0")"
. ../../scripts/platform.sh
. ../../scripts/flavor.sh
INSTALL=$SP_INSTALL
F=$SP_FLAVOR_DIR
OUT=../../work/clienttest-seed$SP_SUFFIX
sp_need SP_BUNDLE_ID
sp_need_device
BUNDLE_ID=$SP_BUNDLE_ID

copy() {
  xcrun devicectl device copy to --device "$SP_DEVICE" --domain-type appDataContainer \
    --domain-identifier $BUNDLE_ID --source "$1" --destination "$2" >/dev/null
  echo "copied $1 -> $2"
}

rm -rf $OUT && mkdir -p $OUT
if [ "$1" = --data ] && [ -n "$SP_DATA_PRODUCTS" ]; then
  # Stage the subset as APFS clones (no extra disk), then copy it in one go.
  STAGE=$OUT/Data
  rm -rf $STAGE && mkdir -p $STAGE/data
  for f in "$INSTALL/Data"/*; do [ "$(basename "$f")" = data ] || cp -cR "$f" $STAGE/; done
  for f in "$INSTALL/Data/data"/*; do case $(basename "$f") in data.[0-9]*) ;; *) cp -c "$f" $STAGE/data/ ;; esac; done
  for a in $(python3 casc_archives.py "$INSTALL" $SP_DATA_PRODUCTS); do
    cp -c "$INSTALL/Data/data/$(printf 'data.%03d' $a)" $STAGE/data/
  done
  echo "staged $(du -sh $STAGE | cut -f1) of Data/ for $SP_DATA_PRODUCTS"
  copy $STAGE Documents/Data
elif [ "$1" = --data ]; then
  copy "$INSTALL/Data" Documents/Data
fi
copy "$INSTALL/.build.info" Documents/.build.info
copy "$INSTALL/$F/.flavor.info" Documents/$F/.flavor.info
xcrun devicectl device info files --device "$SP_DEVICE" --domain-type appDataContainer \
  --domain-identifier $BUNDLE_ID --subdirectory Documents --recurse --json-output $OUT/files.json >/dev/null
if python3 -c 'import json,sys
sys.exit(not any(f["relativePath"] == sys.argv[2] + "/WTF/Config.wtf" for f in json.load(open(sys.argv[1]))["result"]["files"]))' \
  $OUT/files.json $F; then
  echo "Config.wtf already on device, left alone"
else
  printf 'SET portal "us"\nSET textLocale "enUS"\nSET audioLocale "enUS"\n' > $OUT/Config.wtf
  copy $OUT/Config.wtf Documents/$F/WTF/Config.wtf
fi
xcrun devicectl device info files --device "$SP_DEVICE" --domain-type appDataContainer \
  --domain-identifier $BUNDLE_ID --subdirectory Library --json-output $OUT/library.json >/dev/null
if python3 -c 'import json,sys
sys.exit(not any(f["relativePath"] == "spidentity" for f in json.load(open(sys.argv[1]))["result"]["files"]))' \
  $OUT/library.json; then
  echo "spidentity already on device, left alone"
else
  xcrun clang -o $OUT/mac-identity ../../shims/ident/mac-identity.c
  $OUT/mac-identity $OUT/spidentity
  copy $OUT/spidentity Library/spidentity
fi
