// Shared by the CoreAudio and AudioToolbox shims (#included into each generated shim, after its
// header). Passes calls through to the real visionOS library and logs them.
#include <dlfcn.h>

typedef int32_t SPStatus;

// The sample rate the client is told its device (and output unit) runs at, as a Mac's built-in output.
// RemoteIO converts to the hardware rate (48 kHz).
#define SP_CLIENT_RATE 44100

// The real function from the system framework, bypassing this shim's own export of the same name.
static void *sp_real(const char *framework, const char *sym) {
    void *h = dlopen(framework, RTLD_LAZY | RTLD_NOLOAD) ?: dlopen(framework, RTLD_LAZY);
    void *p = h ? dlsym(h, sym) : NULL;
    if (!p) {
        char buf[160];
        snprintf(buf, sizeof buf, "no real %s in %s", sym, framework);
        sp_stub_log(buf);
    }
    return p;
}

// 'abcd' as text; non-printable codes as hex.
static const char *sp_fourcc(uint32_t c, char out[12]) {
    char s[4] = {(char)(c >> 24), (char)(c >> 16), (char)(c >> 8), (char)c};
    for (int i = 0; i < 4; i++)
        if (s[i] < 32 || s[i] > 126) { snprintf(out, 12, "0x%x", c); return out; }
    snprintf(out, 12, "'%.4s'", s);
    return out;
}

// Log at most `limit` lines per call site.
#define SP_LOGF(limit, ...) do { \
    static atomic_int n; \
    if (atomic_fetch_add(&n, 1) < (limit)) { \
        char buf[256]; \
        snprintf(buf, sizeof buf, __VA_ARGS__); \
        sp_stub_log(buf); \
    } \
} while (0)

// The first bytes of a property value, as u32s, for the log.
static const char *sp_hex(const void *p, uint32_t size, char out[64]) {
    out[0] = 0;
    if (!p) return out;
    size_t len = 0;
    for (uint32_t i = 0; i + 4 <= size && i < 24; i += 4)
        len += snprintf(out + len, 64 - len, "%s%x", i ? " " : "", ((const uint32_t *)p)[i / 4]);
    return out;
}
