// Secure Transport and SecTrust, logged on their way to the real Security framework. #included at the
// end of the generated libspSecurity.m (gen_stubs.py EXTRA_INCLUDES, FORCE_SHIM); a function here with
// __asm__("_symbol") wins over the shim's re-export of Security. The client's Battle.net login runs
// TLS through these, so this shows where the headset's connection fails.
#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <mach-o/dyld.h>
#include <TargetConditionals.h>

static void *sp_real_sec(const char *sym) {
    static void *h;
    if (!h) h = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY | RTLD_NOLOAD);
    void *p = h ? dlsym(h, sym) : NULL;
    if (!p) {
        char buf[96];
        snprintf(buf, sizeof buf, "no real %s", sym);
        sp_stub_log(buf);
    }
    return p;
}

#define SP_SEC_REAL(type, name) \
    static __typeof__(type) fn; \
    if (!fn) fn = (type)sp_real_sec(name)

// At most `limit` lines per call site.
#define SP_SEC_LOG(limit, ...) do { \
    static atomic_int sp_logged_; \
    if (atomic_fetch_add(&sp_logged_, 1) < (limit)) { \
        char buf[256]; \
        snprintf(buf, sizeof buf, __VA_ARGS__); \
        sp_stub_log(buf); \
    } \
} while (0)

typedef void *SPSSL;

SPSSL sp_SSLCreateContext(CFAllocatorRef a, int side, int type) __asm__("_SSLCreateContext");
SPSSL sp_SSLCreateContext(CFAllocatorRef a, int side, int type) {
    SP_SEC_REAL(SPSSL (*)(CFAllocatorRef, int, int), "SSLCreateContext");
    SPSSL r = fn(a, side, type);
    SP_SEC_LOG(20, "SSLCreateContext(side %d, type %d) = %p from +0x%lx", side, type, r, SP_CALLER);
    return r;
}

int32_t sp_SSLSetPeerDomainName(SPSSL c, const char *name, size_t len) __asm__("_SSLSetPeerDomainName");
int32_t sp_SSLSetPeerDomainName(SPSSL c, const char *name, size_t len) {
    SP_SEC_REAL(int32_t (*)(SPSSL, const char *, size_t), "SSLSetPeerDomainName");
    int32_t r = fn(c, name, len);
    SP_SEC_LOG(20, "SSLSetPeerDomainName(%p, \"%.*s\") = %d", c, (int)len, name ?: "", r);
    return r;
}

int32_t sp_SSLSetProtocolVersionMin(SPSSL c, int v) __asm__("_SSLSetProtocolVersionMin");
int32_t sp_SSLSetProtocolVersionMin(SPSSL c, int v) {
    SP_SEC_REAL(int32_t (*)(SPSSL, int), "SSLSetProtocolVersionMin");
    int32_t r = fn(c, v);
    SP_SEC_LOG(20, "SSLSetProtocolVersionMin(%p, %d) = %d", c, v, r);
    return r;
}

int32_t sp_SSLSetProtocolVersionMax(SPSSL c, int v) __asm__("_SSLSetProtocolVersionMax");
int32_t sp_SSLSetProtocolVersionMax(SPSSL c, int v) {
    SP_SEC_REAL(int32_t (*)(SPSSL, int), "SSLSetProtocolVersionMax");
    int32_t r = fn(c, v);
    SP_SEC_LOG(20, "SSLSetProtocolVersionMax(%p, %d) = %d", c, v, r);
    return r;
}

int32_t sp_SSLSetSessionOption(SPSSL c, int opt, Boolean v) __asm__("_SSLSetSessionOption");
int32_t sp_SSLSetSessionOption(SPSSL c, int opt, Boolean v) {
    SP_SEC_REAL(int32_t (*)(SPSSL, int, Boolean), "SSLSetSessionOption");
    int32_t r = fn(c, opt, v);
    SP_SEC_LOG(20, "SSLSetSessionOption(%p, %d, %d) = %d", c, opt, v, r);
    return r;
}

int32_t sp_SSLSetEnabledCiphers(SPSSL c, const uint16_t *ciphers, size_t n) __asm__("_SSLSetEnabledCiphers");
int32_t sp_SSLSetEnabledCiphers(SPSSL c, const uint16_t *ciphers, size_t n) {
    SP_SEC_REAL(int32_t (*)(SPSSL, const uint16_t *, size_t), "SSLSetEnabledCiphers");
    int32_t r = fn(c, ciphers, n);
    SP_SEC_LOG(20, "SSLSetEnabledCiphers(%p, %zu ciphers, first 0x%x) = %d", c, n, n ? (unsigned)ciphers[0] : 0u, r);
    return r;
}

