// Assembly on the device: the steps the Mac runs with install_name_tool, vtool and retype.py, ported, so
// an on-device update can make the client image from a newer build's arm64 slice (sppatch.m keeps it in
// Library/spslice/). Three producers make the same unsigned image from the same slice: this,
// ClientAssembly.prepareClient, and apps/client/build.sh; the companion's tests check that byte for byte.
// What the tools do was read from their output (Xcode 27's cctools), not their source:
// - install_name_tool -change rewrites a dylib load command (LC_LOAD_DYLIB and its kin) whose name is the
//   map's <from>, in place in the command list: the name at offset 24, the command's other fields kept,
//   zero padding to a multiple of 8. -add_rpath appends an LC_RPATH, padded the same way, at the end.
// - vtool -set-build-version ... -replace removes every build version (LC_BUILD_VERSION and the older
//   LC_VERSION_MIN_*) and appends one LC_BUILD_VERSION, with no tools and the SDK as given (we give the
//   minimum OS twice), at the end.
// - Each writes the new commands after the header and zeroes what's left of the old ones' space; nothing
//   past that changes. A slice signed for real (a shipped client's Developer ID signature) keeps its
//   LC_CODE_SIGNATURE and signature bytes untouched, stale. A linker-only ad hoc signature (what ld
//   writes on arm64) the tools re-sign, renaming its identifier after the output file: this refuses one.
#import "spassemble.h"
#include <mach-o/loader.h>

static uint32_t u32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }

static uint32_t be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }

static void put32(uint8_t *p, uint32_t v) {
    for (int k = 0; k < 4; k++) p[k] = (uint8_t)(v >> (8 * k));
}

static BOOL fits(NSUInteger n, uint64_t off, uint64_t len) { return off <= n && len <= n - off; }

static BOOL fail(NSString **problem, NSString *why) {
    if (problem) *problem = why;
    return NO;
}

static NSData *refuse(NSString **problem, NSString *why) {
    fail(problem, why);
    return nil;
}

// The image's load commands, each its own bytes, in order. NO when one runs past sizeofcmds or the file.
static BOOL commands(NSData *d, NSMutableArray<NSData *> *out, NSString **problem) {
    const uint8_t *p = d.bytes;
    uint32_t ncmds = u32(p + 16), sizeofcmds = u32(p + 20);
    if (!fits(d.length, 32, sizeofcmds)) return fail(problem, @"its load commands run past the end of the file");
    uint64_t off = 32, end = 32 + (uint64_t)sizeofcmds;
    for (uint32_t i = 0; i < ncmds; i++) {
        if (off + 8 > end) return fail(problem, @"a load command runs past the load commands' size");
        uint32_t size = u32(p + off + 4);
        if (size < 8 || size % 4 || off + size > end) return fail(problem, @"a load command has a bad size");
        [out addObject:[d subdataWithRange:NSMakeRange((NSUInteger)off, size)]];
        off += size;
    }
    return YES;
}

static BOOL is_dylib_load(uint32_t cmd) {
    return cmd == LC_LOAD_DYLIB || cmd == LC_LOAD_WEAK_DYLIB || cmd == LC_REEXPORT_DYLIB || cmd == LC_LAZY_LOAD_DYLIB
        || cmd == LC_LOAD_UPWARD_DYLIB;
}

static BOOL is_build_version(uint32_t cmd) {
    return cmd == LC_BUILD_VERSION || cmd == LC_VERSION_MIN_MACOSX || cmd == LC_VERSION_MIN_IPHONEOS
        || cmd == LC_VERSION_MIN_TVOS || cmd == LC_VERSION_MIN_WATCHOS;
}

// A load command's string at its lc_str offset (`at` in the command), or nil if it isn't NUL-terminated
// inside the command.
static NSString *command_string(NSData *c, uint32_t at) {
    const uint8_t *p = c.bytes;
    uint32_t off = u32(p + at);
    if (off >= c.length) return nil;
    const uint8_t *nul = memchr(p + off, 0, c.length - off);
    return nul ? [[NSString alloc] initWithBytes:p + off length:nul - (p + off) encoding:NSUTF8StringEncoding] : nil;
}

