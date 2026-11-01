#!/bin/sh
# End-to-end Mac test of the real shim on the real client: a thinned, ad-hoc-signed copy (no hardened
# runtime) whose libSystem load command points at libspSystem, spawned suspended with lldb + jit.py
# servicing brk #0xf00d (spawn-mac.py). Everything goes in work/shimtest-mac/ (Blizzard's binary: never commit).
# The client runs offline with no game data, so it should rewrite its code, start up and exit 255.
# Usage: ./test-mac.sh [jit.py mode, default bulkz]
set -e
cd "$(dirname "$0")"
. ../../scripts/flavor.sh
SRC=$SP_CLIENT
ROOT=$(cd ../.. && pwd)/work/shimtest-mac
BIN=$ROOT/bin
rm -rf $BIN && mkdir -p $BIN
./build.sh macos $BIN @executable_path/
lipo -thin arm64 "$SRC" -output $BIN/wow
install_name_tool -change /usr/lib/libSystem.B.dylib @executable_path/libspSystem.dylib $BIN/wow 2>/dev/null
codesign -f -s - $BIN/libspdl.dylib $BIN/libspSystem.dylib $BIN/wow
SP_SYSTEM_CHECKSUM=1 ./spawn-mac.py "${1:-bulkz}" $ROOT/stdout.txt $ROOT/stderr.txt $BIN/wow || echo "exit $?"
grep -v '^20' $ROOT/stderr.txt
