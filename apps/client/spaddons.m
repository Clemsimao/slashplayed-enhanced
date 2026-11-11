#import "spaddons.h"
#include <CommonCrypto/CommonDigest.h>
#include <zlib.h>

static BOOL matches(NSData *data, NSString *sha) {
    if (!data || data.length > 4 * 1024 * 1024) return NO;
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof digest; i++) [hex appendFormat:@"%02x", digest[i]];
    return [hex isEqual:sha];
}

// The publisher's ZIP uses deflate and data descriptors, so sizes come from the central directory,
// rather than the local headers. No ZIP64, encryption, links, or paths outside the named addon folders.
// Bounds and total output are capped even though the whole archive must match a pinned digest first.
static NSDictionary<NSString *, NSData *> *unpack(NSData *zip, NSArray<NSString *> *names) {
    const uint8_t *p = zip.bytes;
    NSUInteger size = zip.length;
    if (size < 22) return nil;
    uint32_t (^le)(NSUInteger, NSUInteger) = ^uint32_t(NSUInteger off, NSUInteger count) {
        uint32_t n = 0;
        for (NSUInteger i = 0; i < count; i++) n |= (uint32_t)p[off + i] << (8 * i);
        return n;
    };
    NSUInteger end = size - 22;
    while (le(end, 4) != 0x06054b50 || end + 22 + le(end + 20, 2) != size) {
        if (end == 0 || size - end > 65557) return nil;
        end--;
    }
    NSUInteger count = le(end + 10, 2), at = le(end + 16, 4), length = le(end + 12, 4);
    if (le(end + 4, 2) || le(end + 6, 2) || le(end + 8, 2) != count ||
        count == 0 || count > 4096 || at > end || length != end - at) return nil;
    NSMutableDictionary<NSString *, NSData *> *files = [NSMutableDictionary dictionary];
    NSUInteger total = 0;
    for (NSUInteger i = 0; i < count; i++) {
        if (at > end || end - at < 46 || le(at, 4) != 0x02014b50) return nil;
        NSUInteger flags = le(at + 8, 2), method = le(at + 10, 2), crc = le(at + 16, 4);
        NSUInteger packed = le(at + 20, 4), plain = le(at + 24, 4), n = le(at + 28, 2);
        NSUInteger next = at + 46 + n + le(at + 30, 2) + le(at + 32, 2), local = le(at + 42, 4);
        // Bits 1–2 are deflate compression hints, bit 3 a data descriptor, and bit 11 UTF-8 names.
        if (next > end || flags & ~0x80e || (method != 0 && method != 8) ||
            le(at + 34, 2) || ((le(at + 38, 4) >> 16) & 0170000) == 0120000) return nil;
        NSString *path = [[NSString alloc] initWithBytes:p + at + 46 length:n encoding:NSUTF8StringEncoding];
        at = next;
        if (!path.length || [path containsString:@"\\"] || [path containsString:@"\0"]) return nil;
        BOOL directory = [path hasSuffix:@"/"];
        NSString *file = directory ? [path substringToIndex:path.length - 1] : path;
        NSArray<NSString *> *parts = [file componentsSeparatedByString:@"/"];
        if (![names containsObject:parts.firstObject] || (!directory && parts.count < 2)) return nil;
        for (NSString *part in parts) if (!part.length || [part isEqual:@"."] || [part isEqual:@".."]) return nil;
        if (directory) continue;
        total += plain;
        if (total > 16 * 1024 * 1024 || plain > 2 * 1024 * 1024 || files[file] ||
            local > size || size - local < 30 || le(local, 4) != 0x04034b50) return nil;
        NSUInteger start = local + 30 + le(local + 26, 2) + le(local + 28, 2);
        if (start > size || packed > size - start) return nil;
        NSMutableData *out = [NSMutableData dataWithLength:MAX(plain, 1)];
        if (method == 0) {
            if (packed != plain) return nil;
            if (plain) memcpy(out.mutableBytes, p + start, plain);
        } else {
            z_stream z = {0};
            if (inflateInit2(&z, -MAX_WBITS) != Z_OK) return nil;
            z.next_in = (Bytef *)p + start; z.avail_in = (uInt)packed;
            z.next_out = out.mutableBytes; z.avail_out = (uInt)out.length;
            int status = inflate(&z, Z_FINISH);
            BOOL valid = status == Z_STREAM_END && z.total_out == plain && z.total_in == packed;
            inflateEnd(&z);
            if (!valid) return nil;
        }
        out.length = plain;
        if (crc32(0, out.bytes, (uInt)out.length) != crc) return nil;
        files[file] = out;
    }
    if (at != end) return nil;
    for (NSString *name in names)
        if (!files[[NSString stringWithFormat:@"%@/%@.toc", name, name]]) return nil;
    return files;
}