// A command of `head` (its fixed part, cmdsize and the lc_str offset filled in here) with `string` after
// it, NUL-terminated and zero-padded to a multiple of 8, as the tools write them for a 64-bit image.
static NSData *command_with_string(NSData *head, uint32_t strAt, NSString *string) {
    NSData *s = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger size = (head.length + s.length + 1 + 7) & ~(NSUInteger)7;
    NSMutableData *c = [NSMutableData dataWithLength:size];
    uint8_t *p = c.mutableBytes;
    memcpy(p, head.bytes, head.length);
    put32(p + 4, (uint32_t)size);
    put32(p + strAt, (uint32_t)head.length);
    memcpy(p + head.length, s.bytes, s.length);
    return c;
}

// The lowest file offset of any section's contents: the load commands have to end before it (both tools
// refuse otherwise, asking for a relink with more header padding).
static uint64_t first_section_offset(NSArray<NSData *> *cmds, uint64_t fileSize) {
    uint64_t lowest = fileSize;
    for (NSData *c in cmds) {
        const uint8_t *p = c.bytes;
        if (u32(p) != LC_SEGMENT_64 || c.length < sizeof(struct segment_command_64)) continue;
        uint32_t nsects = u32(p + 64);
        for (uint32_t i = 0; i < nsects && 72 + (i + 1) * 80 <= c.length; i++) {
            const uint8_t *s = p + 72 + i * 80;
            uint64_t size = u32(s + 40) | (uint64_t)u32(s + 44) << 32;
            uint32_t offset = u32(s + 48), type = u32(s + 64) & SECTION_TYPE;
            BOOL zerofill = type == S_ZEROFILL || type == S_GB_ZEROFILL || type == S_THREAD_LOCAL_ZEROFILL;
            if (!zerofill && size && offset && offset < lowest) lowest = offset;
        }
    }
    return lowest;
}

// One tool's write: `cmds` after the header (ncmds, sizeofcmds updated), then zeros up to where the old
// commands ended. NO and *problem when they don't fit before the first section.
static BOOL write_commands(NSMutableData *d, NSArray<NSData *> *cmds, NSString *tool, NSString **problem) {
    uint8_t *p = d.mutableBytes;
    uint32_t oldSize = u32(p + 20);
    NSUInteger size = 0;
    for (NSData *c in cmds) size += c.length;
    if (32 + size > first_section_offset(cmds, d.length))
        return fail(problem, [NSString stringWithFormat:@"%@'s load commands don't fit in the header's space", tool]);
    NSUInteger at = 32;
    for (NSData *c in cmds) {
        memcpy(p + at, c.bytes, c.length);
        at += c.length;
    }
    if (32 + (NSUInteger)oldSize > at) memset(p + at, 0, 32 + oldSize - at);
    put32(p + 16, (uint32_t)cmds.count);
    put32(p + 20, (uint32_t)size);
    return YES;
}

// Whether the image's code signature is only the linker's (its code directory's CS_LINKER_SIGNED). A
// signature that can't be read counts as not.
static BOOL linker_signed(NSData *d, NSArray<NSData *> *cmds) {
    const uint8_t *p = d.bytes;
    for (NSData *c in cmds) {
        const uint8_t *q = c.bytes;
        if (u32(q) != LC_CODE_SIGNATURE || c.length < 16) continue;
        uint32_t off = u32(q + 8), size = u32(q + 12);
        if (size < 12 || !fits(d.length, off, size) || be32(p + off) != 0xFADE0CC0) return NO;  // CSMAGIC_EMBEDDED_SIGNATURE
        uint32_t count = be32(p + off + 8);
        for (uint32_t i = 0; i < count && 12 + (uint64_t)(i + 1) * 8 <= size; i++) {
            uint32_t type = be32(p + off + 12 + i * 8), at = be32(p + off + 16 + i * 8);
            if (type != 0 || (uint64_t)at + 16 > size) continue;  // CSSLOT_CODEDIRECTORY
            const uint8_t *cd = p + off + at;
            return be32(cd) == 0xFADE0C02 && (be32(cd + 12) & 0x20000);  // CSMAGIC_CODEDIRECTORY, CS_LINKER_SIGNED
        }
    }
    return NO;
}

// rewrite-map.txt: "<from> -> <to>" per line, as ClientAssembly.rewriteMap reads it.
static NSArray<NSArray<NSString *> *> *parse_map(NSString *text, NSString **problem) {
    NSMutableArray *map = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (!line.length) continue;
        NSArray<NSString *> *parts = [line componentsSeparatedByString:@" -> "];
        if (parts.count != 2 || !parts[0].length || !parts[1].length) {
            fail(problem, [NSString stringWithFormat:@"the rewrite map has a line that isn't \"<from> -> <to>\": %@", line]);
            return nil;
        }
        [map addObject:parts];
    }
    return map;
}

