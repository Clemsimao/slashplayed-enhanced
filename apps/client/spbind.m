// The bind check on the device: does every import of a new client resolve against the shims this app
// carries? The companion's BindCheck.swift answers that on the Mac with `dyld_info -imports`; the device
// has no dyld_info, so this reads the imports from the Mach-O itself. sppatch.m runs it on a newer build's
// arm64 slice (spcdn.m), before it's rewritten, so the imports still name the Mac libraries the bundled
// exports.json is keyed by (shims/exports_manifest.py). The companion's tests check it against BindCheck on
// the overnight run's builds (an opt-in test) and on fixtures of our own, of both fixup kinds.
#import "spbind.h"
#include <mach-o/fixup-chains.h>
#include <mach-o/loader.h>

static NSString *const notImage = @"not a thin 64-bit Mach-O";

// Bounds-checked reads of the image: every offset in it is checked before use.
typedef struct {
    const uint8_t *p;
    size_t n;
} span;

static BOOL fits(span s, uint64_t off, uint64_t len) { return off <= s.n && len <= s.n - off; }

static uint32_t u32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }

static uint64_t u64(const uint8_t *p) { return u32(p) | (uint64_t)u32(p + 4) << 32; }

// A ULEB128 at *at in [*at, end); false when it runs off the end or past 64 bits.
static BOOL uleb(const uint8_t *base, size_t *at, size_t end, uint64_t *out) {
    uint64_t v = 0;
    for (unsigned shift = 0; *at < end; shift += 7) {
        uint8_t b = base[(*at)++];
        if (shift > 63) return NO;
        v |= (uint64_t)(b & 0x7f) << shift;
        if (!(b & 0x80)) {
            *out = v;
            return YES;
        }
    }
    return NO;
}

// The library an ordinal names: 1-based among the dylib load commands, or one of the special ones.
static NSString *library(NSArray<NSString *> *dylibs, int64_t ordinal) {
    if (ordinal > 0) return ordinal <= (int64_t)dylibs.count ? dylibs[ordinal - 1] : @"<bad ordinal>";
    switch (ordinal) {
        case BIND_SPECIAL_DYLIB_SELF: return @"<self>";
        case BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE: return @"<executable>";
        case BIND_SPECIAL_DYLIB_FLAT_LOOKUP: return @"<flat>";
        case BIND_SPECIAL_DYLIB_WEAK_LOOKUP: return @"<weak>";
        default: return @"<bad ordinal>";
    }
}

// Bind opcodes (LC_DYLD_INFO's bind, weak bind, and lazy bind streams): every DO_BIND records the current
// (ordinal, symbol). The lazy stream separates its entries with DONE; the others end at it. The weak bind
// stream binds a weak definition wherever the process has one, so it has no ordinal, and an entry flagged
// NON_WEAK_DEFINITION is the image's own definition, not an import. A weak import (WEAK_IMPORT: the
// library may lack it, and dyld binds it to NULL then) is left out: it can't stop the client loading, and
// BindCheck leaves it out too (dyld_info marks it [weak-import], which its pattern doesn't take).
static BOOL bind_opcodes(span s, uint32_t off, uint32_t size, BOOL lazy, BOOL weak, NSArray<NSString *> *dylibs,
                         void (^add)(NSString *lib, NSString *sym)) {
    if (!size) return YES;
    if (!fits(s, off, size)) return NO;
    const uint8_t *p = s.p;
    size_t at = off, end = (size_t)off + size;
    int64_t ordinal = weak ? BIND_SPECIAL_DYLIB_WEAK_LOOKUP : 0;
    NSString *symbol = nil;
    BOOL strong = NO, weakImport = NO;
    uint64_t skip;
    while (at < end) {
        uint8_t op = p[at] & BIND_OPCODE_MASK, imm = p[at] & BIND_IMMEDIATE_MASK;
        at++;
        switch (op) {
            case BIND_OPCODE_DONE:
                if (!lazy) return YES;
                break;
            case BIND_OPCODE_SET_DYLIB_ORDINAL_IMM: ordinal = imm; break;
            case BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB: {
                uint64_t v;
                if (!uleb(p, &at, end, &v)) return NO;
                ordinal = (int64_t)v;
                break;
            }
            case BIND_OPCODE_SET_DYLIB_SPECIAL_IMM: ordinal = imm ? (int8_t)(BIND_OPCODE_MASK | imm) : 0; break;
            case BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM: {
                const uint8_t *nul = memchr(p + at, 0, end - at);
                if (!nul) return NO;
                symbol = [[NSString alloc] initWithBytes:p + at length:(NSUInteger)(nul - (p + at)) encoding:NSUTF8StringEncoding];
                if (!symbol) return NO;
                strong = (imm & BIND_SYMBOL_FLAGS_NON_WEAK_DEFINITION) != 0;
                weakImport = (imm & BIND_SYMBOL_FLAGS_WEAK_IMPORT) != 0;
                at = (size_t)(nul - p) + 1;
                break;
            }
            case BIND_OPCODE_SET_TYPE_IMM: break;
            case BIND_OPCODE_SET_ADDEND_SLEB:  // an SLEB reads as a ULEB for skipping
            case BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
            case BIND_OPCODE_ADD_ADDR_ULEB:
                if (!uleb(p, &at, end, &skip)) return NO;
                break;
            case BIND_OPCODE_DO_BIND:
            case BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED:
            case BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB:
            case BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB:
                if (op == BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB && !uleb(p, &at, end, &skip)) return NO;
                if (op == BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB &&
                    (!uleb(p, &at, end, &skip) || !uleb(p, &at, end, &skip))) return NO;
                if (!symbol) return NO;
                if (!(weak && strong) && !weakImport) add(library(dylibs, ordinal), symbol);
                break;
            case BIND_OPCODE_THREADED:
                // SET_BIND_ORDINAL_TABLE_SIZE_ULEB has an operand; APPLY doesn't.
                if (imm == BIND_SUBOPCODE_THREADED_SET_BIND_ORDINAL_TABLE_SIZE_ULEB && !uleb(p, &at, end, &skip)) return NO;
                break;
            default: return NO;
        }
    }
    return YES;
}

