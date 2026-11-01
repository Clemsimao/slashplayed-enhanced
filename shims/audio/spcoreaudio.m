// CoreAudio shim (#included into the generated libspCoreAudio): the client's six legacy HAL calls,
// answered by one fake device. The real calls work on visionOS, but they load macOS-style HAL plugins
// into the app (BTAudioHALPlugin trapped in one run), and the device they describe has no name and isn't
// in the device list, so the client gave up on it. Playback goes through RemoteIO (spaudiotoolbox.m),
// which ignores the device; this one only has to satisfy the client's checks, with Mac-like values.
// Every selector the client asks for is logged; unknown ones fail with 'who?' like the HAL.
#include "spaudiolog.h"
#include <CoreFoundation/CoreFoundation.h>

static _Atomic uint32_t sp_buffer_frames = 512;  // 'fsiz': the client sets it, RemoteIO ignores it

enum {
    SP_DEVICE = 44,  // the ID visionOS's HAL used for its default device
    SP_UNKNOWN_PROPERTY = 'who?',
    SP_BAD_DEVICE = '!dev',
    SP_BAD_SIZE = '!siz',
};

// A value for hardware or device property `sel` into out (capacity *size; out NULL = size query).
static SPStatus sp_property(uint32_t sel, unsigned char input, uint32_t *size, void *out) {
    union {
        double f64;
        uint32_t u32;
        CFStringRef str;
        uint32_t words[13];
    } v = {0};
    const void *src = &v;
    uint32_t len;
    switch (sel) {
    case 'dOut': case 'dIn ': case 'sOut': case 'dev#':  // default output/input/system device; device list
        v.u32 = SP_DEVICE;
        len = 4;
        break;
    case 'name': case 'mnam': {  // C strings: device / manufacturer name
        src = sel == 'mnam' ? "Apple Inc." : "Apple Vision Pro";
        len = (uint32_t)strlen(src) + 1;
        break;
    }
    case 'lnam': case 'uid ':  // CFStrings (the caller releases them)
        v.str = CFStringCreateWithCString(NULL, sel == 'lnam' ? "Apple Vision Pro" : "VisionProAudio",
                                          kCFStringEncodingUTF8);
        len = sizeof v.str;
        break;
    case 'nsrt':  // nominal sample rate
        v.f64 = SP_CLIENT_RATE;
        len = 8;
        break;
    case 'fsiz':  // buffer frame size
        v.u32 = sp_buffer_frames;
        len = 4;
        break;
    case 'fsz#':  // buffer frame size range (AudioValueRange), as a Mac's built-in output
        memcpy(v.words, (double[2]){15, 4096}, 16);
        len = 16;
        break;
    case 'slay':  // stream configuration: an AudioBufferList with one stereo buffer, both directions
        v.words[0] = 1;  // mNumberBuffers (then 4 bytes of padding)
        v.words[2] = 2;  // mNumberChannels
        v.words[3] = 8;  // mDataByteSize
        len = 24;        // ... and a NULL mData
        break;
    case 'srnd':  // preferred channel layout: two descriptions, left and right
        v.words[2] = 2;  // tag 0 (use descriptions), bitmap 0, 2 descriptions
        v.words[3] = 1;  // kAudioChannelLabel_Left
        v.words[8] = 2;  // kAudioChannelLabel_Right
        len = 52;
        break;
    default:
        return SP_UNKNOWN_PROPERTY;
    }
    if (!size) return SP_BAD_SIZE;
    if (!out) { *size = len; return 0; }
    bool cstr = sel == 'name' || sel == 'mnam';
    if (*size < len && !cstr) {
        if (sel == 'lnam' || sel == 'uid ') CFRelease(v.str);
        return SP_BAD_SIZE;
    }
    if (*size < len) len = *size;  // C strings are truncated, like the HAL does
    memcpy(out, src, len);
    if (cstr && len) ((char *)out)[len - 1] = 0;
    *size = len;
    return 0;
}

SPStatus sp_AudioHardwareGetProperty(uint32_t sel, uint32_t *size, void *out) __asm__("_AudioHardwareGetProperty");
SPStatus sp_AudioHardwareGetProperty(uint32_t sel, uint32_t *size, void *out) {
    uint32_t in = size ? *size : 0;
    SPStatus st = out ? sp_property(sel, 0, size, out) : SP_BAD_SIZE;
    char cc[12], hex[64];
    SP_LOGF(200, "AudioHardwareGetProperty(%s, size %u) = %d, size %u: %s", sp_fourcc(sel, cc), in, st,
            size ? *size : 0, st ? "" : sp_hex(out, size ? *size : 0, hex));
    return st;
}