int32_t sp_SSLSetALPNProtocols(SPSSL c, CFArrayRef protocols) __asm__("_SSLSetALPNProtocols");
int32_t sp_SSLSetALPNProtocols(SPSSL c, CFArrayRef protocols) {
    SP_SEC_REAL(int32_t (*)(SPSSL, CFArrayRef), "SSLSetALPNProtocols");
    int32_t r = fn(c, protocols);
    SP_SEC_LOG(20, "SSLSetALPNProtocols(%p, %s) = %d", c,
               [[(__bridge NSArray *)protocols componentsJoinedByString:@","] UTF8String] ?: "(null)", r);
    return r;
}

int32_t sp_SSLSetCertificate(SPSSL c, CFArrayRef certs) __asm__("_SSLSetCertificate");
int32_t sp_SSLSetCertificate(SPSSL c, CFArrayRef certs) {
    SP_SEC_REAL(int32_t (*)(SPSSL, CFArrayRef), "SSLSetCertificate");
    int32_t r = fn(c, certs);
    SP_SEC_LOG(20, "SSLSetCertificate(%p, %ld items) = %d", c, certs ? (long)CFArrayGetCount(certs) : -1L, r);
    return r;
}

// Every handshake step's result (errSSLWouldBlock -9803 repeats while waiting), up to a limit.
int32_t sp_SSLHandshake(SPSSL c) __asm__("_SSLHandshake");
int32_t sp_SSLHandshake(SPSSL c) {
    SP_SEC_REAL(int32_t (*)(SPSSL), "SSLHandshake");
    int32_t r = fn(c);
    SP_SEC_LOG(200, "SSLHandshake(%p) = %d", c, r);
    return r;
}

int32_t sp_SSLCopyPeerTrust(SPSSL c, void **trust) __asm__("_SSLCopyPeerTrust");
int32_t sp_SSLCopyPeerTrust(SPSSL c, void **trust) {
    SP_SEC_REAL(int32_t (*)(SPSSL, void **), "SSLCopyPeerTrust");
    int32_t r = fn(c, trust);
    SP_SEC_LOG(20, "SSLCopyPeerTrust(%p) = %d, trust %p", c, r, trust ? *trust : NULL);
    return r;
}

int32_t sp_SSLRead(SPSSL c, void *data, size_t len, size_t *done) __asm__("_SSLRead");
int32_t sp_SSLRead(SPSSL c, void *data, size_t len, size_t *done) {
    SP_SEC_REAL(int32_t (*)(SPSSL, void *, size_t, size_t *), "SSLRead");
    int32_t r = fn(c, data, len, done);
    if (r && r != -9803) SP_SEC_LOG(40, "SSLRead(%p, %zu) = %d, %zu read", c, len, r, done ? *done : 0);
    return r;
}

int32_t sp_SSLWrite(SPSSL c, const void *data, size_t len, size_t *done) __asm__("_SSLWrite");
int32_t sp_SSLWrite(SPSSL c, const void *data, size_t len, size_t *done) {
    SP_SEC_REAL(int32_t (*)(SPSSL, const void *, size_t, size_t *), "SSLWrite");
    int32_t r = fn(c, data, len, done);
    if (r && r != -9803) SP_SEC_LOG(40, "SSLWrite(%p, %zu) = %d, %zu written", c, len, r, done ? *done : 0);
    return r;
}

int32_t sp_SSLClose(SPSSL c) __asm__("_SSLClose");
int32_t sp_SSLClose(SPSSL c) {
    SP_SEC_REAL(int32_t (*)(SPSSL), "SSLClose");
    int32_t r = fn(c);
    SP_SEC_LOG(20, "SSLClose(%p) = %d from +0x%lx", c, r, SP_CALLER);
    return r;
}

int32_t sp_SecTrustSetAnchorCertificates(void *t, CFArrayRef certs) __asm__("_SecTrustSetAnchorCertificates");
int32_t sp_SecTrustSetAnchorCertificates(void *t, CFArrayRef certs) {
    SP_SEC_REAL(int32_t (*)(void *, CFArrayRef), "SecTrustSetAnchorCertificates");
    int32_t r = fn(t, certs);
    SP_SEC_LOG(20, "SecTrustSetAnchorCertificates(%p, %ld certs) = %d", t, certs ? (long)CFArrayGetCount(certs) : -1L, r);
    return r;
}

