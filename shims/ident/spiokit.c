// IOKit registry and matching calls, logged on their way to the real IOKit (identity: what the
// client reads about the machine). Values are logged as type, size and hash (spident.h).
// One change, on visionOS only (the user's decision): at login the client reads en0's MAC through
// IOServiceMatching("IOEthernetInterface"), which finds nothing in the sandbox. The match gets one
// made-up en0 instead, with a random MAC generated once per install (stored in the app's prefs,
// locally administered): a new machine, not a copy of another one's, and it logs in. #included at
// the end of the generated libspIOKit.m on visionOS (gen_stubs.py EXTRA_INCLUDES); built alone for the
// Mac probe by build-mac.sh. __asm__("_symbol") wins over the shim's re-export of IOKit.
#include "spident.h"
#include <TargetConditionals.h>

typedef unsigned int sp_io_object_t;
typedef int sp_kern_return_t;

static void *sp_real_iokit(const char *sym) {
    static void *h;
    if (!h) h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_NOLOAD);
    void *p = h ? dlsym(h, sym) : NULL;
    if (!p) {
        char buf[96];
        snprintf(buf, sizeof buf, "no real %s", sym);
        sp_stub_log(buf);
    }
    return p;
}

#define SP_IO_REAL(type, name) \
    static __typeof__(type) fn; \
    if (!fn) fn = (type)sp_real_iokit(name)

static void sp_io_class(sp_io_object_t o, char *out, size_t len) {
    static sp_kern_return_t (*get)(sp_io_object_t, char *);
    if (!get) get = (sp_kern_return_t (*)(sp_io_object_t, char *))sp_real_iokit("IOObjectGetClass");
    char name[128] = "?";
    if (o == 0x7ffffff2) snprintf(name, sizeof name, "made-up en0");
    else if (o == 0x7ffffff3) snprintf(name, sizeof name, "made-up en0 controller");
    else if (!o || !get || get(o, name)) snprintf(name, sizeof name, o ? "?" : "none");
    snprintf(out, len, "%s", name);
}

// Made-up en0 (visionOS): an iterator, the interface and its controller, as port names no real
// object has (Mach port names are small indexes plus a generation). Only these four calls and the
// property/parent wrappers below know them.
enum { SP_FAKE_ITER = 0x7ffffff1, SP_FAKE_IF = 0x7ffffff2, SP_FAKE_CTRL = 0x7ffffff3 };
#define SP_FAKE(o) ((o) >= SP_FAKE_ITER && (o) <= SP_FAKE_CTRL)
static CFMutableDictionaryRef sp_ether_match;  // the client's IOServiceMatching("IOEthernetInterface")
static _Atomic int sp_fake_next;               // SP_FAKE_ITER: how many it has handed out

#if !TARGET_OS_OSX
static CFDataRef sp_fake_mac(void) {
    static CFDataRef mac;
    if (mac) return mac;
    CFStringRef key = CFSTR("spMadeUpMAC");
    CFTypeRef v = CFPreferencesCopyAppValue(key, kCFPreferencesCurrentApplication);
    if (v && CFGetTypeID(v) == CFDataGetTypeID() && CFDataGetLength(v) == 6) {
        mac = v;
    } else {
        if (v) CFRelease(v);
        uint8_t b[6];
        arc4random_buf(b, sizeof b);
        b[0] = (b[0] & 0xfc) | 0x02;  // unicast, locally administered
        mac = CFDataCreate(NULL, b, sizeof b);
        CFPreferencesSetAppValue(key, mac, kCFPreferencesCurrentApplication);
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
        sp_stub_log("ident: made up an en0 MAC for this install");
    }
    char line[80];
    snprintf(line, sizeof line, "ident: en0 MAC (made up) #%08x", sp_ihash(CFDataGetBytePtr(mac), 6));
    sp_stub_log(line);
    return mac;
}
#endif

static CFTypeRef sp_fake_property(sp_io_object_t e, CFStringRef key) {
#if !TARGET_OS_OSX
    if (e == SP_FAKE_IF && CFEqual(key, CFSTR("IOInterfaceNamePrefix"))) return CFRetain(CFSTR("en"));
    if (e == SP_FAKE_IF && CFEqual(key, CFSTR("IOInterfaceUnit"))) {
        int unit = 0;
        return CFNumberCreate(NULL, kCFNumberIntType, &unit);
    }
    if (e == SP_FAKE_CTRL && CFEqual(key, CFSTR("IOMACAddress"))) return CFRetain(sp_fake_mac());
#endif
    return NULL;
}

sp_io_object_t sp_IOIteratorNext(sp_io_object_t it) __asm__("_IOIteratorNext");
sp_io_object_t sp_IOIteratorNext(sp_io_object_t it) {
    SP_IO_REAL(sp_io_object_t (*)(sp_io_object_t), "IOIteratorNext");
    if (it == SP_FAKE_ITER) return atomic_fetch_add(&sp_fake_next, 1) == 0 ? SP_FAKE_IF : 0;
    return fn(it);
}