// LC_DYLD_CHAINED_FIXUPS: its imports table (the binds the chains point into), in one of three formats.
// Weak imports are left out, as above.
static BOOL chained_imports(span s, uint32_t off, uint32_t size, NSArray<NSString *> *dylibs,
                            void (^add)(NSString *lib, NSString *sym)) {
    if (!fits(s, off, size) || size < 28) return NO;
    const uint8_t *h = s.p + off;
    uint32_t importsOffset = u32(h + 8), symbolsOffset = u32(h + 12), count = u32(h + 16), format = u32(h + 20);
    uint32_t entry = format == DYLD_CHAINED_IMPORT ? 4 : format == DYLD_CHAINED_IMPORT_ADDEND ? 8
                   : format == DYLD_CHAINED_IMPORT_ADDEND64 ? 16 : 0;
    if (!entry || !fits((span){h, size}, importsOffset, (uint64_t)count * entry) || symbolsOffset > size) return NO;
    const char *names = (const char *)h + symbolsOffset;
    size_t namesLen = size - symbolsOffset;
    for (uint32_t i = 0; i < count; i++) {
        const uint8_t *e = h + importsOffset + (size_t)i * entry;
        int64_t ordinal;
        uint64_t name;
        BOOL weakImport;
        if (format == DYLD_CHAINED_IMPORT_ADDEND64) {  // lib_ordinal:16, weak_import:1, reserved:15, name_offset:32
            uint64_t v = u64(e);
            ordinal = (v & 0xffff) >= 0xfff0 ? (int16_t)(v & 0xffff) : (int64_t)(v & 0xffff);
            weakImport = (v >> 16) & 1;
            name = v >> 32;
        } else {  // lib_ordinal:8, weak_import:1, name_offset:23
            uint32_t v = u32(e);
            ordinal = (v & 0xff) >= 0xf0 ? (int8_t)(v & 0xff) : (int64_t)(v & 0xff);
            weakImport = (v >> 8) & 1;
            name = v >> 9;
        }
        if (name >= namesLen) return NO;
        const char *nul = memchr(names + name, 0, namesLen - name);
        if (!nul) return NO;
        NSString *symbol = [[NSString alloc] initWithBytes:names + name length:(NSUInteger)(nul - (names + name))
                                                  encoding:NSUTF8StringEncoding];
        if (!symbol) return NO;
        if (!weakImport) add(library(dylibs, ordinal), symbol);
    }
    return YES;
}

