// DiskArbitration, logged on its way to the real framework (Mac probe only: visionOS has no
// DiskArbitration, and the generated shim's stubs return NULL there, logging once each).
// Descriptions are logged key by key as type, size and hash (spident.h).
#include "spident.h"

static void *sp_real_da(const char *sym) {
    static void *h;
    if (!h) h = dlopen("/System/Library/Frameworks/DiskArbitration.framework/DiskArbitration", RTLD_LAZY | RTLD_NOLOAD);
    return h ? dlsym(h, sym) : NULL;
}

#define SP_DA_REAL(type, name) \
    static __typeof__(type) fn; \
    if (!fn) fn = (type)sp_real_da(name)

CFTypeRef sp_DASessionCreate(CFAllocatorRef a) __asm__("_DASessionCreate");
CFTypeRef sp_DASessionCreate(CFAllocatorRef a) {
    SP_DA_REAL(CFTypeRef (*)(CFAllocatorRef), "DASessionCreate");
    CFTypeRef r = fn(a);
    SP_ID_LOG(20, "ident: DASessionCreate() = %s from +0x%lx", r ? "session" : "NULL", SP_CALLER);
    return r;
}

CFTypeRef sp_DADiskCreateFromVolumePath(CFAllocatorRef a, CFTypeRef s, CFURLRef path) __asm__("_DADiskCreateFromVolumePath");
CFTypeRef sp_DADiskCreateFromVolumePath(CFAllocatorRef a, CFTypeRef s, CFURLRef path) {
    SP_DA_REAL(CFTypeRef (*)(CFAllocatorRef, CFTypeRef, CFURLRef), "DADiskCreateFromVolumePath");
    CFTypeRef r = fn(a, s, path);
    char p[512] = "";
    if (path) CFURLGetFileSystemRepresentation(path, true, (UInt8 *)p, sizeof p);
    SP_ID_LOG(20, "ident: DADiskCreateFromVolumePath(\"%s\") = %s from +0x%lx", p, r ? "disk" : "NULL", SP_CALLER);
    return r;
}

CFDictionaryRef sp_DADiskCopyDescription(CFTypeRef disk) __asm__("_DADiskCopyDescription");
CFDictionaryRef sp_DADiskCopyDescription(CFTypeRef disk) {
    SP_DA_REAL(CFDictionaryRef (*)(CFTypeRef), "DADiskCopyDescription");
    CFDictionaryRef r = fn(disk);
    static atomic_int logged;
    if (atomic_fetch_add(&logged, 1) < 20) {
        char line[120];
        snprintf(line, sizeof line, "ident: DADiskCopyDescription() = %ld keys from +0x%lx",
                 r ? (long)CFDictionaryGetCount(r) : -1L, SP_CALLER);
        sp_stub_log(line);
        sp_cf_dict_log("  ident:   ", r);
    }
    return r;
}

unsigned sp_DADiskCopyIOMedia(CFTypeRef disk) __asm__("_DADiskCopyIOMedia");
unsigned sp_DADiskCopyIOMedia(CFTypeRef disk) {
    SP_DA_REAL(unsigned (*)(CFTypeRef), "DADiskCopyIOMedia");
    unsigned r = fn(disk);
    SP_ID_LOG(20, "ident: DADiskCopyIOMedia() = %s from +0x%lx", r ? "media" : "none", SP_CALLER);
    return r;
}
