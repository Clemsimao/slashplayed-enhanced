// Foundation calls that could carry identity (OS version, host and user names, locale, time zone,
// bundle info, user defaults), logged when SP_SYSTEM_TRACE is set and the caller is the client.
// Observation only (every wrapper returns exactly what the real call returned), except, on visionOS,
// NSUserName() for the client, which answers from the small identity file login needs from the Mac
// (the user's decision of 2026-10-12). OS version, locale, time zone and bundle strings are printed;
// names, paths and defaults values as size and hash.
// Methods are wrapped by replacing their implementations at load (the original is called through);
// functions with __asm__("_symbol"), which wins over the shim's re-export of Foundation.
// #included at the end of the generated libspFoundation.m on visionOS (gen_stubs.py EXTRA_INCLUDES);
// built alone for the Mac probe by build-mac.sh.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include "spident.h"

static int sp_fn_tracing(void) {
    static int t = -1;
    if (t < 0) t = getenv("SP_SYSTEM_TRACE") != NULL;
    return t;
}

// The caller is in the client's __TEXT.
static int sp_fn_from_client(uintptr_t ret) {
    static uintptr_t lo, hi;
    if (!hi) {
        const struct mach_header_64 *h = (const struct mach_header_64 *)sp_client_base();
        const struct load_command *lc = (const struct load_command *)(h + 1);
        for (uint32_t i = 0; i < h->ncmds; i++, lc = (const void *)((const char *)lc + lc->cmdsize)) {
            const struct segment_command_64 *s = (const void *)lc;
            if (lc->cmd == LC_SEGMENT_64 && !strcmp(s->segname, "__TEXT")) {
                lo = (uintptr_t)h;
                hi = lo + s->vmsize;
            }
        }
    }
    return ret >= lo && ret < hi;
}

#define SP_FN_LOG(limit, ...) do { \
    if (sp_fn_tracing() && sp_fn_from_client((uintptr_t)__builtin_return_address(0))) \
        SP_ID_LOG(limit, __VA_ARGS__); \
} while (0)

// plain: strings (and arrays of them) printed as is; otherwise strings as size and hash.
static void sp_ns_desc(id v, BOOL plain, char *out, size_t len) {
    if (!v) {
        snprintf(out, len, "nil");
    } else if ([v isKindOfClass:[NSString class]]) {
        const char *s = [v UTF8String] ?: "";
        if (plain) snprintf(out, len, "\"%s\"", s);
        else snprintf(out, len, "string %lu chars #%08x", (unsigned long)[v length], sp_ihash(s, strlen(s)));
    } else if ([v isKindOfClass:[NSArray class]]) {
        size_t n = snprintf(out, len, "array %lu [", (unsigned long)[v count]);
        for (id e in v) {
            if (n >= len) break;
            char d[120];
            sp_ns_desc(e, plain, d, sizeof d);
            n += snprintf(out + n, len - n, "%s ", d);
        }
        if (n < len) snprintf(out + n, len - n, "]");
    } else if ([v isKindOfClass:[NSNumber class]]) {
        snprintf(out, len, "number %s", [[v stringValue] UTF8String]);
    } else if ([v isKindOfClass:[NSData class]]) {
        snprintf(out, len, "data %lu B #%08x", (unsigned long)[v length], sp_ihash([v bytes], [v length]));
    } else if ([v isKindOfClass:[NSDictionary class]]) {
        snprintf(out, len, "dict %lu keys", (unsigned long)[v count]);
    } else if ([v isKindOfClass:[NSLocale class]]) {
        snprintf(out, len, "locale \"%s\"", [[v localeIdentifier] UTF8String]);
    } else if ([v isKindOfClass:[NSTimeZone class]]) {
        snprintf(out, len, "timezone \"%s\"", [[v name] UTF8String]);
    } else {
        snprintf(out, len, "<%s>", object_getClassName(v));
    }
}

// Replace cls's (or its metaclass's, for +methods) implementation of sel with a block that calls the
// original. Each SP_WRAP_* expands to one block type; `plain` as in sp_ns_desc.
static IMP sp_swap(Class cls, BOOL meta, const char *selname, id block) {
    SEL sel = sel_registerName(selname);
    Method m = meta ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!m) {
        char line[160];
        snprintf(line, sizeof line, "fn: no %c[%s %s] to trace", meta ? '+' : '-', class_getName(cls), selname);
        sp_stub_log(line);
        return NULL;
    }
    return method_setImplementation(m, imp_implementationWithBlock(block));
}

#define SP_WRAP_OBJ(cls, meta, selname, plain) do { \
    static id (*orig)(id, SEL); \
    orig = (id (*)(id, SEL))sp_swap(cls, meta, selname, ^id(id self_) { \
        id r = orig(self_, sel_registerName(selname)); \
        char d_[300]; \
        sp_ns_desc(r, plain, d_, sizeof d_); \
        SP_FN_LOG(40, "fn: %c[%s %s] = %s from +0x%lx", meta ? '+' : '-', object_getClassName(self_), selname, \
                  d_, SP_CALLER); \
        return r; \
    }); \
} while (0)

