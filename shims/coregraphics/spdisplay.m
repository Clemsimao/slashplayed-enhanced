// CoreGraphics display queries and cursor calls. #included at the end of the generated libspCoreGraphics.m
// (gen_stubs.py EXTRA_INCLUDES); a function here with __asm__("_symbol") replaces its stub.
//
// There's one display, 1 (NSScreenNumber in the AppKit shim), and it's the AppKit shim's NSScreen,
// scale 1 ($SP_SCALE). The client caps its drawable at the display mode's pixel size; with no display
// (the stubs returned 0 and NULL) it capped at 1920x1080.
#include <CoreGraphics/CoreGraphics.h>
#include <objc/message.h>

static const uint32_t sp_display = 1;

// Points, from the AppKit shim's +[NSScreen mainScreen].frame (that library isn't linked here).
static CGSize sp_display_size(void) {
    id screen = ((id (*)(id, SEL))objc_msgSend)((id)NSClassFromString(@"NSScreen"), sel_registerName("mainScreen"));
    CGRect frame = screen ? ((CGRect (*)(id, SEL))objc_msgSend)(screen, sel_registerName("frame")) : CGRectMake(0, 0, 1280, 720);
    return frame.size;
}

// Its backingScaleFactor.
static CGFloat sp_display_scale(void) {
    id screen = ((id (*)(id, SEL))objc_msgSend)((id)NSClassFromString(@"NSScreen"), sel_registerName("mainScreen"));
    return screen ? ((CGFloat (*)(id, SEL))objc_msgSend)(screen, sel_registerName("backingScaleFactor")) : 1;
}

__attribute__((noinline)) static void sp_display_log(const char *fn, uint32_t display) {
    static atomic_int n;
    if (atomic_fetch_add(&n, 1) >= 40) return;
    CGSize s = sp_display_size();
    char buf[128];
    snprintf(buf, sizeof buf, "%s(%u) -> %gx%g pt, from +0x%lx", fn, display, s.width, s.height,
             (unsigned long)__builtin_return_address(1) - sp_client_base());
    sp_stub_log(buf);
}

// A display mode: its size in points, captured when it was made, and the scale.
@interface SPDisplayMode : NSObject {
  @public
    CGSize size;
}
@end
@implementation SPDisplayMode
@end

static SPDisplayMode *sp_mode_now(void) {
    SPDisplayMode *m = [[SPDisplayMode alloc] init];
    m->size = sp_display_size();
    return m;
}

uint32_t sp_CGMainDisplayID(void) __asm__("_CGMainDisplayID");
uint32_t sp_CGMainDisplayID(void) {
    SP_LOG_ONCE("CGMainDisplayID -> 1");
    return sp_display;
}

int32_t sp_CGGetActiveDisplayList(uint32_t max, uint32_t *displays, uint32_t *count) __asm__("_CGGetActiveDisplayList");
int32_t sp_CGGetActiveDisplayList(uint32_t max, uint32_t *displays, uint32_t *count) {
    SP_LOG_ONCE("CGGetActiveDisplayList -> [1]");
    if (displays && max) displays[0] = sp_display;
    if (count) *count = displays ? (max ? 1 : 0) : 1;
    return 0;
}

int sp_CGDisplayIsMain(uint32_t display) __asm__("_CGDisplayIsMain");
int sp_CGDisplayIsMain(uint32_t display) {
    return display == sp_display;
}

CGRect sp_CGDisplayBounds(uint32_t display) __asm__("_CGDisplayBounds");
CGRect sp_CGDisplayBounds(uint32_t display) {
    sp_display_log("CGDisplayBounds", display);
    CGSize s = sp_display_size();
    return CGRectMake(0, 0, s.width, s.height);
}

size_t sp_CGDisplayPixelsHigh(uint32_t display) __asm__("_CGDisplayPixelsHigh");
size_t sp_CGDisplayPixelsHigh(uint32_t display) {  // points, despite the name, as on macOS
    sp_display_log("CGDisplayPixelsHigh", display);
    return (size_t)sp_display_size().height;
}

CFTypeRef sp_CGDisplayCopyDisplayMode(uint32_t display) __asm__("_CGDisplayCopyDisplayMode");
CFTypeRef sp_CGDisplayCopyDisplayMode(uint32_t display) {
    sp_display_log("CGDisplayCopyDisplayMode", display);
    return display == sp_display ? CFBridgingRetain(sp_mode_now()) : NULL;
}