int32_t sp_SecTrustSetAnchorCertificatesOnly(void *t, Boolean only) __asm__("_SecTrustSetAnchorCertificatesOnly");
int32_t sp_SecTrustSetAnchorCertificatesOnly(void *t, Boolean only) {
    SP_SEC_REAL(int32_t (*)(void *, Boolean), "SecTrustSetAnchorCertificatesOnly");
    int32_t r = fn(t, only);
    SP_SEC_LOG(20, "SecTrustSetAnchorCertificatesOnly(%p, %d) = %d", t, only, r);
    return r;
}

int32_t sp_SecTrustEvaluate(void *t, uint32_t *result) __asm__("_SecTrustEvaluate");
int32_t sp_SecTrustEvaluate(void *t, uint32_t *result) {
    SP_SEC_REAL(int32_t (*)(void *, uint32_t *), "SecTrustEvaluate");
    int32_t r = fn(t, result);
    SP_SEC_LOG(20, "SecTrustEvaluate(%p) = %d, result %u", t, r, result ? *result : 0);
    return r;
}

bool sp_SecTrustEvaluateWithError(void *t, CFErrorRef *error) __asm__("_SecTrustEvaluateWithError");
bool sp_SecTrustEvaluateWithError(void *t, CFErrorRef *error) {
    SP_SEC_REAL(bool (*)(void *, CFErrorRef *), "SecTrustEvaluateWithError");
    bool r = fn(t, error);
    SP_SEC_LOG(20, "SecTrustEvaluateWithError(%p) = %d %s", t, r,
               !r && error && *error ? [[(__bridge NSError *)*error description] UTF8String] : "");
    return r;
}

// Keychain and certificate calls the client might make to find trusted roots (on visionOS an app
// sees only its own keychain).
static const char *sp_cf_desc(CFTypeRef o) {
    if (!o) return "(null)";
    NSString *d = [(__bridge id)o description];
    return [[d stringByReplacingOccurrencesOfString:@"\n" withString:@" "] UTF8String] ?: "?";
}

// Apple's root CAs, exported from the Mac's SystemRootCertificates.keychain into the app bundle by
// apps/client/build.sh (sproots.plist, an array of DER data).
static NSArray *sp_roots(void) {
    static NSArray *roots;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *a = [NSMutableArray array];
        NSString *path = [NSBundle.mainBundle pathForResource:@"sproots" ofType:@"plist"];
        for (NSData *der in [NSArray arrayWithContentsOfFile:path]) {
            SecCertificateRef c = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)der);
            if (c) [a addObject:CFBridgingRelease(c)];
        }
        roots = a;
        SP_SEC_LOG(1, "loaded %lu root certificates from %s", (unsigned long)a.count, path.UTF8String ?: "(no sproots.plist)");
    });
    return roots;
}

// The client builds its own trust store at startup from a certificate query (and, failing that, the
// macOS SystemRootCertificates.keychain via SecKeychainOpen). Neither finds anything on visionOS, where
// an app's keychain holds only its own items, and the client's TLS then rejects Battle.net's
// certificate. A certificate query that finds nothing gets the bundled roots instead.
int32_t sp_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) __asm__("_SecItemCopyMatching");
int32_t sp_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    SP_SEC_REAL(int32_t (*)(CFDictionaryRef, CFTypeRef *), "SecItemCopyMatching");
    int32_t r = fn(query, result);
    NSDictionary *q = (__bridge NSDictionary *)query;
    if (r == errSecItemNotFound && [q[(__bridge id)kSecClass] isEqual:(__bridge id)kSecClassCertificate] && result) {
        BOOL all = [q[(__bridge id)kSecMatchLimit] isEqual:(__bridge id)kSecMatchLimitAll];
        BOOL data = [q[(__bridge id)kSecReturnData] boolValue], ref = [q[(__bridge id)kSecReturnRef] boolValue];
        BOOL attrs = [q[(__bridge id)kSecReturnAttributes] boolValue];
        NSArray *roots = sp_roots();
        if (roots.count && !attrs && data != ref) {
            NSMutableArray *out = [NSMutableArray array];
            for (id c in roots)
                [out addObject:data ? CFBridgingRelease(SecCertificateCopyData((__bridge SecCertificateRef)c)) : c];
            *result = CFBridgingRetain(all ? out : out[0]);
            r = 0;
        }
        SP_SEC_LOG(20, "SecItemCopyMatching(certificates, all %d, data %d, ref %d, attributes %d): %s from +0x%lx", all,
                   data, ref, attrs, r ? "not found (left as is)" : "answered with the bundled roots", SP_CALLER);
        return r;
    }
    long count = result && *result && CFGetTypeID(*result) == CFArrayGetTypeID() ? (long)CFArrayGetCount(*result) : -1;
    SP_SEC_LOG(20, "SecItemCopyMatching(%.200s) = %d, %ld results, from +0x%lx", sp_cf_desc(query), r, count, SP_CALLER);
    return r;
}

