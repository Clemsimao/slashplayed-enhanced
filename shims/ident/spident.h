// Shared by spiokit.c and spdiskarb.c: describe CF values for the identity logs as type, size and
// hash, never the value (serials, UUIDs, MACs and names stay out of logs). Numbers and booleans are
// printed. Expects sp_stub_log() and SP_CALLER from the generated shim, or from mac-prelude.h.
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>

static unsigned sp_ihash(const void *p, size_t len) {
    unsigned h = 2166136261u;
    for (size_t i = 0; i < len; i++) h = (h ^ ((const unsigned char *)p)[i]) * 16777619u;
    return h;
}

static void sp_cf_desc(CFTypeRef v, char *out, size_t len) {
    if (!v) {
        snprintf(out, len, "NULL");
        return;
    }
    CFTypeID t = CFGetTypeID(v);
    if (t == CFStringGetTypeID()) {
        char s[1024] = "";
        CFStringGetCString(v, s, sizeof s, kCFStringEncodingUTF8);
        snprintf(out, len, "string %ld chars #%08x", (long)CFStringGetLength(v), sp_ihash(s, strlen(s)));
    } else if (t == CFDataGetTypeID()) {
        snprintf(out, len, "data %ld B #%08x", (long)CFDataGetLength(v),
                 sp_ihash(CFDataGetBytePtr(v), CFDataGetLength(v)));
    } else if (t == CFNumberGetTypeID()) {
        long long n = 0;
        CFNumberGetValue(v, kCFNumberLongLongType, &n);
        snprintf(out, len, "number %lld", n);
    } else if (t == CFBooleanGetTypeID()) {
        snprintf(out, len, "%s", CFBooleanGetValue(v) ? "true" : "false");
    } else if (t == CFDictionaryGetTypeID()) {
        snprintf(out, len, "dict %ld keys", (long)CFDictionaryGetCount(v));
    } else if (t == CFArrayGetTypeID()) {
        snprintf(out, len, "array %ld", (long)CFArrayGetCount(v));
    } else if (t == CFURLGetTypeID()) {
        CFStringRef s = CFURLGetString(v);
        char p[1024] = "";
        CFStringGetCString(s, p, sizeof p, kCFStringEncodingUTF8);
        snprintf(out, len, "url %zu chars #%08x", strlen(p), sp_ihash(p, strlen(p)));
    } else if (t == CFUUIDGetTypeID()) {
        CFUUIDBytes b = CFUUIDGetUUIDBytes(v);
        snprintf(out, len, "uuid #%08x", sp_ihash(&b, sizeof b));
    } else {
        snprintf(out, len, "type %lu", (unsigned long)t);
    }
}

static void sp_cf_cstr(CFStringRef s, char *out, size_t len) {
    if (!s || !CFStringGetCString(s, out, len, kCFStringEncodingUTF8)) snprintf(out, len, "?");
}

// Each dictionary entry on its own line: "<prefix> key: value".
static void sp_cf_dict_log(const char *prefix, CFDictionaryRef d) {
    if (!d || CFGetTypeID(d) != CFDictionaryGetTypeID()) return;
    CFIndex n = CFDictionaryGetCount(d);
    const void *keys[256], *vals[256];
    if (n > 256) n = 256;
    CFDictionaryGetKeysAndValues(d, keys, vals);
    for (CFIndex i = 0; i < n; i++) {
        char k[128], v[96], line[300];
        if (CFGetTypeID(keys[i]) == CFStringGetTypeID()) sp_cf_cstr(keys[i], k, sizeof k);
        else snprintf(k, sizeof k, "(non-string key)");
        sp_cf_desc(vals[i], v, sizeof v);
        snprintf(line, sizeof line, "%s %s: %s", prefix, k, v);
        sp_stub_log(line);
    }
}

// At most `limit` lines per call site.
#define SP_ID_LOG(limit, ...) do { \
    static atomic_int sp_logged_; \
    if (atomic_fetch_add(&sp_logged_, 1) < (limit)) { \
        char buf_[400]; \
        snprintf(buf_, sizeof buf_, __VA_ARGS__); \
        sp_stub_log(buf_); \
    } \
} while (0)