BOOL sp_addon_download(NSString *cache, NSString *game, NSURL *url, NSString *sha256,
                       NSArray<NSString *> *names, SPFetch fetch, NSString **line) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *problem = nil;
    NSData *zip = [NSData dataWithContentsOfFile:cache];
    BOOL downloaded = !matches(zip, sha256);
    if (downloaded) zip = fetch(url, NSMakeRange(0, 0), &problem);
    if (!matches(zip, sha256)) {
        *line = [NSString stringWithFormat:@"addons: Bagnon unavailable (%@); will retry next launch", problem ?: @"package checksum mismatch"];
        return NO;
    }
    NSDictionary<NSString *, NSData *> *files = unpack(zip, names);
    if (!files) { *line = @"addons: Bagnon package is invalid"; return NO; }
    if (downloaded) {
        [fm createDirectoryAtPath:cache.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        if (![zip writeToFile:cache atomically:YES]) { *line = @"addons: couldn't cache Bagnon"; return NO; }
    }
    NSString *root = [game.stringByResolvingSymlinksInPath stringByAppendingPathComponent:@"Interface/AddOns"];
    NSArray<NSString *> *ordered = [files.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *file in ordered) {
        // Check every component before writing. Resolving a whole path misses links when the leaf
        // doesn't exist yet, precisely the case on a first install or when repairing a missing file.
        NSString *path = game;
        for (NSString *part in [[@"Interface/AddOns" stringByAppendingPathComponent:file] componentsSeparatedByString:@"/"]) {
            path = [path stringByAppendingPathComponent:part];
            if ([[fm attributesOfItemAtPath:path error:nil][NSFileType] isEqual:NSFileTypeSymbolicLink]) {
                *line = @"addons: Bagnon destination contains a symbolic link"; return NO;
            }
        }
    }
    NSUInteger written = 0;
    for (NSString *file in ordered) {
        NSString *dest = [root stringByAppendingPathComponent:file];
        if ([[NSData dataWithContentsOfFile:dest] isEqual:files[file]]) continue;
        [fm createDirectoryAtPath:dest.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        if (![files[file] writeToFile:dest atomically:YES]) {
            *line = [NSString stringWithFormat:@"addons: couldn't write %@", file]; return NO;
        }
        written++;
    }
    *line = [NSString stringWithFormat:@"addons: Bagnon %@, wrote %lu files", downloaded ? @"downloaded" : @"cached", (unsigned long)written];
    return YES;
}

BOOL sp_bagnon_place(NSString *cache, NSString *game, NSString *flavor, SPFetch fetch, NSString **line) {
    // CurseForge file 9546609, published by Jaliborc. Keep URL and SHA together when updating the pin.
    // The package's TOCs explicitly support these five flavors, including Forever (16001).
    if (![@[@"classic_era", @"anniversary", @"classic", @"retail", @"forever"] containsObject:flavor]) {
        *line = @"addons: Bagnon has no package for this game"; return YES;
    }
    return sp_addon_download([cache stringByAppendingPathComponent:@"Bagnon-12.1.9.zip"], game,
        [NSURL URLWithString:@"https://edge.forgecdn.net/files/9546/609/Bagnon-12.1.9.zip"],
        @"18d274f99ff3ca02cb73947b5e36c13fea555fb5a65f2bfc443e064ac15c0847",
        @[@"BagBrother", @"Bagnon", @"Bagnon_Bank", @"Bagnon_Config", @"Bagnon_GuildBank"], fetch, line);
}