CFArrayRef sp_CGDisplayCopyAllDisplayModes(uint32_t display, CFDictionaryRef options) __asm__("_CGDisplayCopyAllDisplayModes");
CFArrayRef sp_CGDisplayCopyAllDisplayModes(uint32_t display, CFDictionaryRef options) {
    sp_display_log("CGDisplayCopyAllDisplayModes", display);
    return display == sp_display ? CFBridgingRetain(@[ sp_mode_now() ]) : NULL;
}

void sp_CGDisplayModeRelease(CFTypeRef mode) __asm__("_CGDisplayModeRelease");
void sp_CGDisplayModeRelease(CFTypeRef mode) {
    if (mode) CFRelease(mode);
}

size_t sp_CGDisplayModeGetWidth(SPDisplayMode *m) __asm__("_CGDisplayModeGetWidth");
size_t sp_CGDisplayModeGetWidth(SPDisplayMode *m) {
    return m ? (size_t)m->size.width : 0;
}
size_t sp_CGDisplayModeGetHeight(SPDisplayMode *m) __asm__("_CGDisplayModeGetHeight");
size_t sp_CGDisplayModeGetHeight(SPDisplayMode *m) {
    return m ? (size_t)m->size.height : 0;
}
size_t sp_CGDisplayModeGetPixelWidth(SPDisplayMode *m) __asm__("_CGDisplayModeGetPixelWidth");
size_t sp_CGDisplayModeGetPixelWidth(SPDisplayMode *m) {
    return m ? (size_t)(m->size.width * sp_display_scale()) : 0;
}
size_t sp_CGDisplayModeGetPixelHeight(SPDisplayMode *m) __asm__("_CGDisplayModeGetPixelHeight");
size_t sp_CGDisplayModeGetPixelHeight(SPDisplayMode *m) {
    return m ? (size_t)(m->size.height * sp_display_scale()) : 0;
}
// The client already presents at about 60 fps; keep telling it 60 until that's looked at.
double sp_CGDisplayModeGetRefreshRate(SPDisplayMode *m) __asm__("_CGDisplayModeGetRefreshRate");
double sp_CGDisplayModeGetRefreshRate(SPDisplayMode *m) {
    return 60;
}
uint32_t sp_CGDisplayModeGetIOFlags(SPDisplayMode *m) __asm__("_CGDisplayModeGetIOFlags");
uint32_t sp_CGDisplayModeGetIOFlags(SPDisplayMode *m) {
    return 0x7;  // kDisplayModeValidFlag | kDisplayModeSafeFlag | kDisplayModeDefaultFlag
}
CFStringRef sp_CGDisplayModeCopyPixelEncoding(SPDisplayMode *m) __asm__("_CGDisplayModeCopyPixelEncoding");
CFStringRef sp_CGDisplayModeCopyPixelEncoding(SPDisplayMode *m) {
    return CFSTR("--------RRRRRRRRGGGGGGGGBBBBBBBB");  // IO32BitDirectPixels
}

// ---- the cursor: the AppKit shim's mouse state (+[NSEvent sp_...] in spevent.m)

static Class sp_nsevent(void) {
    return NSClassFromString(@"NSEvent");
}

// The client disconnects the mouse from the cursor while it turns the camera, and reconnects it after.
int32_t sp_CGAssociateMouseAndMouseCursorPosition(uint32_t connected) __asm__("_CGAssociateMouseAndMouseCursorPosition");
int32_t sp_CGAssociateMouseAndMouseCursorPosition(uint32_t connected) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(sp_nsevent(), sel_registerName("sp_setMouseFrozen:"), !connected);
    return 0;
}
// Global display coordinates, origin top left; AppKit's origin is bottom left.
int32_t sp_CGWarpMouseCursorPosition(CGPoint p) __asm__("_CGWarpMouseCursorPosition");
int32_t sp_CGWarpMouseCursorPosition(CGPoint p) {
    CGPoint appkit = CGPointMake(p.x, sp_display_size().height - p.y);
    ((void (*)(id, SEL, CGPoint))objc_msgSend)(sp_nsevent(), sel_registerName("sp_warpMouseTo:"), appkit);
    return 0;
}
int32_t sp_CGDisplayMoveCursorToPoint(uint32_t display, CGPoint p) __asm__("_CGDisplayMoveCursorToPoint");
int32_t sp_CGDisplayMoveCursorToPoint(uint32_t display, CGPoint p) {
    return sp_CGWarpMouseCursorPosition(p);  // one display, at the origin
}
uint32_t sp_CGCursorIsVisible(void) __asm__("_CGCursorIsVisible");
uint32_t sp_CGCursorIsVisible(void) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(sp_nsevent(), sel_registerName("sp_cursorVisible"));
}
