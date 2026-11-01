#!/bin/sh
# Mac identity probe: ./build-mac.sh <out-dir>. Builds libspIOKit.dylib, libspDiskArbitration.dylib,
# libspCoreFoundation.dylib and libspFoundation.dylib (@executable_path/, re-exporting the real
# frameworks with spiokit.c / spdiskarb.c / spcf.c / spfoundation.m on top) for a copy of the Mac
# reference client whose IOKit, DiskArbitration, CoreFoundation and Foundation load commands point at them.
set -e
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
cd "$(dirname "$0")"
CC="clang -arch arm64 -mmacosx-version-min=11.0 -dynamiclib -O1 -Wall -include mac-prelude.h -framework CoreFoundation"
$CC spiokit.c -o "$OUT/libspIOKit.dylib" -install_name @executable_path/libspIOKit.dylib \
  -Wl,-reexport_framework,IOKit
$CC spdiskarb.c -o "$OUT/libspDiskArbitration.dylib" -install_name @executable_path/libspDiskArbitration.dylib \
  -Wl,-reexport_framework,DiskArbitration
$CC spcf.c -o "$OUT/libspCoreFoundation.dylib" -install_name @executable_path/libspCoreFoundation.dylib \
  -Wl,-reexport_framework,CoreFoundation
$CC -fobjc-arc spfoundation.m -o "$OUT/libspFoundation.dylib" -install_name @executable_path/libspFoundation.dylib \
  -Wl,-reexport_framework,Foundation