int sp_IOIteratorIsValid(sp_io_object_t it) __asm__("_IOIteratorIsValid");
int sp_IOIteratorIsValid(sp_io_object_t it) {
    SP_IO_REAL(int (*)(sp_io_object_t), "IOIteratorIsValid");
    return it == SP_FAKE_ITER ? 1 : fn(it);
}

sp_kern_return_t sp_IOObjectRelease(sp_io_object_t o) __asm__("_IOObjectRelease");
sp_kern_return_t sp_IOObjectRelease(sp_io_object_t o) {
    SP_IO_REAL(sp_kern_return_t (*)(sp_io_object_t), "IOObjectRelease");
    return SP_FAKE(o) ? 0 : fn(o);
}

sp_kern_return_t sp_IOObjectRetain(sp_io_object_t o) __asm__("_IOObjectRetain");
sp_kern_return_t sp_IOObjectRetain(sp_io_object_t o) {
    SP_IO_REAL(sp_kern_return_t (*)(sp_io_object_t), "IOObjectRetain");
    return SP_FAKE(o) ? 0 : fn(o);
}

int sp_IOObjectIsEqualTo(sp_io_object_t a, sp_io_object_t b) __asm__("_IOObjectIsEqualTo");
int sp_IOObjectIsEqualTo(sp_io_object_t a, sp_io_object_t b) {
    SP_IO_REAL(int (*)(sp_io_object_t, sp_io_object_t), "IOObjectIsEqualTo");
    return SP_FAKE(a) || SP_FAKE(b) ? a == b : fn(a, b);
}

CFMutableDictionaryRef sp_IOServiceMatching(const char *name) __asm__("_IOServiceMatching");
CFMutableDictionaryRef sp_IOServiceMatching(const char *name) {
    SP_IO_REAL(CFMutableDictionaryRef (*)(const char *), "IOServiceMatching");
    CFMutableDictionaryRef r = fn(name);
    if (name && !strcmp(name, "IOEthernetInterface")) sp_ether_match = r;
    SP_ID_LOG(100, "ident: IOServiceMatching(\"%s\") from +0x%lx", name ? name : "", SP_CALLER);
    return r;
}

sp_io_object_t sp_IOServiceGetMatchingService(unsigned port, CFDictionaryRef m) __asm__("_IOServiceGetMatchingService");
sp_io_object_t sp_IOServiceGetMatchingService(unsigned port, CFDictionaryRef m) {
    SP_IO_REAL(sp_io_object_t (*)(unsigned, CFDictionaryRef), "IOServiceGetMatchingService");
    sp_io_object_t r = fn(port, m);  // consumes m
    char c[128];
    sp_io_class(r, c, sizeof c);
    SP_ID_LOG(100, "ident: IOServiceGetMatchingService() = %s from +0x%lx", c, SP_CALLER);
    return r;
}

sp_kern_return_t sp_IOServiceGetMatchingServices(unsigned port, CFDictionaryRef m, sp_io_object_t *it)
    __asm__("_IOServiceGetMatchingServices");
sp_kern_return_t sp_IOServiceGetMatchingServices(unsigned port, CFDictionaryRef m, sp_io_object_t *it) {
    SP_IO_REAL(sp_kern_return_t (*)(unsigned, CFDictionaryRef, sp_io_object_t *), "IOServiceGetMatchingServices");
#if !TARGET_OS_OSX
    if (m && m == sp_ether_match && it) {
        sp_ether_match = NULL;
        CFRelease(m);  // consumed, as the real call would
        *it = SP_FAKE_ITER;
        atomic_store(&sp_fake_next, 0);
        SP_ID_LOG(100, "ident: IOServiceGetMatchingServices(IOEthernetInterface) = made-up en0 from +0x%lx", SP_CALLER);
        return 0;
    }
#endif
    sp_kern_return_t r = fn(port, m, it);
    SP_ID_LOG(100, "ident: IOServiceGetMatchingServices() = 0x%x from +0x%lx", r, SP_CALLER);
    return r;
}

CFTypeRef sp_IORegistryEntryCreateCFProperty(sp_io_object_t e, CFStringRef key, CFAllocatorRef a, unsigned opts)
    __asm__("_IORegistryEntryCreateCFProperty");
CFTypeRef sp_IORegistryEntryCreateCFProperty(sp_io_object_t e, CFStringRef key, CFAllocatorRef a, unsigned opts) {
    SP_IO_REAL(CFTypeRef (*)(sp_io_object_t, CFStringRef, CFAllocatorRef, unsigned), "IORegistryEntryCreateCFProperty");
    CFTypeRef r = SP_FAKE(e) ? sp_fake_property(e, key) : fn(e, key, a, opts);
    char c[128], k[128], v[96];
    sp_io_class(e, c, sizeof c);
    sp_cf_cstr(key, k, sizeof k);
    sp_cf_desc(r, v, sizeof v);
    SP_ID_LOG(300, "ident: IORegistryEntryCreateCFProperty(%s, \"%s\") = %s from +0x%lx", c, k, v, SP_CALLER);
    return r;
}