#define SP_WRAP_OBJ_KEY(cls, meta, selname, plain) do { \
    static id (*orig)(id, SEL, id); \
    orig = (id (*)(id, SEL, id))sp_swap(cls, meta, selname, ^id(id self_, id key) { \
        id r = orig(self_, sel_registerName(selname), key); \
        char k_[160], d_[300]; \
        sp_ns_desc(key, YES, k_, sizeof k_); \
        sp_ns_desc(r, plain, d_, sizeof d_); \
        SP_FN_LOG(100, "fn: -[%s %s%s] = %s from +0x%lx", object_getClassName(self_), selname, k_, d_, SP_CALLER); \
        return r; \
    }); \
} while (0)

#define SP_WRAP_INT_KEY(cls, selname, type) do { \
    static type (*orig)(id, SEL, id); \
    orig = (type (*)(id, SEL, id))sp_swap(cls, NO, selname, ^type(id self_, id key) { \
        type r = orig(self_, sel_registerName(selname), key); \
        char k_[160]; \
        sp_ns_desc(key, YES, k_, sizeof k_); \
        SP_FN_LOG(100, "fn: -[%s %s%s] = %lld from +0x%lx", object_getClassName(self_), selname, k_, (long long)r, \
                  SP_CALLER); \
        return r; \
    }); \
} while (0)

#define SP_WRAP_INT(cls, selname, type) do { \
    static type (*orig)(id, SEL); \
    orig = (type (*)(id, SEL))sp_swap(cls, NO, selname, ^type(id self_) { \
        type r = orig(self_, sel_registerName(selname)); \
        SP_FN_LOG(40, "fn: -[%s %s] = %lld from +0x%lx", object_getClassName(self_), selname, (long long)r, SP_CALLER); \
        return r; \
    }); \
} while (0)

__attribute__((constructor)) static void sp_fn_trace_init(void) {
    if (!sp_fn_tracing()) return;
    @autoreleasepool {
        Class pi = [[NSProcessInfo processInfo] class];
        {
            static NSOperatingSystemVersion (*orig)(id, SEL);
            orig = (NSOperatingSystemVersion (*)(id, SEL))sp_swap(pi, NO, "operatingSystemVersion",
                                                                   ^NSOperatingSystemVersion(id self_) {
                NSOperatingSystemVersion r = orig(self_, @selector(operatingSystemVersion));
                SP_FN_LOG(40, "fn: -[NSProcessInfo operatingSystemVersion] = %ld.%ld.%ld from +0x%lx",
                          (long)r.majorVersion, (long)r.minorVersion, (long)r.patchVersion, SP_CALLER);
                return r;
            });
        }
        SP_WRAP_OBJ(pi, NO, "operatingSystemVersionString", YES);
        SP_WRAP_OBJ(pi, NO, "processName", YES);
        SP_WRAP_OBJ(pi, NO, "hostName", NO);
        SP_WRAP_OBJ(pi, NO, "globallyUniqueString", NO);
        SP_WRAP_INT(pi, "physicalMemory", unsigned long long);
        SP_WRAP_INT(pi, "processorCount", NSUInteger);
        SP_WRAP_INT(pi, "activeProcessorCount", NSUInteger);

        Class host = objc_getClass("NSHost");  // private on visionOS (no header)
        if (host) {
            SP_WRAP_OBJ(host, YES, "currentHost", NO);
            SP_WRAP_OBJ(host, NO, "name", NO);
            SP_WRAP_OBJ(host, NO, "names", NO);
            SP_WRAP_OBJ(host, NO, "localizedName", NO);
            SP_WRAP_OBJ(host, NO, "address", NO);
            SP_WRAP_OBJ(host, NO, "addresses", NO);
        } else {
            sp_stub_log("fn: no NSHost class to trace");
        }

        Class locale = [NSLocale class], loc = [[NSLocale currentLocale] class];
        SP_WRAP_OBJ(locale, YES, "currentLocale", YES);
        SP_WRAP_OBJ(locale, YES, "systemLocale", YES);
        SP_WRAP_OBJ(locale, YES, "autoupdatingCurrentLocale", YES);
        SP_WRAP_OBJ(locale, YES, "preferredLanguages", YES);
        SP_WRAP_OBJ(loc, NO, "localeIdentifier", YES);
        SP_WRAP_OBJ(loc, NO, "languageCode", YES);
        SP_WRAP_OBJ(loc, NO, "countryCode", YES);
        SP_WRAP_OBJ_KEY(loc, NO, "objectForKey:", YES);

        Class tz = [NSTimeZone class], tzi = [[NSTimeZone systemTimeZone] class];
        SP_WRAP_OBJ(tz, YES, "systemTimeZone", YES);
        SP_WRAP_OBJ(tz, YES, "localTimeZone", YES);
        SP_WRAP_OBJ(tz, YES, "defaultTimeZone", YES);
        SP_WRAP_OBJ(tzi, NO, "name", YES);
        SP_WRAP_INT(tzi, "secondsFromGMT", NSInteger);

        Class bundle = [NSBundle class];
        SP_WRAP_OBJ(bundle, NO, "bundleIdentifier", YES);
        SP_WRAP_OBJ(bundle, NO, "infoDictionary", YES);
        SP_WRAP_OBJ(bundle, NO, "bundlePath", NO);
        SP_WRAP_OBJ_KEY(bundle, NO, "objectForInfoDictionaryKey:", YES);

        Class ud = [NSUserDefaults class];
        SP_WRAP_OBJ_KEY(ud, NO, "objectForKey:", NO);
        SP_WRAP_OBJ_KEY(ud, NO, "stringForKey:", NO);
        SP_WRAP_OBJ_KEY(ud, NO, "arrayForKey:", NO);
        SP_WRAP_OBJ_KEY(ud, NO, "dictionaryForKey:", NO);
        SP_WRAP_OBJ_KEY(ud, NO, "dataForKey:", NO);
        SP_WRAP_INT_KEY(ud, "integerForKey:", NSInteger);
        SP_WRAP_INT_KEY(ud, "boolForKey:", BOOL);
        sp_stub_log("fn: Foundation identity trace on");
    }
}