NSData *sp_assemble(NSData *slice, NSString *rewriteMap, uint32_t platform, uint32_t minOS, NSArray<NSString *> **changes,
                    NSString **problem) {
    if (changes) *changes = @[];
    const uint8_t *in = slice.bytes;
    if (slice.length < 32 || u32(in) != MH_MAGIC_64) return refuse(problem, @"not a thin 64-bit Mach-O");
    if (u32(in + 12) != MH_EXECUTE) return refuse(problem, @"not an executable, so it can't be retyped");
    NSArray<NSArray<NSString *> *> *map = parse_map(rewriteMap, problem);
    if (!map) return nil;
    NSMutableArray<NSData *> *cmds = [NSMutableArray array];
    if (!commands(slice, cmds, problem)) return nil;
    if (linker_signed(slice, cmds))
        return refuse(problem, @"its code signature is only the linker's, which the Mac's tools re-sign and this doesn't");
    NSMutableData *d = [slice mutableCopy];

    // install_name_tool: each -change in place, the first map entry naming the library; then -add_rpath.
    NSString *rpath = @"@executable_path/Frameworks";
    for (NSUInteger i = 0; i < cmds.count; i++) {
        uint32_t cmd = u32(cmds[i].bytes);
        if (cmd == LC_RPATH && [command_string(cmds[i], 8) isEqual:rpath])
            return refuse(problem, @"it already has the Frameworks rpath (install_name_tool refuses a duplicate)");
        if (!is_dylib_load(cmd) || cmds[i].length < sizeof(struct dylib_command)) continue;
        NSString *name = command_string(cmds[i], 8);
        if (!name) return refuse(problem, @"a library's load command has no name");
        for (NSArray<NSString *> *e in map) {
            if (![e[0] isEqual:name]) continue;
            cmds[i] = command_with_string([cmds[i] subdataWithRange:NSMakeRange(0, sizeof(struct dylib_command))], 8, e[1]);
            break;
        }
    }
    uint8_t rp[sizeof(struct rpath_command)] = {0};
    put32(rp, LC_RPATH);
    [cmds addObject:command_with_string([NSData dataWithBytes:rp length:sizeof rp], 8, rpath)];
    if (!write_commands(d, cmds, @"install_name_tool", problem)) return nil;

    // vtool: every build version out, the new one at the end (no tools; the SDK is the minimum OS).
    [cmds filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSData *c, id _) { return !is_build_version(u32(c.bytes)); }]];
    uint8_t bv[sizeof(struct build_version_command)] = {0};
    put32(bv, LC_BUILD_VERSION);
    put32(bv + 4, sizeof bv);
    put32(bv + 8, platform);
    put32(bv + 12, minOS);
    put32(bv + 16, minOS);
    [cmds addObject:[NSData dataWithBytes:bv length:sizeof bv]];
    if (!write_commands(d, cmds, @"vtool", problem)) return nil;

    // The retype (retype.py): MH_BUNDLE, and no file offset on a zero-fill section.
    uint8_t *p = d.mutableBytes;
    put32(p + 12, MH_BUNDLE);
    NSMutableArray<NSString *> *changed = [NSMutableArray array];
    uint64_t off = 32;
    for (NSData *c in cmds) {
        if (u32(c.bytes) == LC_SEGMENT_64 && c.length >= sizeof(struct segment_command_64)) {
            uint32_t nsects = u32(p + off + 64);
            for (uint32_t i = 0; i < nsects && 72 + (i + 1) * 80 <= c.length; i++) {
                uint8_t *s = p + off + 72 + i * 80;
                uint32_t offset = u32(s + 48), type = u32(s + 64) & 0xFF;
                if ((type == S_ZEROFILL || type == S_GB_ZEROFILL || type == S_THREAD_LOCAL_ZEROFILL) && offset) {
                    [changed addObject:[NSString stringWithFormat:@"%.16s,%.16s: zero-fill offset 0x%x -> 0", (const char *)s,
                                                                  (const char *)s + 16, offset]];
                    put32(s + 48, 0);
                }
            }
        }
        off += c.length;
    }
    if (changes) *changes = changed;
    return d;
}