sp_kern_return_t sp_IORegistryEntryCreateCFProperties(sp_io_object_t e, CFMutableDictionaryRef *d, CFAllocatorRef a,
                                                      unsigned opts) __asm__("_IORegistryEntryCreateCFProperties");
sp_kern_return_t sp_IORegistryEntryCreateCFProperties(sp_io_object_t e, CFMutableDictionaryRef *d, CFAllocatorRef a,
                                                      unsigned opts) {
    SP_IO_REAL(sp_kern_return_t (*)(sp_io_object_t, CFMutableDictionaryRef *, CFAllocatorRef, unsigned),
               "IORegistryEntryCreateCFProperties");
    sp_kern_return_t r = SP_FAKE(e) ? (*d = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                                                     &kCFTypeDictionaryValueCallBacks), 0)
                                   : fn(e, d, a, opts);
    static atomic_int logged;
    if (atomic_fetch_add(&logged, 1) < 40) {
        char c[128], line[200];
        sp_io_class(e, c, sizeof c);
        snprintf(line, sizeof line, "ident: IORegistryEntryCreateCFProperties(%s) = 0x%x, %ld keys from +0x%lx", c, r,
                 !r && d && *d ? (long)CFDictionaryGetCount(*d) : 0L, SP_CALLER);
        sp_stub_log(line);
        if (!r && d) sp_cf_dict_log("  ident:   ", *d);
    }
    return r;
}

CFTypeRef sp_IORegistryEntrySearchCFProperty(sp_io_object_t e, const char *plane, CFStringRef key, CFAllocatorRef a,
                                             unsigned opts) __asm__("_IORegistryEntrySearchCFProperty");
CFTypeRef sp_IORegistryEntrySearchCFProperty(sp_io_object_t e, const char *plane, CFStringRef key, CFAllocatorRef a,
                                             unsigned opts) {
    SP_IO_REAL(CFTypeRef (*)(sp_io_object_t, const char *, CFStringRef, CFAllocatorRef, unsigned),
               "IORegistryEntrySearchCFProperty");
    CFTypeRef r = SP_FAKE(e) ? sp_fake_property(e, key) : fn(e, plane, key, a, opts);
    char c[128], k[128], v[96];
    sp_io_class(e, c, sizeof c);
    sp_cf_cstr(key, k, sizeof k);
    sp_cf_desc(r, v, sizeof v);
    SP_ID_LOG(300, "ident: IORegistryEntrySearchCFProperty(%s, %s, \"%s\", opts 0x%x) = %s from +0x%lx", c,
              plane ? plane : "", k, opts, v, SP_CALLER);
    return r;
}

sp_kern_return_t sp_IORegistryEntryGetRegistryEntryID(sp_io_object_t e, unsigned long long *id)
    __asm__("_IORegistryEntryGetRegistryEntryID");
sp_kern_return_t sp_IORegistryEntryGetRegistryEntryID(sp_io_object_t e, unsigned long long *id) {
    SP_IO_REAL(sp_kern_return_t (*)(sp_io_object_t, unsigned long long *), "IORegistryEntryGetRegistryEntryID");
    sp_kern_return_t r = SP_FAKE(e) ? (*id = e, 0) : fn(e, id);
    char c[128];
    sp_io_class(e, c, sizeof c);
    SP_ID_LOG(100, "ident: IORegistryEntryGetRegistryEntryID(%s) = 0x%x from +0x%lx", c, r, SP_CALLER);
    return r;
}

sp_kern_return_t sp_IORegistryEntryGetParentEntry(sp_io_object_t e, const char *plane, sp_io_object_t *p)
    __asm__("_IORegistryEntryGetParentEntry");
sp_kern_return_t sp_IORegistryEntryGetParentEntry(sp_io_object_t e, const char *plane, sp_io_object_t *p) {
    SP_IO_REAL(sp_kern_return_t (*)(sp_io_object_t, const char *, sp_io_object_t *), "IORegistryEntryGetParentEntry");
    sp_kern_return_t r;
    if (e == SP_FAKE_IF) *p = SP_FAKE_CTRL, r = 0;
    else if (SP_FAKE(e)) r = 0xe00002c0;  // kIOReturnNotFound
    else r = fn(e, plane, p);
    char c[128], pc[128];
    sp_io_class(e, c, sizeof c);
    sp_io_class(!r && p ? *p : 0, pc, sizeof pc);
    SP_ID_LOG(100, "ident: IORegistryEntryGetParentEntry(%s, %s) = %s from +0x%lx", c, plane ? plane : "", pc,
              SP_CALLER);
    return r;
}

CFTypeRef sp_IOPSCopyPowerSourcesInfo(void) __asm__("_IOPSCopyPowerSourcesInfo");
CFTypeRef sp_IOPSCopyPowerSourcesInfo(void) {
    SP_IO_REAL(CFTypeRef (*)(void), "IOPSCopyPowerSourcesInfo");
    CFTypeRef r = fn();
    SP_ID_LOG(20, "ident: IOPSCopyPowerSourcesInfo() = %s from +0x%lx", r ? "info" : "NULL", SP_CALLER);
    return r;
}