void *sp_SecCertificateCreateWithData(CFAllocatorRef a, CFDataRef data) __asm__("_SecCertificateCreateWithData");
void *sp_SecCertificateCreateWithData(CFAllocatorRef a, CFDataRef data) {
    SP_SEC_REAL(void *(*)(CFAllocatorRef, CFDataRef), "SecCertificateCreateWithData");
    void *r = fn(a, data);
    SP_SEC_LOG(20, "SecCertificateCreateWithData(%ld bytes) = %p from +0x%lx", data ? (long)CFDataGetLength(data) : -1L, r, SP_CALLER);
    return r;
}

int32_t sp_SecTrustCreateWithCertificates(CFTypeRef certs, CFTypeRef policies, void **trust) __asm__("_SecTrustCreateWithCertificates");
int32_t sp_SecTrustCreateWithCertificates(CFTypeRef certs, CFTypeRef policies, void **trust) {
    SP_SEC_REAL(int32_t (*)(CFTypeRef, CFTypeRef, void **), "SecTrustCreateWithCertificates");
    int32_t r = fn(certs, policies, trust);
    SP_SEC_LOG(20, "SecTrustCreateWithCertificates() = %d from +0x%lx", r, SP_CALLER);
    return r;
}

void *sp_SecPolicyCreateSSL(Boolean server, CFStringRef host) __asm__("_SecPolicyCreateSSL");
void *sp_SecPolicyCreateSSL(Boolean server, CFStringRef host) {
    SP_SEC_REAL(void *(*)(Boolean, CFStringRef), "SecPolicyCreateSSL");
    void *r = fn(server, host);
    SP_SEC_LOG(20, "SecPolicyCreateSSL(%d, %s) from +0x%lx", server, sp_cf_desc(host), SP_CALLER);
    return r;
}

CFDataRef sp_SecCertificateCopyData(void *cert) __asm__("_SecCertificateCopyData");
CFDataRef sp_SecCertificateCopyData(void *cert) {
    SP_SEC_REAL(CFDataRef (*)(void *), "SecCertificateCopyData");
    CFDataRef r = fn(cert);
    SP_SEC_LOG(10, "SecCertificateCopyData(%p) = %ld bytes from +0x%lx", cert, r ? (long)CFDataGetLength(r) : -1L, SP_CALLER);
    return r;
}

// SecKeychainOpen is a macOS-only Security API. On visionOS it doesn't exist, so the shim provides it
// and hands back no keychain (there are no keychain files there, and the bundled-roots path in
// SecItemCopyMatching covers trust instead). On the Mac test the real API exists and the client's bnet
// OpenSSL builds its trust store from the real SystemRootCertificates.keychain -- denying it there makes
// the bnet TLS handshake fail (Front disconnected result=3) before login runs -- so on macOS forward to
// the real call and leave native trust intact.
int32_t sp_SecKeychainOpen(const char *path, void **keychain) __asm__("_SecKeychainOpen");
int32_t sp_SecKeychainOpen(const char *path, void **keychain) {
#if TARGET_OS_OSX
    int32_t (*fn)(const char *, void **) = sp_real_sec("SecKeychainOpen");
    if (fn) {
        int32_t r = fn(path, keychain);
        SP_SEC_LOG(20, "SecKeychainOpen(\"%s\") = %d (real), from +0x%lx", path ?: "(null)", r, SP_CALLER);
        return r;
    }
#endif
    SP_SEC_LOG(20, "SecKeychainOpen(\"%s\") -> no keychain, from +0x%lx", path ?: "(null)", SP_CALLER);
    if (keychain) *keychain = NULL;
    return 0;
}
