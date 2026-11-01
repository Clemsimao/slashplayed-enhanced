// CoreFoundation calls that could carry identity (locale, time zone, preferences, bundle info),
// logged on their way to the real CoreFoundation when SP_SYSTEM_TRACE is set. Observation only: every
// wrapper returns exactly what the real call returned. Locale, time zone and bundle strings are
// printed; preference values are logged as type, size and hash (spident.h).
// #included at the end of the generated libspCoreFoundation.m on visionOS (gen_stubs.py
// EXTRA_INCLUDES, FORCE_SHIM); built alone for the Mac probe by build-mac.sh. __asm__("_symbol") wins
// over the shim's re-export of CoreFoundation, so the shim's own calls to these would come back here:
// the wrappers reach the real functions through sp_real_cf() only.
#include "spident.h"
#include <stdlib.h>

static void *sp_real_cf(const char *sym) {
    static void *h;
    if (!h) h = dlopen("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", RTLD_LAZY);
    if (!h) h = dlopen("/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation", RTLD_LAZY);
    void *p = h ? dlsym(h, sym) : NULL;
    if (!p) {
        char buf[96];
        snprintf(buf, sizeof buf, "no real %s", sym);
        sp_stub_log(buf);
    }
    return p;
}

#define SP_CF_REAL(type, name) \
    static __typeof__(type) fn; \
    if (!fn) fn = (type)sp_real_cf(name)

static int sp_cf_tracing(void) {
    static int t = -1;
    if (t < 0) t = getenv("SP_SYSTEM_TRACE") != NULL;
    return t;
}

#define SP_CF_LOG(limit, ...) do { if (sp_cf_tracing()) SP_ID_LOG(limit, __VA_ARGS__); } while (0)

// A string printed as is (locale, time zone, bundle info: not personal), anything else as sp_cf_desc.
static void sp_cf_plain(CFTypeRef v, char *out, size_t len) {
    if (v && CFGetTypeID(v) == CFStringGetTypeID()) {
        char s[200];
        sp_cf_cstr(v, s, sizeof s);
        snprintf(out, len, "\"%s\"", s);
    } else {
        sp_cf_desc(v, out, len);
    }
}

static void sp_cf_locale_id(CFLocaleRef l, char *out, size_t len) {
    SP_CF_REAL(CFStringRef (*)(CFLocaleRef), "CFLocaleGetIdentifier");
    sp_cf_plain(l && fn ? fn(l) : NULL, out, len);
}

CFLocaleRef sp_CFLocaleCopyCurrent(void) __asm__("_CFLocaleCopyCurrent");
CFLocaleRef sp_CFLocaleCopyCurrent(void) {
    SP_CF_REAL(CFLocaleRef (*)(void), "CFLocaleCopyCurrent");
    CFLocaleRef r = fn();
    char id[220];
    sp_cf_locale_id(r, id, sizeof id);
    SP_CF_LOG(40, "cf: CFLocaleCopyCurrent() = %s from +0x%lx", id, SP_CALLER);
    return r;
}

CFLocaleRef sp_CFLocaleGetSystem(void) __asm__("_CFLocaleGetSystem");
CFLocaleRef sp_CFLocaleGetSystem(void) {
    SP_CF_REAL(CFLocaleRef (*)(void), "CFLocaleGetSystem");
    CFLocaleRef r = fn();
    char id[220];
    sp_cf_locale_id(r, id, sizeof id);
    SP_CF_LOG(40, "cf: CFLocaleGetSystem() = %s from +0x%lx", id, SP_CALLER);
    return r;
}

CFTypeRef sp_CFLocaleGetValue(CFLocaleRef l, CFStringRef key) __asm__("_CFLocaleGetValue");
CFTypeRef sp_CFLocaleGetValue(CFLocaleRef l, CFStringRef key) {
    SP_CF_REAL(CFTypeRef (*)(CFLocaleRef, CFStringRef), "CFLocaleGetValue");
    CFTypeRef r = fn(l, key);
    char id[220], k[128], v[220];
    sp_cf_locale_id(l, id, sizeof id);
    sp_cf_cstr(key, k, sizeof k);
    sp_cf_plain(r, v, sizeof v);
    SP_CF_LOG(80, "cf: CFLocaleGetValue(%s, %s) = %s from +0x%lx", id, k, v, SP_CALLER);
    return r;
}

