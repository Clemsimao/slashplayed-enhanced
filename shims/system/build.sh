#!/bin/sh
# Builds libspSystem.dylib + libspdl.dylib: ./build.sh <xros|ios|macos> <out-dir> [install-name prefix]
# The prefix defaults to @rpath/ (the app bundle's Frameworks/); the Mac test uses @executable_path/.
set -e
PLATFORM=$1
mkdir -p "$2"
OUT=$(cd "$2" && pwd)
cd "$(dirname "$0")"
PREFIX=${3:-@rpath/}
case $PLATFORM in
  xros) CC="xcrun --sdk xros clang -target arm64-apple-xros27.0" ;;
  ios) CC="xcrun --sdk iphoneos clang -target arm64-apple-ios26.0" ;;
  macos) CC="clang -arch arm64 -mmacosx-version-min=11.0" ;;
  *) echo "usage: $0 <xros|ios|macos> <out-dir> [install-name prefix]" >&2; exit 1 ;;
esac
$CC -dynamiclib -O1 -Wall spdl.c -o "$OUT/libspdl.dylib" -install_name "${PREFIX}libspdl.dylib"
$CC -dynamiclib -O1 -Wall spsystem.c -o "$OUT/libspSystem.dylib" -install_name "${PREFIX}libspSystem.dylib" \
  -Wl,-reexport-lSystem.B "$OUT/libspdl.dylib"