NSArray<NSArray<NSString *> *> *sp_bind_imports(NSData *image, NSString **problem) {
    span s = {image.bytes, image.length};
    if (!fits(s, 0, sizeof(struct mach_header_64)) || u32(s.p) != MH_MAGIC_64) {
        if (problem) *problem = notImage;
        return nil;
    }
    uint32_t ncmds = u32(s.p + 16);
    NSMutableArray<NSString *> *dylibs = [NSMutableArray array];
    const uint8_t *info = NULL, *chained = NULL;
    size_t at = sizeof(struct mach_header_64);
    for (uint32_t c = 0; c < ncmds; c++) {
        if (!fits(s, at, 8)) goto bad;
        uint32_t cmd = u32(s.p + at), size = u32(s.p + at + 4);
        if (size < 8 || !fits(s, at, size)) goto bad;
        const uint8_t *lc = s.p + at;
        switch (cmd) {
            // Each takes the next ordinal, as MachO.loadedDylibs counts them.
            case LC_LOAD_DYLIB:
            case LC_LOAD_WEAK_DYLIB:
            case LC_REEXPORT_DYLIB:
            case LC_LAZY_LOAD_DYLIB:
            case LC_LOAD_UPWARD_DYLIB: {
                if (size < sizeof(struct dylib_command)) goto bad;
                uint32_t name = u32(lc + 8);
                const uint8_t *nul = name < size ? memchr(lc + name, 0, size - name) : NULL;
                NSString *n = nul ? [[NSString alloc] initWithBytes:lc + name length:(NSUInteger)(nul - (lc + name))
                                                           encoding:NSUTF8StringEncoding] : nil;
                if (!n) goto bad;
                [dylibs addObject:n];
                break;
            }
            case LC_DYLD_INFO:
            case LC_DYLD_INFO_ONLY:
                if (size < sizeof(struct dyld_info_command)) goto bad;
                info = lc;
                break;
            case LC_DYLD_CHAINED_FIXUPS:
                if (size < sizeof(struct linkedit_data_command)) goto bad;
                chained = lc;
                break;
        }
        at += size;
    }
    {
        NSMutableArray<NSArray<NSString *> *> *out = [NSMutableArray array];
        NSMutableSet<NSArray<NSString *> *> *seen = [NSMutableSet set];
        void (^add)(NSString *, NSString *) = ^(NSString *lib, NSString *sym) {
            NSArray<NSString *> *pair = @[lib, sym];
            if ([seen containsObject:pair]) return;
            [seen addObject:pair];
            [out addObject:pair];
        };
        BOOL ok = YES;
        if (info) {
            const struct dyld_info_command *d = (const void *)info;
            ok = bind_opcodes(s, d->bind_off, d->bind_size, NO, NO, dylibs, add)
              && bind_opcodes(s, d->weak_bind_off, d->weak_bind_size, NO, YES, dylibs, add)
              && bind_opcodes(s, d->lazy_bind_off, d->lazy_bind_size, YES, NO, dylibs, add);
        }
        if (ok && chained) {
            const struct linkedit_data_command *d = (const void *)chained;
            ok = chained_imports(s, d->dataoff, d->datasize, dylibs, add);
        }
        if (!ok) {
            if (problem) *problem = @"its fixup info doesn't parse";
            return nil;
        }
        if (!info && !chained) {
            if (problem) *problem = @"it has no fixup info";
            return nil;
        }
        return out;
    }
bad:
    if (problem) *problem = @"a load command runs past its end";
    return nil;
}

// The name BindCheck reports a library under: dyld_info's short name ("(from AppKit)"), the install
// name's last component up to its first dot.
static NSString *short_name(NSString *install) {
    if ([install hasPrefix:@"<"]) return install;
    return [install.lastPathComponent componentsSeparatedByString:@"."][0];
}

NSArray<NSString *> *sp_bind_unresolved(NSData *image, NSData *exports, NSSet<NSString *> *withheld, NSUInteger *total,
                                         NSString **problem) {
    NSArray<NSArray<NSString *> *> *imports = sp_bind_imports(image, problem);
    if (!imports) return nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:exports options:0 error:nil];
    NSDictionary *libraries = [json isKindOfClass:NSDictionary.class] ? json[@"libraries"] : nil;
    if (![libraries isKindOfClass:NSDictionary.class]) {
        if (problem) *problem = @"the app's exports.json isn't an exports manifest";
        return nil;
    }
    // Each library's symbols as a set, made the first time one of its imports is looked up.
    NSMutableDictionary<NSString *, NSSet<NSString *> *> *provided = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *unresolved = [NSMutableArray array];
    for (NSArray<NSString *> *pair in imports) {
        NSSet<NSString *> *symbols = provided[pair[0]];
        if (!symbols) {
            NSDictionary *lib = libraries[pair[0]];
            NSArray *list = [lib isKindOfClass:NSDictionary.class] ? lib[@"symbols"] : nil;
            symbols = [list isKindOfClass:NSArray.class] ? [NSSet setWithArray:list] : [NSSet set];
            provided[pair[0]] = symbols;
        }
        if (![symbols containsObject:pair[1]] || [withheld containsObject:pair[1]])
            [unresolved addObject:[NSString stringWithFormat:@"%@ %@", short_name(pair[0]), pair[1]]];
    }
    // A withheld symbol the image doesn't import still fails the check (BindCheck.check's rule), so a
    // drill with a mistyped symbol shows up as a drill rather than passing as if nothing were set.
    for (NSString *symbol in [withheld.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *suffix = [@" " stringByAppendingString:symbol];
        BOOL listed = NO;
        for (NSString *u in unresolved) listed = listed || [u hasSuffix:suffix];
        if (!listed) [unresolved addObject:[@"patch drill" stringByAppendingString:suffix]];
    }
    *total = imports.count;
    return unresolved;
}