static void *sp_real_foundation(const char *sym) {
    static void *h;
    if (!h) h = dlopen("/System/Library/Frameworks/Foundation.framework/Foundation", RTLD_LAZY);
    if (!h) h = dlopen("/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation", RTLD_LAZY);
    return h ? dlsym(h, sym) : NULL;
}

#if !TARGET_OS_OSX
// The Mac user's name: the whole of <container>/Library/spidentity (written by mac-identity.c), or nil.
static NSString *sp_mac_user_name(void) {
    static NSString *name;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *home = getenv("HOME");
        NSData *d = home ? [NSData dataWithContentsOfFile:[NSString stringWithFormat:@"%s/Library/spidentity", home]] : nil;
        if (d.length) name = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        char line[80];
        snprintf(line, sizeof line, "ident: user name (Library/spidentity) %lu chars #%08x", (unsigned long)name.length,
                 name ? sp_ihash(name.UTF8String, strlen(name.UTF8String)) : 0);
        sp_stub_log(name ? line : "ident: no user name in Library/spidentity");
    });
    return name;
}
#endif

NSString *sp_NSUserName(void) __asm__("_NSUserName");
NSString *sp_NSUserName(void) {
    static NSString *(*fn)(void);
    if (!fn) fn = (NSString *(*)(void))sp_real_foundation("NSUserName");
    NSString *r = fn();
#if !TARGET_OS_OSX
    if (sp_fn_from_client((uintptr_t)__builtin_return_address(0))) r = sp_mac_user_name() ?: r;
#endif
    char d[120];
    sp_ns_desc(r, NO, d, sizeof d);
    SP_FN_LOG(20, "fn: NSUserName() = %s from +0x%lx", d, SP_CALLER);
    return r;
}

NSString *sp_NSFullUserName(void) __asm__("_NSFullUserName");
NSString *sp_NSFullUserName(void) {
    static NSString *(*fn)(void);
    if (!fn) fn = (NSString *(*)(void))sp_real_foundation("NSFullUserName");
    NSString *r = fn();
    char d[120];
    sp_ns_desc(r, NO, d, sizeof d);
    SP_FN_LOG(20, "fn: NSFullUserName() = %s from +0x%lx", d, SP_CALLER);
    return r;
}

NSArray *sp_NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory dir, NSSearchPathDomainMask mask, BOOL expand)
    __asm__("_NSSearchPathForDirectoriesInDomains");
NSArray *sp_NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory dir, NSSearchPathDomainMask mask, BOOL expand) {
    static NSArray *(*fn)(NSSearchPathDirectory, NSSearchPathDomainMask, BOOL);
    if (!fn) fn = (NSArray *(*)(NSSearchPathDirectory, NSSearchPathDomainMask, BOOL))
                      sp_real_foundation("NSSearchPathForDirectoriesInDomains");
    NSArray *r = fn(dir, mask, expand);
    char d[300];
    sp_ns_desc(r, NO, d, sizeof d);
    SP_FN_LOG(40, "fn: NSSearchPathForDirectoriesInDomains(%lu, %lu, %d) = %s from +0x%lx", (unsigned long)dir,
              (unsigned long)mask, expand, d, SP_CALLER);
    return r;
}