CFTimeZoneRef sp_CFTimeZoneCopySystem(void) __asm__("_CFTimeZoneCopySystem");
CFTimeZoneRef sp_CFTimeZoneCopySystem(void) {
    SP_CF_REAL(CFTimeZoneRef (*)(void), "CFTimeZoneCopySystem");
    static CFStringRef (*name)(CFTimeZoneRef);
    if (!name) name = (CFStringRef (*)(CFTimeZoneRef))sp_real_cf("CFTimeZoneGetName");
    CFTimeZoneRef r = fn();
    char n[220];
    sp_cf_plain(r && name ? name(r) : NULL, n, sizeof n);
    SP_CF_LOG(40, "cf: CFTimeZoneCopySystem() = %s from +0x%lx", n, SP_CALLER);
    return r;
}

CFTimeInterval sp_CFTimeZoneGetSecondsFromGMT(CFTimeZoneRef tz, CFAbsoluteTime at) __asm__("_CFTimeZoneGetSecondsFromGMT");
CFTimeInterval sp_CFTimeZoneGetSecondsFromGMT(CFTimeZoneRef tz, CFAbsoluteTime at) {
    SP_CF_REAL(CFTimeInterval (*)(CFTimeZoneRef, CFAbsoluteTime), "CFTimeZoneGetSecondsFromGMT");
    CFTimeInterval r = fn(tz, at);
    SP_CF_LOG(40, "cf: CFTimeZoneGetSecondsFromGMT() = %.0f from +0x%lx", r, SP_CALLER);
    return r;
}

CFPropertyListRef sp_CFPreferencesCopyAppValue(CFStringRef key, CFStringRef app) __asm__("_CFPreferencesCopyAppValue");
CFPropertyListRef sp_CFPreferencesCopyAppValue(CFStringRef key, CFStringRef app) {
    SP_CF_REAL(CFPropertyListRef (*)(CFStringRef, CFStringRef), "CFPreferencesCopyAppValue");
    CFPropertyListRef r = fn(key, app);
    char k[128], a[128], v[96];
    sp_cf_cstr(key, k, sizeof k);
    sp_cf_cstr(app, a, sizeof a);
    sp_cf_desc(r, v, sizeof v);
    SP_CF_LOG(200, "cf: CFPreferencesCopyAppValue(\"%s\", %s) = %s from +0x%lx", k, a, v, SP_CALLER);
    return r;
}

CFIndex sp_CFPreferencesGetAppIntegerValue(CFStringRef key, CFStringRef app, Boolean *ok)
    __asm__("_CFPreferencesGetAppIntegerValue");
CFIndex sp_CFPreferencesGetAppIntegerValue(CFStringRef key, CFStringRef app, Boolean *ok) {
    SP_CF_REAL(CFIndex (*)(CFStringRef, CFStringRef, Boolean *), "CFPreferencesGetAppIntegerValue");
    Boolean mine;
    CFIndex r = fn(key, app, ok ? ok : &mine);
    char k[128], a[128];
    sp_cf_cstr(key, k, sizeof k);
    sp_cf_cstr(app, a, sizeof a);
    SP_CF_LOG(100, "cf: CFPreferencesGetAppIntegerValue(\"%s\", %s) = %ld (%s) from +0x%lx", k, a, (long)r,
              (ok ? *ok : mine) ? "set" : "unset", SP_CALLER);
    return r;
}

CFTypeRef sp_CFBundleGetValueForInfoDictionaryKey(CFBundleRef b, CFStringRef key)
    __asm__("_CFBundleGetValueForInfoDictionaryKey");