SPStatus sp_AudioHardwareGetPropertyInfo(uint32_t sel, uint32_t *size, unsigned char *writable) __asm__("_AudioHardwareGetPropertyInfo");
SPStatus sp_AudioHardwareGetPropertyInfo(uint32_t sel, uint32_t *size, unsigned char *writable) {
    uint32_t len = 0;
    SPStatus st = sp_property(sel, 0, &len, NULL);
    if (st == 0 && size) *size = len;
    if (st == 0 && writable) *writable = 0;
    char cc[12];
    SP_LOGF(200, "AudioHardwareGetPropertyInfo(%s) = %d, size %u", sp_fourcc(sel, cc), st, len);
    return st;
}

// The device never changes, so listeners are never called.
SPStatus sp_AudioHardwareAddPropertyListener(uint32_t sel, void *proc, void *data) __asm__("_AudioHardwareAddPropertyListener");
SPStatus sp_AudioHardwareAddPropertyListener(uint32_t sel, void *proc, void *data) {
    char cc[12];
    SP_LOGF(50, "AudioHardwareAddPropertyListener(%s, %p) = 0 (never called)", sp_fourcc(sel, cc), proc);
    return 0;
}

SPStatus sp_AudioDeviceGetProperty(uint32_t dev, uint32_t ch, unsigned char input, uint32_t sel, uint32_t *size, void *out) __asm__("_AudioDeviceGetProperty");
SPStatus sp_AudioDeviceGetProperty(uint32_t dev, uint32_t ch, unsigned char input, uint32_t sel, uint32_t *size, void *out) {
    uint32_t in = size ? *size : 0;
    SPStatus st = dev != SP_DEVICE ? SP_BAD_DEVICE : out ? sp_property(sel, input, size, out) : SP_BAD_SIZE;
    char cc[12], hex[64];
    SP_LOGF(300, "AudioDeviceGetProperty(dev %u, ch %u, %s, %s, size %u) = %d, size %u: %s", dev, ch,
            input ? "in" : "out", sp_fourcc(sel, cc), in, st, size ? *size : 0,
            st ? "" : sp_hex(out, size ? *size : 0, hex));
    return st;
}

SPStatus sp_AudioDeviceGetPropertyInfo(uint32_t dev, uint32_t ch, unsigned char input, uint32_t sel, uint32_t *size, unsigned char *writable) __asm__("_AudioDeviceGetPropertyInfo");
SPStatus sp_AudioDeviceGetPropertyInfo(uint32_t dev, uint32_t ch, unsigned char input, uint32_t sel, uint32_t *size, unsigned char *writable) {
    uint32_t len = 0;
    SPStatus st = dev != SP_DEVICE ? SP_BAD_DEVICE : sp_property(sel, input, &len, NULL);
    if (st == 0 && size) *size = len;
    if (st == 0 && writable) *writable = 0;
    char cc[12];
    SP_LOGF(300, "AudioDeviceGetPropertyInfo(dev %u, ch %u, %s, %s) = %d, size %u", dev, ch,
            input ? "in" : "out", sp_fourcc(sel, cc), st, len);
    return st;
}

// Nothing on the fake device is settable; accept and log, so the client doesn't treat it as fatal.
SPStatus sp_AudioDeviceSetProperty(uint32_t dev, const void *when, uint32_t ch, unsigned char input, uint32_t sel, uint32_t size, const void *data) __asm__("_AudioDeviceSetProperty");
SPStatus sp_AudioDeviceSetProperty(uint32_t dev, const void *when, uint32_t ch, unsigned char input, uint32_t sel, uint32_t size, const void *data) {
    SPStatus st = dev != SP_DEVICE ? SP_BAD_DEVICE : 0;
    const char *how = " (ignored)";
    if (st == 0 && sel == 'fsiz' && data && size >= 4) {
        uint32_t frames = *(const uint32_t *)data;
        if (frames >= 15 && frames <= 4096) {
            sp_buffer_frames = frames;
            how = "";
        } else {
            st = 'nope';  // kAudioHardwareIllegalOperationError
        }
    }
    char cc[12], hex[64];
    SP_LOGF(100, "AudioDeviceSetProperty(dev %u, ch %u, %s, %s, %s) = %d%s", dev, ch,
            input ? "in" : "out", sp_fourcc(sel, cc), sp_hex(data, size, hex), st, how);
    return st;
}
