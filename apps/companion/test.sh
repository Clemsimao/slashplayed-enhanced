#!/bin/sh
# Runs the companion's unit tests (apps/companion/Tests; needs xcodegen). Extra arguments go to
# xcodebuild, e.g. -only-testing:SPCompanionTests/ClientAssemblyTests.
set -e
cd "$(dirname "$0")"
OUT=$(cd ../.. && pwd)/build/companion-tests
./idevice-config.sh
# The launcher's signer (spsign.m) is tested on the Mac, linked with zsign and OpenSSL built for it.
[ -f ../../work/zsign/macos/libzsign.a ] && [ -f ../../work/zsign/macos/openssl/lib/libcrypto.a ] ||
  { echo "test.sh: no work/zsign/macos/libzsign.a or its libcrypto.a (run scripts/build-zsign.sh macos)" >&2; exit 1; }
xcodegen generate --quiet
xcodebuild -project SPCompanion.xcodeproj -scheme SPCompanion -derivedDataPath "$OUT" -quiet test "$@"
