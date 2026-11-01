// CSSM, which visionOS doesn't have, over CommonCrypto: the subset the client imports. The client's
// Battle.net launcher login (-launcherlogin) needs it, and with the generated stubs (CSSM_OK, nothing
// filled in) it silently falls back to the password form.
// Follows the documented CDSA semantics; layouts and constants are the macOS SDK's (cssmtype.h), with
// 64-bit CSSM_SIZE. Logs algorithms and sizes, and short SHA-256 prefixes of inputs so runs can be
// compared; never key material.
#include <CommonCrypto/CommonCrypto.h>
#include <CommonCrypto/CommonKeyDerivation.h>
#include <os/lock.h>

typedef int32_t SP_CSSM_RETURN;
typedef intptr_t SP_CSSM_HANDLE;  // CSSM_INTPTR

typedef struct {
    size_t Length;
    uint8_t *Data;
} SP_CSSM_DATA;

typedef struct {
    void *(*malloc_func)(size_t, void *);
    void (*free_func)(void *, void *);
    void *(*realloc_func)(void *, size_t, void *);
    void *(*calloc_func)(uint32_t, size_t, void *);
    void *AllocRef;
} SP_CSSM_MEMORY_FUNCS;

typedef struct {
    uint32_t HeaderVersion;
    uint8_t CspId[16];
    uint32_t BlobType, Format, AlgorithmId, KeyClass, LogicalKeySizeInBits, KeyAttr, KeyUsage;
    uint8_t StartDate[8], EndDate[8];
    uint32_t WrapAlgorithmId, WrapMode, Reserved;
} SP_CSSM_KEYHEADER;  // 76 bytes

typedef struct {
    SP_CSSM_KEYHEADER KeyHeader;
    SP_CSSM_DATA KeyData;  // at 80
} SP_CSSM_KEY;

typedef struct {
    SP_CSSM_DATA Passphrase;
    uint32_t PseudoRandomFunction;  // 0: HMAC-SHA1, the only one CSSM defines
} SP_CSSM_PKCS5_PBKDF2_PARAMS;

_Static_assert(sizeof(SP_CSSM_KEYHEADER) == 76 && sizeof(SP_CSSM_KEY) == 96, "CSSM_KEY layout");
_Static_assert(sizeof(SP_CSSM_PKCS5_PBKDF2_PARAMS) == 24, "CSSM_PKCS5_PBKDF2_PARAMS layout");

enum {
    SP_ALGID_DES = 0xe, SP_ALGID_3DES_3KEY_EDE = 0x11, SP_ALGID_PKCS5_PBKDF2 = 0x67, SP_ALGID_AES = 0x80000001,
    SP_ALGMODE_ECB = 2, SP_ALGMODE_CBC = 4, SP_ALGMODE_CBC_IV8 = 5, SP_ALGMODE_CBCPadIV8 = 6,
    SP_PADDING_NONE = 0, SP_PADDING_PKCS5 = 6, SP_PADDING_PKCS7 = 7,
    SP_KEYHEADER_VERSION = 2, SP_KEYCLASS_SESSION_KEY = 2, SP_KEYBLOB_RAW_FORMAT_OCTET_STRING = 12,
    SP_KEYATTR_RETURN_BITS = 0xf0000000,  // CSSM_KEYATTR_RETURN_*: requests, not attributes of the key
};
#define SPERR_INVALID_ALGORITHM ((SP_CSSM_RETURN)0x80010931)
#define SPERR_INVALID_CONTEXT_HANDLE ((SP_CSSM_RETURN)0x80010840)
#define SPERR_OUTPUT_LENGTH_ERROR ((SP_CSSM_RETURN)0x80010902)
#define SPERR_INVALID_DATA ((SP_CSSM_RETURN)0x80010846)
#define SPERR_FUNCTION_NOT_IMPLEMENTED ((SP_CSSM_RETURN)0x80010807)
#define SPERR_MEMORY_ERROR ((SP_CSSM_RETURN)0x80010802)

static SP_CSSM_MEMORY_FUNCS sp_cssm_mem;  // from ModuleAttach; output buffers the caller frees

static void *sp_cssm_alloc(size_t n) {
    return sp_cssm_mem.malloc_func ? sp_cssm_mem.malloc_func(n, sp_cssm_mem.AllocRef) : malloc(n);
}

static void sp_cssm_free(void *p) {
    if (sp_cssm_mem.free_func) sp_cssm_mem.free_func(p, sp_cssm_mem.AllocRef);
    else free(p);
}

