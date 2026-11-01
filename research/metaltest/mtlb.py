#!/usr/bin/env python3
"""Dumps and retags .metallib files (our own test shader only).

  mtlb.py dump FILE
  mtlb.py retag IN OUT

Layout (MTLB container, as observed in metal 32023 output):
  0x00 'MTLB'  0x04 u16 target (bit 15 = macOS)  0x06 u16 ver major  0x08 u16 ver minor
  0x0a u8 lib type  0x0b u8 platform (0x80 | id; 1 = macOS, 11 = visionOS; 0 before v2.6)
  0x0c platform version (major in the low byte)
  0x10 u64 file size, then (offset, size) u64 pairs: function list, public md, private md, bitcode.
Function list: u32 count, then per function u32 entry size + tagged fields (NAME, TYPE, HASH,
MDSZ, OFFT, VERS, ... ENDT). HASH is the SHA-256 of that function's bitcode module.
"""
import hashlib, struct, sys

def u16(b, o): return struct.unpack_from('<H', b, o)[0]
def u32(b, o): return struct.unpack_from('<I', b, o)[0]
def u64(b, o): return struct.unpack_from('<Q', b, o)[0]

def header(b):
    h = dict(target=u16(b, 4), major=u16(b, 6), minor=u16(b, 8), libtype=b[10], platform=b[11],
             pver=b[12:16].hex(), size=u64(b, 16))
    names = ['funcs', 'pubmd', 'privmd', 'bitcode']
    for i, n in enumerate(names):
        h[n] = (u64(b, 0x18 + 16 * i), u64(b, 0x20 + 16 * i))
    return h

def tags(b, o, end):
    while o + 4 <= end:
        t = b[o:o + 4].decode('latin1')
        if t == 'ENDT':
            yield t, o, b''
            return
        n = u16(b, o + 4)
        yield t, o + 6, b[o + 6:o + 6 + n]
        o += 6 + n

def functions(b):
    fo, fs = header(b)['funcs']
    cnt = u32(b, fo)
    o = fo + 4
    for _ in range(cnt):
        sz = u32(b, o)
        yield {t: (off, d) for t, off, d in tags(b, o + 4, o + sz)}
        o += sz

def modules(b):
    """(function fields, bitcode slice start, end) for each function."""
    bo = header(b)['bitcode'][0]
    for f in functions(b):
        off = struct.unpack_from('<3Q', f['OFFT'][1])[2]
        size = u64(f['MDSZ'][1], 0)
        yield f, bo + off, bo + off + size

def triple(mod):
    """The target triple string inside an LLVM bitcode module (wrapper or raw)."""
    for pfx in (b'air64-apple-', b'air64_v'):
        i = mod.find(pfx)
        if i >= 0:
            j = i
            while j < len(mod) and 32 < mod[j] < 127: j += 1
            return i, mod[i:j]
    return -1, b''

def dump(path):
    b = open(path, 'rb').read()
    h = header(b)
    print(path, {k: (hex(v) if isinstance(v, int) else v) for k, v in h.items()})
    for f, s, e in modules(b):
        mod = b[s:e]
        fields = {t: d.hex() if t not in ('NAME',) else d.rstrip(b'\0').decode() for t, (o, d) in f.items()}
        print('  fn', fields)
        print('    bitcode', hex(s), e - s, 'magic', mod[:4].hex(), 'sha256 ok' if hashlib.sha256(mod).digest() == f['HASH'][1] else 'sha256 MISMATCH')
        print('    triple-ish string', triple(mod))
    # Anything after the function list up to public md (header extension tags).
    fo, fs = h['funcs']
    ext = fo + fs
    if ext < h['pubmd'][0]:
        print('  ext', [(t, d.hex()) for t, o, d in tags(b, ext + 4, h['pubmd'][0])])

def retag_header(b):
    """Clears the macOS flag (bit 15 of the target field). That is all visionOS needs: it rejects
    only containers that have the flag and predate the platform field (v2.2-2.5)."""
    b = bytearray(b)
    struct.pack_into('<H', b, 4, u16(b, 4) & 0x7fff)
    return bytes(b)

if __name__ == '__main__':
    if sys.argv[1] == 'dump':
        for p in sys.argv[2:]: dump(p)
    elif sys.argv[1] == 'retag':
        b = open(sys.argv[2], 'rb').read()
        open(sys.argv[3], 'wb').write(retag_header(b))
