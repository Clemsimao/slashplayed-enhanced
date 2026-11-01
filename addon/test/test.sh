#!/bin/sh
# Mac test of the SPHover pixel strip: the addon runs against a mock WoW API, and the shim's decoder
# (shims/appkit/sphoverstrip.h) has to get back the rects the mock UI should produce.
# Needs lua (Homebrew's is 5.4; the addon is written for WoW's 5.1).
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
cc -O1 -Wall -o $OUT/decode decode.c
lua mockwow.lua ../SPHover/SPHover.lua 30 | $OUT/decode