// First 4 bytes of SHA-256, as hex: identifies an input without revealing it.
static const char *sp_cssm_tag(const void *p, size_t n, char out[9]) {
    uint8_t h[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(p, (CC_LONG)n, h);
    snprintf(out, 9, "%02x%02x%02x%02x", h[0], h[1], h[2], h[3]);
    return out;
}

typedef struct {
    int used, derive;
    uint32_t alg, mode, padding, key_type, key_bits, iterations;
    uint8_t *salt, *key, *iv;
    size_t salt_len, key_len, iv_len;
} sp_cssm_ctx;

static sp_cssm_ctx sp_cssm_ctxs[32];
static os_unfair_lock sp_cssm_lock = OS_UNFAIR_LOCK_INIT;

static uint8_t *sp_cssm_dup(const SP_CSSM_DATA *d, size_t *len) {
    *len = d && d->Data ? d->Length : 0;
    if (!*len) return NULL;
    uint8_t *p = malloc(*len);
    memcpy(p, d->Data, *len);
    return p;
}

static SP_CSSM_RETURN sp_cssm_new(sp_cssm_ctx c, SP_CSSM_HANDLE *out) {
    os_unfair_lock_lock(&sp_cssm_lock);
    for (int i = 0; i < 32; i++)
        if (!sp_cssm_ctxs[i].used) {
            c.used = 1;
            sp_cssm_ctxs[i] = c;
            os_unfair_lock_unlock(&sp_cssm_lock);
            *out = i + 1;
            return 0;
        }
    os_unfair_lock_unlock(&sp_cssm_lock);
    return SPERR_MEMORY_ERROR;
}

static sp_cssm_ctx *sp_cssm_get(SP_CSSM_HANDLE h) {
    return h >= 1 && h <= 32 && sp_cssm_ctxs[h - 1].used ? &sp_cssm_ctxs[h - 1] : NULL;
}

SP_CSSM_RETURN sp_CSSM_Init(const void *version, uint32_t scope, const void *guid, uint32_t hierarchy,
                         uint32_t *pvc, const void *reserved) __asm__("_CSSM_Init");
SP_CSSM_RETURN sp_CSSM_Init(const void *version, uint32_t scope, const void *guid, uint32_t hierarchy,
                         uint32_t *pvc, const void *reserved) {
    SP_SEC_LOG(5, "CSSM_Init from +0x%lx", SP_CALLER);
    return 0;
}

SP_CSSM_RETURN sp_CSSM_ModuleLoad(const void *guid, uint32_t hierarchy, void *handler, void *ctx) __asm__("_CSSM_ModuleLoad");
SP_CSSM_RETURN sp_CSSM_ModuleLoad(const void *guid, uint32_t hierarchy, void *handler, void *ctx) {
    SP_SEC_LOG(5, "CSSM_ModuleLoad");
    return 0;
}

SP_CSSM_RETURN sp_CSSM_ModuleAttach(const void *guid, const void *version, const SP_CSSM_MEMORY_FUNCS *mem,
                                 uint32_t subservice, uint32_t type, uint32_t flags, uint32_t hierarchy,
                                 void *table, uint32_t ntable, const void *reserved, SP_CSSM_HANDLE *handle)
    __asm__("_CSSM_ModuleAttach");
SP_CSSM_RETURN sp_CSSM_ModuleAttach(const void *guid, const void *version, const SP_CSSM_MEMORY_FUNCS *mem,
                                 uint32_t subservice, uint32_t type, uint32_t flags, uint32_t hierarchy,
                                 void *table, uint32_t ntable, const void *reserved, SP_CSSM_HANDLE *handle) {
    if (mem) sp_cssm_mem = *mem;
    *handle = 1;
    SP_SEC_LOG(5, "CSSM_ModuleAttach(type 0x%x, memory funcs %s) = handle 1", type, mem ? "given" : "none");
    return 0;
}

SP_CSSM_RETURN sp_CSSM_ModuleDetach(SP_CSSM_HANDLE h) __asm__("_CSSM_ModuleDetach");
SP_CSSM_RETURN sp_CSSM_ModuleDetach(SP_CSSM_HANDLE h) {
    return 0;
}

SP_CSSM_RETURN sp_CSSM_CSP_CreateDeriveKeyContext(SP_CSSM_HANDLE csp, uint32_t alg, uint32_t key_type, uint32_t key_bits,
                                               const void *cred, const SP_CSSM_KEY *base, uint32_t iterations,
                                               const SP_CSSM_DATA *salt, const void *seed, SP_CSSM_HANDLE *out)
    __asm__("_CSSM_CSP_CreateDeriveKeyContext");
SP_CSSM_RETURN sp_CSSM_CSP_CreateDeriveKeyContext(SP_CSSM_HANDLE csp, uint32_t alg, uint32_t key_type, uint32_t key_bits,
                                               const void *cred, const SP_CSSM_KEY *base, uint32_t iterations,
                                               const SP_CSSM_DATA *salt, const void *seed, SP_CSSM_HANDLE *out) {
    sp_cssm_ctx c = {.derive = 1, .alg = alg, .key_type = key_type, .key_bits = key_bits, .iterations = iterations};
    c.salt = sp_cssm_dup(salt, &c.salt_len);
    char t[9] = "-";
    if (c.salt_len) sp_cssm_tag(c.salt, c.salt_len, t);
    SP_CSSM_RETURN r = sp_cssm_new(c, out);
    SP_SEC_LOG(10, "CSSM_CSP_CreateDeriveKeyContext(alg 0x%x, key type 0x%x, %u bits, %u iterations, salt %zu B #%s, "
               "base key %s, seed %s) = 0x%x from +0x%lx", alg, key_type, key_bits, iterations, c.salt_len, t,
               base ? "yes" : "no", seed ? "yes" : "no", r, SP_CALLER);
    return r;
}

SP_CSSM_RETURN sp_CSSM_DeriveKey(SP_CSSM_HANDLE cc, SP_CSSM_DATA *param, uint32_t usage, uint32_t attr, const SP_CSSM_DATA *label,
                              const void *acl, SP_CSSM_KEY *key) __asm__("_CSSM_DeriveKey");
SP_CSSM_RETURN sp_CSSM_DeriveKey(SP_CSSM_HANDLE cc, SP_CSSM_DATA *param, uint32_t usage, uint32_t attr, const SP_CSSM_DATA *label,
                              const void *acl, SP_CSSM_KEY *key) {
    sp_cssm_ctx *c = sp_cssm_get(cc);
    if (!c || !c->derive) return SPERR_INVALID_CONTEXT_HANDLE;
    if (c->alg != SP_ALGID_PKCS5_PBKDF2 || !param || !param->Data || param->Length < sizeof(SP_CSSM_PKCS5_PBKDF2_PARAMS)) {
        SP_SEC_LOG(10, "CSSM_DeriveKey: unsupported (alg 0x%x, param %zu B)", c->alg, param ? param->Length : 0);
        return SPERR_INVALID_ALGORITHM;
    }
    const SP_CSSM_PKCS5_PBKDF2_PARAMS *p = (const void *)param->Data;
    size_t n = (c->key_bits + 7) / 8;
    uint8_t *out = sp_cssm_alloc(n);
    if (!out) return SPERR_MEMORY_ERROR;
    int s = p->PseudoRandomFunction != 0 ? -1 :
        CCKeyDerivationPBKDF(kCCPBKDF2, (const char *)p->Passphrase.Data, p->Passphrase.Length, c->salt, c->salt_len,
                             kCCPRFHmacAlgSHA1, c->iterations, out, n);
    char tp[9], tk[9];
    sp_cssm_tag(p->Passphrase.Data, p->Passphrase.Length, tp);
    sp_cssm_tag(out, n, tk);
    SP_SEC_LOG(10, "CSSM_DeriveKey(PBKDF2, prf %u, passphrase %zu B #%s, usage 0x%x, attr 0x%x) -> %zu B key #%s, status %d",
               p->PseudoRandomFunction, p->Passphrase.Length, tp, usage, attr, n, tk, s);
    if (s) {
        sp_cssm_free(out);
        return SPERR_INVALID_ALGORITHM;
    }
    memset(key, 0, sizeof *key);
    key->KeyHeader.HeaderVersion = SP_KEYHEADER_VERSION;
    key->KeyHeader.Format = SP_KEYBLOB_RAW_FORMAT_OCTET_STRING;  // BlobType raw (0)
    key->KeyHeader.AlgorithmId = c->key_type;
    key->KeyHeader.KeyClass = SP_KEYCLASS_SESSION_KEY;
    key->KeyHeader.LogicalKeySizeInBits = c->key_bits;
    key->KeyHeader.KeyAttr = attr & ~SP_KEYATTR_RETURN_BITS;
    key->KeyHeader.KeyUsage = usage;
    key->KeyData.Data = out;
    key->KeyData.Length = n;
    return 0;
}

SP_CSSM_RETURN sp_CSSM_FreeKey(SP_CSSM_HANDLE csp, const void *cred, SP_CSSM_KEY *key, int del) __asm__("_CSSM_FreeKey");
SP_CSSM_RETURN sp_CSSM_FreeKey(SP_CSSM_HANDLE csp, const void *cred, SP_CSSM_KEY *key, int del) {
    if (key && key->KeyData.Data) {
        memset(key->KeyData.Data, 0, key->KeyData.Length);
        sp_cssm_free(key->KeyData.Data);
        key->KeyData.Data = NULL;
        key->KeyData.Length = 0;
    }
    return 0;
}

SP_CSSM_RETURN sp_CSSM_CSP_CreateSymmetricContext(SP_CSSM_HANDLE csp, uint32_t alg, uint32_t mode, const void *cred,
                                               const SP_CSSM_KEY *key, const SP_CSSM_DATA *iv, uint32_t padding,
                                               const void *reserved, SP_CSSM_HANDLE *out)
    __asm__("_CSSM_CSP_CreateSymmetricContext");
SP_CSSM_RETURN sp_CSSM_CSP_CreateSymmetricContext(SP_CSSM_HANDLE csp, uint32_t alg, uint32_t mode, const void *cred,
                                               const SP_CSSM_KEY *key, const SP_CSSM_DATA *iv, uint32_t padding,
                                               const void *reserved, SP_CSSM_HANDLE *out) {
    sp_cssm_ctx c = {.alg = alg, .mode = mode, .padding = padding};
    c.key = sp_cssm_dup(key ? &key->KeyData : NULL, &c.key_len);
    c.iv = sp_cssm_dup(iv, &c.iv_len);
    SP_CSSM_RETURN r = sp_cssm_new(c, out);
    SP_SEC_LOG(10, "CSSM_CSP_CreateSymmetricContext(alg 0x%x, mode %u, padding %u, key %zu B, iv %zu B) = 0x%x from +0x%lx",
               alg, mode, padding, c.key_len, c.iv_len, r, SP_CALLER);
    return r;
}

SP_CSSM_RETURN sp_CSSM_CSP_CreateAsymmetricContext(SP_CSSM_HANDLE csp, uint32_t alg, const void *cred, const SP_CSSM_KEY *key,
                                                uint32_t padding, SP_CSSM_HANDLE *out)
    __asm__("_CSSM_CSP_CreateAsymmetricContext");
SP_CSSM_RETURN sp_CSSM_CSP_CreateAsymmetricContext(SP_CSSM_HANDLE csp, uint32_t alg, const void *cred, const SP_CSSM_KEY *key,
                                                uint32_t padding, SP_CSSM_HANDLE *out) {
    SP_SEC_LOG(10, "CSSM_CSP_CreateAsymmetricContext(alg 0x%x, padding %u): not implemented, from +0x%lx", alg, padding,
               SP_CALLER);
    return SPERR_FUNCTION_NOT_IMPLEMENTED;
}

SP_CSSM_RETURN sp_CSSM_DeleteContext(SP_CSSM_HANDLE cc) __asm__("_CSSM_DeleteContext");
SP_CSSM_RETURN sp_CSSM_DeleteContext(SP_CSSM_HANDLE cc) {
    os_unfair_lock_lock(&sp_cssm_lock);
    sp_cssm_ctx *c = sp_cssm_get(cc);
    if (c) {
        if (c->key) memset(c->key, 0, c->key_len);
        free(c->salt);
        free(c->key);
        free(c->iv);
        memset(c, 0, sizeof *c);
    }
    os_unfair_lock_unlock(&sp_cssm_lock);
    return c ? 0 : SPERR_INVALID_CONTEXT_HANDLE;
}

// One-shot encrypt/decrypt of the concatenated input buffers into the first output buffer (allocated
// with the attach memory functions if its Data is NULL). Staged CSSM calls aren't imported.
static SP_CSSM_RETURN sp_cssm_crypt(CCOperation op, const char *name, SP_CSSM_HANDLE cc, const SP_CSSM_DATA *in, uint32_t nin,
                                 SP_CSSM_DATA *out, uint32_t nout, size_t *done, SP_CSSM_DATA *rem) {
    sp_cssm_ctx *c = sp_cssm_get(cc);
    if (!c || c->derive || !out || !nout) return SPERR_INVALID_CONTEXT_HANDLE;
    CCAlgorithm a;
    size_t block;
    switch (c->alg) {
    case SP_ALGID_AES: a = kCCAlgorithmAES; block = kCCBlockSizeAES128; break;
    case SP_ALGID_DES: a = kCCAlgorithmDES; block = kCCBlockSizeDES; break;
    case SP_ALGID_3DES_3KEY_EDE: a = kCCAlgorithm3DES; block = kCCBlockSize3DES; break;
    default:
        SP_SEC_LOG(10, "%s: unsupported alg 0x%x", name, c->alg);
        return SPERR_INVALID_ALGORITHM;
    }
    CCOptions o = 0;
    int padded = c->padding == SP_PADDING_PKCS5 || c->padding == SP_PADDING_PKCS7 || c->mode == SP_ALGMODE_CBCPadIV8;
    if (padded) o |= kCCOptionPKCS7Padding;
    if (c->mode == SP_ALGMODE_ECB) o |= kCCOptionECBMode;
    else if (c->mode != SP_ALGMODE_CBC && c->mode != SP_ALGMODE_CBC_IV8 && c->mode != SP_ALGMODE_CBCPadIV8) {
        SP_SEC_LOG(10, "%s: unsupported mode %u", name, c->mode);
        return SPERR_INVALID_ALGORITHM;
    }
    size_t total = 0;
    for (uint32_t i = 0; i < nin; i++) total += in[i].Length;
    uint8_t *src = malloc(total ? total : 1);
    for (size_t i = 0, at = 0; i < nin; at += in[i].Length, i++) memcpy(src + at, in[i].Data, in[i].Length);
    size_t cap = total + block, n = 0;
    int allocated = !out->Data;
    uint8_t *dst = allocated ? sp_cssm_alloc(cap) : out->Data;
    if (!allocated) cap = out->Length;
    CCCryptorStatus s = dst ? CCCrypt(op, a, o, c->key, c->key_len, c->iv, src, total, dst, cap, &n) : kCCMemoryFailure;
    free(src);
    // CCCrypt can report success on bad PKCS7 padding without stripping anything (seen with a wrong key);
    // the real CSP fails. Valid padded plaintext is always shorter than its ciphertext.
    if (!s && padded && op == kCCDecrypt && n >= total) s = kCCDecodeError;
    char ti[9] = "-";
    if (c->iv_len) sp_cssm_tag(c->iv, c->iv_len, ti);
    SP_SEC_LOG(20, "%s(alg 0x%x, mode %u, padding %u, key %zu B, iv #%s, %u bufs, %zu B) -> %zu B, status %d", name,
               c->alg, c->mode, c->padding, c->key_len, ti, nin, total, n, s);
    if (s) {
        if (allocated && dst) sp_cssm_free(dst);
        return s == kCCBufferTooSmall ? SPERR_OUTPUT_LENGTH_ERROR : SPERR_INVALID_DATA;
    }
    out->Data = dst;
    // Like Apple's CSP: a buffer it allocates for decryption keeps the input's length; *done has the
    // plaintext's.
    out->Length = allocated && op == kCCDecrypt ? total : n;
    if (done) *done = n;
    if (rem) rem->Length = 0;
    return 0;
}

SP_CSSM_RETURN sp_CSSM_DecryptData(SP_CSSM_HANDLE cc, const SP_CSSM_DATA *in, uint32_t nin, SP_CSSM_DATA *out, uint32_t nout,
                                size_t *done, SP_CSSM_DATA *rem) __asm__("_CSSM_DecryptData");
SP_CSSM_RETURN sp_CSSM_DecryptData(SP_CSSM_HANDLE cc, const SP_CSSM_DATA *in, uint32_t nin, SP_CSSM_DATA *out, uint32_t nout,
                                size_t *done, SP_CSSM_DATA *rem) {
    return sp_cssm_crypt(kCCDecrypt, "CSSM_DecryptData", cc, in, nin, out, nout, done, rem);
}

SP_CSSM_RETURN sp_CSSM_EncryptData(SP_CSSM_HANDLE cc, const SP_CSSM_DATA *in, uint32_t nin, SP_CSSM_DATA *out, uint32_t nout,
                                size_t *done, SP_CSSM_DATA *rem) __asm__("_CSSM_EncryptData");
SP_CSSM_RETURN sp_CSSM_EncryptData(SP_CSSM_HANDLE cc, const SP_CSSM_DATA *in, uint32_t nin, SP_CSSM_DATA *out, uint32_t nout,
                                size_t *done, SP_CSSM_DATA *rem) {
    return sp_cssm_crypt(kCCEncrypt, "CSSM_EncryptData", cc, in, nin, out, nout, done, rem);
}