CFTypeRef sp_CFBundleGetValueForInfoDictionaryKey(CFBundleRef b, CFStringRef key) {
    SP_CF_REAL(CFTypeRef (*)(CFBundleRef, CFStringRef), "CFBundleGetValueForInfoDictionaryKey");
    CFTypeRef r = fn(b, key);
    char k[128], v[220];
    sp_cf_cstr(key, k, sizeof k);
    sp_cf_plain(r, v, sizeof v);
    SP_CF_LOG(100, "cf: CFBundleGetValueForInfoDictionaryKey(\"%s\") = %s from +0x%lx", k, v, SP_CALLER);
    return r;
}

UInt32 sp_CFBundleGetVersionNumber(CFBundleRef b) __asm__("_CFBundleGetVersionNumber");
UInt32 sp_CFBundleGetVersionNumber(CFBundleRef b) {
    SP_CF_REAL(UInt32 (*)(CFBundleRef), "CFBundleGetVersionNumber");
    UInt32 r = fn(b);
    SP_CF_LOG(40, "cf: CFBundleGetVersionNumber() = 0x%x from +0x%lx", r, SP_CALLER);
    return r;
}

CFStringRef sp_CFBundleGetIdentifier(CFBundleRef b) __asm__("_CFBundleGetIdentifier");
CFStringRef sp_CFBundleGetIdentifier(CFBundleRef b) {
    SP_CF_REAL(CFStringRef (*)(CFBundleRef), "CFBundleGetIdentifier");
    CFStringRef r = fn(b);
    char v[220];
    sp_cf_plain(r, v, sizeof v);
    SP_CF_LOG(60, "cf: CFBundleGetIdentifier() = %s from +0x%lx", v, SP_CALLER);
    return r;
}

CFBundleRef sp_CFBundleCreate(CFAllocatorRef a, CFURLRef url) __asm__("_CFBundleCreate");
CFBundleRef sp_CFBundleCreate(CFAllocatorRef a, CFURLRef url) {
    SP_CF_REAL(CFBundleRef (*)(CFAllocatorRef, CFURLRef), "CFBundleCreate");
    CFBundleRef r = fn(a, url);
    char u[96];
    sp_cf_desc(url, u, sizeof u);
    SP_CF_LOG(40, "cf: CFBundleCreate(%s) = %s from +0x%lx", u, r ? "bundle" : "NULL", SP_CALLER);
    return r;
}

CFDictionaryRef sp_CFBundleCopyInfoDictionaryForURL(CFURLRef url) __asm__("_CFBundleCopyInfoDictionaryForURL");
CFDictionaryRef sp_CFBundleCopyInfoDictionaryForURL(CFURLRef url) {
    SP_CF_REAL(CFDictionaryRef (*)(CFURLRef), "CFBundleCopyInfoDictionaryForURL");
    CFDictionaryRef r = fn(url);
    char u[96], v[96];
    sp_cf_desc(url, u, sizeof u);
    sp_cf_desc(r, v, sizeof v);
    SP_CF_LOG(40, "cf: CFBundleCopyInfoDictionaryForURL(%s) = %s from +0x%lx", u, v, SP_CALLER);
    return r;
}

CFArrayRef sp_CFBundleGetAllBundles(void) __asm__("_CFBundleGetAllBundles");
CFArrayRef sp_CFBundleGetAllBundles(void) {
    SP_CF_REAL(CFArrayRef (*)(void), "CFBundleGetAllBundles");
    CFArrayRef r = fn();
    char v[96];
    sp_cf_desc(r, v, sizeof v);
    SP_CF_LOG(40, "cf: CFBundleGetAllBundles() = %s from +0x%lx", v, SP_CALLER);
    return r;
}

CFStringEncoding sp_CFStringGetSystemEncoding(void) __asm__("_CFStringGetSystemEncoding");
CFStringEncoding sp_CFStringGetSystemEncoding(void) {
    SP_CF_REAL(CFStringEncoding (*)(void), "CFStringGetSystemEncoding");
    CFStringEncoding r = fn();
    SP_CF_LOG(20, "cf: CFStringGetSystemEncoding() = 0x%x from +0x%lx", r, SP_CALLER);
    return r;
}
