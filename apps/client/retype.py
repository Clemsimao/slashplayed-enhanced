#!/usr/bin/env python3
"""Makes a thinned arm64 executable dlopen-able for the flavor launcher (launcher.m): retypes its header
MH_EXECUTE -> MH_BUNDLE (dyld refuses to dlopen an executable) and zeroes the file offset of zero-fill
sections (dyld rejects a non-main image whose zero-fill section has one, e.g. the client's
__DATA,__thread_bss). Only the header and section headers change.

Usage: retype.py <binary>
"""
import struct
import sys

MH_MAGIC_64, MH_EXECUTE, MH_BUNDLE, LC_SEGMENT_64 = 0xFEEDFACF, 2, 8, 0x19
ZEROFILL_TYPES = {0x1, 0xC, 0x12}  # S_ZEROFILL, S_GB_ZEROFILL, S_THREAD_LOCAL_ZEROFILL

path = sys.argv[1]
d = bytearray(open(path, "rb").read())
magic, _, _, filetype, ncmds = struct.unpack_from("<IiiII", d, 0)
assert magic == MH_MAGIC_64 and filetype == MH_EXECUTE, "not a thin 64-bit executable"
struct.pack_into("<I", d, 12, MH_BUNDLE)
off = 32
for _ in range(ncmds):
    cmd, size = struct.unpack_from("<II", d, off)
    if cmd == LC_SEGMENT_64:
        nsects = struct.unpack_from("<I", d, off + 64)[0]
        for i in range(nsects):
            s = off + 72 + i * 80
            name = d[s:s + 16].rstrip(b"\0").decode("latin-1") + "," + d[s + 16:s + 32].rstrip(b"\0").decode("latin-1")
            offset, flags = struct.unpack_from("<I", d, s + 48)[0], struct.unpack_from("<I", d, s + 64)[0]
            if flags & 0xFF in ZEROFILL_TYPES and offset:
                print(f"{name}: zero-fill offset {offset:#x} -> 0", file=sys.stderr)
                struct.pack_into("<I", d, s + 48, 0)
    off += size
open(path, "wb").write(d)
