// NSScreen, NSWindow and NSView geometry over the UIKit window (spuikit.m). #included at the end of
// the generated libspAppKit.m after spuikit.m. The stub classes have no ivars and the client
// subclasses NSWindow and NSView, so state lives in associated objects.
//
// One window, the size of the game rect in points, at the bottom left of one screen, so window and
// screen coordinates are the same. The game rect (sp_game_rect) is the UIKit window, except on an
// iPhone in landscape, where the Dynamic Island's side is cut off to just past the island: the
// client's layer sits in the rest and the strip beside it stays black (the root view's background),
// so edge-anchored UI (quest log, spellbook, map) isn't under the island. AppKit coordinates (origin
// the game rect's bottom left) and UIKit's (the window's top left) differ in y and, on an iPhone, by
// that x offset (spevent.m converts). When the scene is resized, sp_window_track_scene (called from
// the client's event pump) resizes the layer, the window and its content view and tells the window's
// delegate, as AppKit would after a live resize; when only the game rect moves (the phone turned
// over, the island now on the other side), it moves the layer, the look highlights and the cursor,
// and the client, whose size didn't change, hears nothing.
//
// On visionOS the screen is a fixed size, at least as big as the scene window gets (2218x1307 pt seen);
// on iPad it follows the scene's orientation and covers every enabled render resolution. The client
// reads the display (here and in the CoreGraphics shim, which asks NSScreen) once at startup and caps
// its drawable at the display's pixel size; a screen the size of the launch window capped it there,
// and larger windows got a stretched image.
// On an iPhone the screen stays the whole screen, island side included: the window is narrower than
// the screen, as a Stage Manager window is, and the drawable cap is the screen's.

#include <objc/message.h>
#include "spdisplaygeometry.h"

@interface NSScreen (SPUIKitDecl)
+ (instancetype)mainScreen;
@end
@interface NSView (SPUIKitDecl)
- (instancetype)initWithFrame:(CGRect)frame;
- (CGRect)frame;
- (void)setFrame:(CGRect)frame;
- (id)window;
@end
@interface NSWindow (SPUIKitDecl)
- (CGRect)frame;
- (void)setFrame:(CGRect)frame display:(BOOL)display;
- (void)setStyleMask:(NSUInteger)style;
- (void)setContentView:(NSView *)view;
@end

static void sp_hover_attach(CALayer *layer);  // sphover.m

#if !TARGET_OS_VISION
// The Dynamic Island's rect, in the screen's fixed (portrait-up) coordinate space, or CGRectNull. UIKit
// has no public API for it; the screen's private _exclusionArea is a UISDisplaySingleRectShape whose
// rect property is it (iPhone 16 Pro: {138.3, 14, 125, 36.7}, the island's outline seen from the top
// of the portrait screen). Private is fine for a sideloaded app; it's looked up through KVC in @try
// and type-checked, so a renamed key or a shape that isn't one rect falls back to the safe-area
// inset instead of crashing the game. A notch's rect would be cut to the same way.
static CGRect sp_island_rect(UIScreen *screen) {
    id rect = nil;
    @try {
        id shape = [screen valueForKey:@"_exclusionArea"];
        if (shape) rect = [shape valueForKey:@"rect"];
    } @catch (NSException *e) {
        SP_LOG_ONCE("screen has no _exclusionArea rect: the island's cut is the safe-area inset");
        return CGRectNull;
    }
    if (![rect isKindOfClass:NSValue.class] || strcmp([rect objCType], @encode(CGRect))) return CGRectNull;
    return [rect CGRectValue];
}
#endif

// What sp_game_rect last cut by and why, for sp_window_track_scene's log line: the island's rect in the
// window (CGRectNull when the safe area was used) and the cut's source.
static CGRect sp_game_island;
static const char *sp_game_cut_source = "";

// The game's part of the scene window, in UIKit points (origin the window's top left). Only the
// island's side is cut: the top and bottom insets are the home indicator's, which hides itself
// (SPRootViewController), and the other side's inset is only there for symmetry. In landscape iOS
// reports an iPhone's left and right insets the same (62 pt on a 16 Pro), island or not, so the
// island's side comes from geometry: the screen's fixed coordinate space is portrait-up, the island at
// the middle of its top edge, and that point converted into the window lands on the island's side
// whichever way the phone is turned (both landscapes are allowed: ClientAssembly.swift's Info.plist,
// and the script build's). The cut goes to the island's outer edge (sp_island_rect, 50.7 pt in on a
// 16 Pro) plus a margin, not the whole 62 pt inset, which is mostly margin; the inset is the fallback
// when the island's rect is missing or doesn't fit (not wholly inside that side's inset band). An iPad
// (insets 0, no island) and the headset keep the whole window.
static CGRect sp_game_rect(void) {
    if (!sp_window) return CGRectMake(0, 0, 1280, 720);
    CGRect b = sp_window.bounds;
#if !TARGET_OS_VISION
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone) return b;
    UIEdgeInsets in = sp_window.safeAreaInsets;
    CGFloat inset = MAX(in.left, in.right);
    UIScreen *screen = sp_window.windowScene.screen;
    if (inset <= 0 || inset * 2 >= b.size.width || !screen) return b;
    id<UICoordinateSpace> fixed = screen.fixedCoordinateSpace;
    CGPoint top = [fixed convertPoint:CGPointMake(CGRectGetMidX(fixed.bounds), 0) toCoordinateSpace:sp_window];
    // Near the middle across: the island is at the top or bottom (portrait, mid-rotation), no side.
    if (fabs(top.x - CGRectGetMidX(b)) < b.size.width / 4) return b;
    BOOL left = top.x < CGRectGetMidX(b);
    CGFloat cut = inset;
    sp_game_island = CGRectNull;
    sp_game_cut_source = "safe area";
    CGRect island = sp_island_rect(screen);
    if (!CGRectIsNull(island) && !CGRectIsEmpty(island)) {
        CGRect r = [fixed convertRect:island toCoordinateSpace:sp_window];
        // Its outer edge, from the window's edge on its side; the rect must lie in that side's inset band.
        CGFloat edge = left ? CGRectGetMaxX(r) : b.size.width - CGRectGetMinX(r);
        BOOL fits = left ? CGRectGetMinX(r) >= 0 : CGRectGetMaxX(r) <= b.size.width;
        if (fits && edge > 0 && edge <= inset) {
            // 4 pt past the island, rounded up to whole points: enough that the game's edge (a frame's
            // border, a button's) reads as clear of the island rather than touching it, while giving back
            // most of the inset's spare margin (55 pt cut, not 62, on a 16 Pro). Whole points keep the
            // drawable a whole number of pixels at any backing scale.
            cut = MIN(inset, ceil(edge + 4));
            sp_game_island = r;
            sp_game_cut_source = "Dynamic Island";
        }
    }
    if (left) b.origin.x += cut;
    b.size.width -= cut;
#endif
    return b;
}

// The client's window: the game rect's size, at the origin.
static CGRect sp_scene_rect(void) {
    CGSize size = sp_game_rect().size;
    return CGRectMake(0, 0, size.width, size.height);
}

static CGRect sp_device_screen_rect(void) {
#if TARGET_OS_VISION
    return CGRectMake(0, 0, 2560, 1440);
#else
    // Match the window's orientation, including an iPad launched or rotated into portrait. Using a
    // landscape height in portrait caps the client's drawable before it fills the window.
    CGSize s = sp_window.windowScene ? sp_window.windowScene.screen.bounds.size : sp_scene_rect().size;
    return sp_screen_in_orientation(s, sp_scene_rect().size);
#endif
}

static BOOL sp_scale_overridden(void) {
    const char *env = getenv("SP_SCALE");
    return env && isfinite(atof(env)) && atof(env) > 0;
}

// Default backing pixels per point: $SP_SCALE (the dev override), else the legacy "sp_scale"
// preference, else 1, or 2 on an iPhone. The scale picker is gone; keep existing preferences so an
// update doesn't change a player's default. On the headset at 2 retail was GPU-bound below 90 fps; 1 frees
// most of the GPU but didn't delay the heat (2026-10-14). An iPhone's screen is small enough that 1x
// (874x402 on a 16 Pro) makes the UI's text unreadable, while the 3D world looks fine: so 2x, with the
// game's own render scale at 50% (launcher.m) to keep the world's GPU cost near 1x's. This is Native's
// scale, read after the start screen; a mode selected in WoW supplies its own scale below.
static CGFloat sp_native_scale(void) {
    static CGFloat scale;
    if (!scale) {
        const char *env = getenv("SP_SCALE");
        NSInteger set = [NSUserDefaults.standardUserDefaults integerForKey:@"sp_scale"];
        scale = env && isfinite(atof(env)) && atof(env) > 0 ? atof(env)
              : set == 1 || set == 2 ? set
              : UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone ? 2 : 1;
        sp_stub_log([NSString stringWithFormat:@"backing scale %gx (%s)", scale,
                     sp_scale_overridden() ? "SP_SCALE" : set == 1 || set == 2 ? "Settings" : "Automatic"].UTF8String);
    }
    return scale;
}

// Keep the existing default and saved selection, including older backing-scale preferences, but
// always expose the complete catalog in WoW. Small stable IDs name the screen-relative modes;
// long-edge IDs name fixed presets. An old availability toggle must never hide a valid game choice.
enum { SPResolutionFullDetail = 1, SPResolutionLowerPower = 2 };
static NSArray<NSNumber *> *sp_resolution_catalog(void) {
    return @[@0, @(SPResolutionLowerPower), @1920, @2560, @(SPResolutionFullDetail)];
}

static BOOL sp_resolution_available(NSInteger resolution) {
    if (!resolution) return YES;
    return !sp_scale_overridden() && [sp_resolution_catalog() containsObject:@(resolution)];
}

static CGFloat sp_resolution_scale(NSInteger resolution, CGSize points) {
    if (resolution == SPResolutionLowerPower) return 1;
    if (resolution == SPResolutionFullDetail) {
#if TARGET_OS_VISION
        return 2;
#else
        UIScreen *screen = sp_window.windowScene.screen;
        CGFloat scale = screen ? screen.scale : 2;
        return MAX(1, scale);
#endif
    }
    return resolution ? resolution / MAX(1, MAX(points.width, points.height)) : sp_native_scale();
}

static NSInteger sp_selected_resolution = -1;
static NSInteger sp_resolution_now(void) {
    if (sp_selected_resolution < 0) {
        NSInteger saved = [NSUserDefaults.standardUserDefaults integerForKey:@"sp_resolution"];
        sp_selected_resolution = sp_resolution_available(saved) ? saved : 0;
        if (saved != sp_selected_resolution && !sp_scale_overridden()) {
            [NSUserDefaults.standardUserDefaults setInteger:sp_selected_resolution forKey:@"sp_resolution"];
        }
        // A screen-relative choice can equal the legacy default. Keep one canonical selection,
        // just as the menu deduplicates those identical pixel sizes.
        if ((sp_selected_resolution == SPResolutionLowerPower || sp_selected_resolution == SPResolutionFullDetail) &&
            fabs(sp_resolution_scale(sp_selected_resolution, CGSizeZero) - sp_native_scale()) < 0.00001) {
            sp_selected_resolution = 0;
            [NSUserDefaults.standardUserDefaults setInteger:0 forKey:@"sp_resolution"];
        }
    }
    return sp_selected_resolution;
}

static BOOL sp_select_resolution(NSInteger resolution) {
    if (!sp_resolution_available(resolution)) return NO;
    if (sp_resolution_now() != resolution) {
        sp_selected_resolution = resolution;
        [NSUserDefaults.standardUserDefaults setInteger:resolution forKey:@"sp_resolution"];
        NSString *label = resolution == SPResolutionFullDetail ? @"Full detail"
                         : resolution == SPResolutionLowerPower ? @"Lower power"
                         : resolution ? @(resolution).stringValue : @"Default";
        sp_stub_log([NSString stringWithFormat:@"game selected resolution: %@", label].UTF8String);
    }
    return YES;
}

static CGFloat sp_scale_now(void) {
    NSInteger resolution = sp_resolution_now();
    CGSize size = sp_scene_rect().size;
    return sp_resolution_scale(resolution, size);
}

static CGSize sp_mode_pixels(NSInteger resolution) {
    CGSize size = sp_scene_rect().size;
    CGFloat scale = sp_resolution_scale(resolution, size);
    return sp_resolution_pixels(size, scale, resolution != 0);
}

// A virtual screen large enough for every enabled preset, independent of the current low-power
// drawable. Otherwise WoW clamps a higher selection to the old display ceiling before requesting it.
static CGRect sp_screen_rect(void) {
    CGSize device = sp_device_screen_rect().size;
    CGSize pixels = CGSizeMake(device.width * sp_native_scale(), device.height * sp_native_scale());
    for (NSNumber *preset in sp_resolution_catalog()) if (sp_resolution_available(preset.integerValue)) {
        CGSize mode = sp_mode_pixels(preset.integerValue);
        pixels.width = MAX(pixels.width, mode.width);
        pixels.height = MAX(pixels.height, mode.height);
    }
    // Screen geometry describes the available hardware ceiling, not the active window's render
    // scale. Shrinking it after selecting 1920 makes the client's next 2560 selection a no-op.
    CGFloat scale = sp_native_scale();
    return CGRectMake(0, 0, pixels.width / scale, pixels.height / scale);
}

// Fullscreen-windowed clients can select a mode by resizing their window or their drawable, without
// calling CGDisplaySetDisplayMode. Accept only an advertised size; ignore their generic startup size.
static BOOL sp_announcing_display;
static BOOL sp_select_pixel_size(CGSize pixels) {
    if (sp_announcing_display) return NO;
    for (NSNumber *preset in sp_resolution_catalog()) {
        NSInteger resolution = preset.integerValue;
        if (!sp_resolution_available(resolution)) continue;
        CGSize mode = sp_mode_pixels(resolution);
        if (fabs(pixels.width - mode.width) < 0.5 && fabs(pixels.height - mode.height) < 0.5)
            return sp_select_resolution(resolution);
    }
    return NO;
}

// The launcher's read of it (launcher.m's default_render_scale), so the precedence lives here alone.
__attribute__((visibility("default"))) double sp_backing_scale(void) { return sp_scale_now(); }
#define sp_scale sp_scale_now()

static CGRect sp_to_backing(CGRect r) {
    CGSize size = sp_resolution_pixels(r.size, sp_scale, sp_resolution_now() != 0);
    return CGRectMake(r.origin.x * sp_scale, r.origin.y * sp_scale, size.width, size.height);
}

static CGRect sp_from_backing(CGRect r) {
    return CGRectMake(r.origin.x / sp_scale, r.origin.y / sp_scale, r.size.width / sp_scale,
                      r.size.height / sp_scale);
}

static id sp_client_window;  // the client's one NSWindow

static char sp_style_key, sp_frame_key, sp_content_view_key, sp_window_key, sp_layer_key, sp_wants_layer_key;

static CGRect sp_get_rect(id obj, void *key, CGRect fallback) {
    NSValue *v = objc_getAssociatedObject(obj, key);
    return v ? v.CGRectValue : fallback;
}

static void sp_set_rect(id obj, void *key, CGRect r) {
    objc_setAssociatedObject(obj, key, [NSValue valueWithCGRect:r], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@implementation NSScreen (SPUIKit)
- (NSArray *)sp_displayModes {
    NSMutableArray *modes = [NSMutableArray array];
    for (NSNumber *preset in sp_resolution_catalog()) if (sp_resolution_available(preset.integerValue)) {
        CGSize pixels = sp_mode_pixels(preset.integerValue);
        BOOL duplicate = NO;
        for (NSDictionary *mode in modes) if (CGSizeEqualToSize([mode[@"Pixels"] CGSizeValue], pixels)) duplicate = YES;
        if (!duplicate) [modes addObject:@{@"Resolution": preset, @"Pixels": [NSValue valueWithCGSize:pixels]}];
    }
    return modes;
}
- (BOOL)sp_selectResolution:(NSInteger)resolution { return sp_select_resolution(resolution); }
- (NSInteger)sp_selectedResolution { return sp_resolution_now(); }
+ (NSArray *)screens {
    return @[ [self mainScreen] ];
}
+ (instancetype)mainScreen {
    static NSScreen *screen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ screen = [[NSScreen alloc] init]; });
    return screen;
}
- (CGRect)frame {
    return sp_screen_rect();
}
- (CGRect)visibleFrame {
    return sp_screen_rect();
}
- (CGFloat)backingScaleFactor {
    return sp_native_scale();
}
- (CGRect)convertRectToBacking:(CGRect)r {
    CGFloat scale = sp_native_scale();
    return CGRectMake(r.origin.x * scale, r.origin.y * scale, r.size.width * scale, r.size.height * scale);
}
- (CGRect)convertRectFromBacking:(CGRect)r {
    CGFloat scale = sp_native_scale();
    return CGRectMake(r.origin.x / scale, r.origin.y / scale, r.size.width / scale, r.size.height / scale);
}
- (NSDictionary *)deviceDescription {
    return @{
        @"NSScreenNumber": @1,  // CGDirectDisplayID
        @"NSDeviceSize": [NSValue valueWithCGSize:sp_screen_rect().size],
        @"NSDeviceResolution": [NSValue valueWithCGSize:CGSizeMake(72 * sp_native_scale(), 72 * sp_native_scale())],
    };
}
@end

@implementation NSWindow (SPUIKit)
- (instancetype)initWithContentRect:(CGRect)rect styleMask:(NSUInteger)style backing:(NSUInteger)backing
                              defer:(BOOL)defer {
    if (!(self = [self init])) return nil;
    sp_stub_log([NSString stringWithFormat:@"-[%s initWithContentRect:{%g,%g,%g,%g} styleMask:0x%lx]",
                 object_getClassName(self), rect.origin.x, rect.origin.y, rect.size.width,
                 rect.size.height, (unsigned long)style].UTF8String);
    sp_set_rect(self, &sp_frame_key, sp_scene_rect());
    [self setStyleMask:style];
    sp_client_window = self;
    return self;
}
- (NSUInteger)styleMask {
    return [objc_getAssociatedObject(self, &sp_style_key) unsignedIntegerValue];
}
- (void)setStyleMask:(NSUInteger)style {
    objc_setAssociatedObject(self, &sp_style_key, @(style), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (CGRect)frame {
    return sp_get_rect(self, &sp_frame_key, sp_scene_rect());
}
// The client's one window is the UIKit scene window, so its frame is always that window's size,
// whatever the client asks for (it asks for 960x540, 3/4 of the screen, and would render into only that
// much). Content and frame rects are the same (no title bar), and the content view follows the size.
- (void)setFrame:(CGRect)frame display:(BOOL)display {
    sp_stub_log([NSString stringWithFormat:@"-[%s setFrame:{%g,%g,%g,%g}] (pinned to the scene window)",
                 object_getClassName(self), frame.origin.x, frame.origin.y, frame.size.width,
                 frame.size.height].UTF8String);
    // AppKit frames are points. At the 1920 preset, WoW requests about 1821.33x1366 points for a
    // 2560x1920 drawable. Comparing that frame directly to pixel modes silently ignores the choice.
    CGFloat previous_scale = sp_scale;
    CGSize pixels = CGSizeMake(frame.size.width * previous_scale, frame.size.height * previous_scale);
    if (!sp_select_pixel_size(pixels) &&
        !sp_select_pixel_size(sp_resolution_pixels(frame.size, previous_scale, YES)))
        sp_select_pixel_size(frame.size);  // clients that pass the advertised pixel size directly
    frame = sp_scene_rect();
    sp_set_rect(self, &sp_frame_key, frame);
    NSView *view = objc_getAssociatedObject(self, &sp_content_view_key);
    if (view) [view setFrame:CGRectMake(0, 0, frame.size.width, frame.size.height)];
}
- (void)setFrame:(CGRect)frame display:(BOOL)display animate:(BOOL)animate {
    [self setFrame:frame display:display];
}
- (void)setContentSize:(CGSize)size {
    CGRect r = [self frame];
    r.size = size;
    [self setFrame:r display:YES];
}
- (CGRect)contentRectForFrameRect:(CGRect)frame {
    return frame;
}
- (CGRect)frameRectForContentRect:(CGRect)content {
    return content;
}
- (id)contentView {
    NSView *view = objc_getAssociatedObject(self, &sp_content_view_key);
    if (!view) {
        CGRect r = [self frame];
        view = [[NSView alloc] initWithFrame:CGRectMake(0, 0, r.size.width, r.size.height)];
        [self setContentView:view];
    }
    return view;
}
// The client sets nil on its way out; objc_setAssociatedObject on nil is fatal.
- (void)setContentView:(NSView *)view {
    NSView *old = objc_getAssociatedObject(self, &sp_content_view_key);
    if (old && old != view) objc_setAssociatedObject(old, &sp_window_key, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(self, &sp_content_view_key, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!view) return;
    objc_setAssociatedObject(view, &sp_window_key, self, OBJC_ASSOCIATION_ASSIGN);
    CGRect r = [self frame];
    CGRect vf = [view frame];
    if (vf.size.width <= 0 || vf.size.height <= 0) [view setFrame:CGRectMake(0, 0, r.size.width, r.size.height)];
}
- (NSScreen *)screen {
    return [NSScreen mainScreen];
}
- (CGFloat)backingScaleFactor {
    return sp_scale;
}
- (BOOL)isVisible {
    return YES;
}
- (BOOL)isKeyWindow {
    return YES;
}
- (BOOL)isMainWindow {
    return YES;
}
@end

// The client renders into its view's layer (a CAMetalLayer), so it has to be on screen: it fills the
// game rect of the UIKit window, the one content view there is. The present hook (sp_hover_attach) goes
// in with it, and the loading screen comes down at the first present, so neither may happen for a layer
// off screen.
static CALayer *sp_resolution_layer;
static void (*sp_drawable_size_orig)(id, SEL, CGSize);
static void sp_drawable_size(id layer, SEL selector, CGSize size) {
    if (layer == sp_resolution_layer) sp_select_pixel_size(size);
    sp_drawable_size_orig(layer, selector, size);
}

static void sp_layer_show(CALayer *l) {
    sp_resolution_layer = l;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method method = class_getInstanceMethod(NSClassFromString(@"CAMetalLayer"), sel_registerName("setDrawableSize:"));
        if (method) sp_drawable_size_orig = (void *)method_setImplementation(method, (IMP)sp_drawable_size);
    });
    l.frame = sp_game_rect();
    l.contentsScale = sp_scale;
    [sp_window.rootViewController.view.layer addSublayer:l];
    sp_hover_attach(l);
}

// On visionOS UIKit starts at +sharedApplication, and the scene usually connects before the client sets
// its layer, but not always: a launch held until the headset is put on connected 5.5 s after the client
// was asked for, after -setLayer:, and with nothing to add the layer to, the game ran behind the loading
// screen for good. The layer set meanwhile waits here (the client's latest; nil when it replaces it)
// until the scene connects (sp_window_scene_connected).
static CALayer *sp_layer_waiting;

// spuikit.m's scene delegate, once sp_window is made: what the client set while there was no window.
// The window's and view's sizes need nothing here: until then they're sp_scene_rect()'s fallback, and
// sp_window_track_scene sizes them to the scene at the client's next pump, as after any resize.
static void sp_window_scene_connected(void) {
    CALayer *l = sp_layer_waiting;
    sp_layer_waiting = nil;
    if (!l || l.superlayer) return;
    sp_layer_show(l);
    sp_stub_log("client's layer on screen late, when the scene connected");
}

// Test hook (SP_SCENE_CONNECT_LATE=1, through DEVICECTL_CHILD_): makes the late connect above happen on
// demand. The scene delegate calls this before it makes the window; it hands the main thread back to the
// client (as the run loop observer does) until the client has set its layer, then lets the connect go on.
// Only once the client has asked for NSApp, so never before the client is loaded (iOS's early UIKit), and
// for at most 10 s.
static void sp_scene_connect_late(void) {
    static BOOL done;
    if (done || !getenv("SP_SCENE_CONNECT_LATE") || !sp_NSApp || !sp_in_uikit) return;
    done = YES;
    sp_stub_log("SP_SCENE_CONNECT_LATE: holding the scene's connect until the client sets its layer");
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent() + 10;
    while (!sp_layer_waiting && CFAbsoluteTimeGetCurrent() < end) sp_switch_to(NO);
    sp_stub_log(sp_layer_waiting ? "SP_SCENE_CONNECT_LATE: the client set its layer; connecting"
                                 : "SP_SCENE_CONNECT_LATE: no layer in 10 s; connecting");
}

@implementation NSView (SPUIKit)
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [self init])) return nil;
    sp_set_rect(self, &sp_frame_key, frame);
    return self;
}
// Until it has one of its own, a view is as big as its window's content, or the screen.
- (CGRect)frame {
    NSWindow *w = [self window];
    CGRect fallback = w ? [w frame] : sp_scene_rect();
    fallback.origin = CGPointMake(0, 0);
    return sp_get_rect(self, &sp_frame_key, fallback);
}
- (void)setFrame:(CGRect)frame {
    static int logged;
    if (logged < 20 && !CGSizeEqualToSize(frame.size, sp_scene_rect().size)) {
        logged++;
        sp_stub_log([NSString stringWithFormat:@"-[%s setFrame:{%g,%g,%g,%g}] (scene is %gx%g)", object_getClassName(self),
                     frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
                     sp_scene_rect().size.width, sp_scene_rect().size.height].UTF8String);
    }
    sp_set_rect(self, &sp_frame_key, frame);
}
- (void)setFrameSize:(CGSize)size {
    CGRect r = [self frame];
    r.size = size;
    [self setFrame:r];
}
- (CGRect)bounds {
    CGRect r = [self frame];
    r.origin = CGPointMake(0, 0);
    return r;
}
- (id)window {
    return objc_getAssociatedObject(self, &sp_window_key);
}
- (BOOL)wantsLayer {
    return [objc_getAssociatedObject(self, &sp_wants_layer_key) boolValue];
}
- (void)setWantsLayer:(BOOL)wants {
    objc_setAssociatedObject(self, &sp_wants_layer_key, @(wants), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (id)layer {
    return objc_getAssociatedObject(self, &sp_layer_key);
}
// Watch for observers on the client's views (it observes its View with KVO), to know which keys a
// resize has to change.
- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options
            context:(void *)context {
    sp_stub_log([NSString stringWithFormat:@"-[%s addObserver:<%s> forKeyPath:%@]", object_getClassName(self),
                 object_getClassName(observer), keyPath].UTF8String);
    [super addObserver:observer forKeyPath:keyPath options:options context:context];
}
- (void)setLayer:(id)layer {
    sp_stub_log([NSString stringWithFormat:@"-[%s setLayer:<%s>]", object_getClassName(self),
                 object_getClassName(layer)].UTF8String);
    // The client replaces its layer when it comes back from the background (nil, then a new one); the
    // old one leaves the UIKit window, or each comeback stacks another full-size Metal layer under it.
    CALayer *old = objc_getAssociatedObject(self, &sp_layer_key);
    if (old != layer && [old isKindOfClass:NSClassFromString(@"CALayer")]) [old removeFromSuperlayer];
    objc_setAssociatedObject(self, &sp_layer_key, layer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (old != layer && old == sp_layer_waiting) sp_layer_waiting = nil;
    if (![layer isKindOfClass:NSClassFromString(@"CALayer")]) return;
    if (sp_window) {
        sp_layer_show(layer);
    } else {
        sp_layer_waiting = layer;
        sp_stub_log("client's layer set before the scene connected: it goes on screen when the scene does");
    }
}
- (CGRect)convertRectToBacking:(CGRect)r {
    return sp_to_backing(r);
}
- (CGRect)convertRectFromBacking:(CGRect)r {
    return sp_from_backing(r);
}
- (CGSize)convertSizeToBacking:(CGSize)s {
    return sp_resolution_pixels(s, sp_scale, sp_resolution_now() != 0);
}
- (CGSize)convertSizeFromBacking:(CGSize)s {
    return CGSizeMake(s.width / sp_scale, s.height / sp_scale);
}
@end

// ---- scene resize

// The game rect (UIKit points, in the scene window) the client, its layer, the look highlights and the
// cursor were last fitted to; empty until the first fit.
static CGRect sp_told_rect;
static CGRect sp_told_screen;
static CGFloat sp_told_scale;
static void sp_game_moved(CGRect game);  // spevent.m: the look highlights and the cursor follow the game

static void sp_set_layer_frame(CALayer *l, CGRect frame) {
    Class tx = NSClassFromString(@"CATransaction");  // not linked directly
    [tx begin];
    [tx setDisableActions:YES];  // a sublayer's frame change would otherwise animate
    l.frame = frame;
    [tx commit];
}

// Called on the client's side of the main thread each time it pumps events, which is also how a
// change in the safe area is noticed (no UIKit callback is needed: the client pumps every frame). The
// first time, whenever the game rect changed size since, and whenever the client's layer isn't where
// it was put (coming back from the background, the client makes a new layer sized for the whole
// screen), apply it the way AppKit's live resize ends: window frame, content view frame (KVO
// observers see it), NSViewFrameDidChangeNotification, then windowDidResize: and
// NSWindowDidResizeNotification. When the game rect only moved (an iPhone turned from one landscape to
// the other: same scene size, the island's strip on the other side), the layer, the look highlights
// and the cursor move with it and the client isn't told: its window's size and coordinates are the same.
// The same for a layer the client only displaced: it sets its layer's frame to its view's bounds, origin
// 0,0, once while handling the first resize (iPhone 16 Pro, 2026-10-31), so the layer goes back to the
// game rect's origin, and telling the client again would only have it do that again.
static void sp_window_track_scene(void) {
    if (!sp_window || !sp_client_window || sp_announcing_display) return;
    CGRect game = sp_game_rect();
    CGSize size = game.size;
    if (size.width <= 0 || size.height <= 0) return;
    id window = sp_client_window;
    NSView *view = objc_getAssociatedObject(window, &sp_content_view_key);
    CALayer *layer = view ? objc_getAssociatedObject(view, &sp_layer_key) : nil;
    if (![layer isKindOfClass:NSClassFromString(@"CALayer")]) layer = nil;
    BOOL layer_off = layer && !CGRectEqualToRect(layer.frame, sp_told_rect);
    BOOL layer_resized = layer && !CGSizeEqualToSize(layer.frame.size, sp_told_rect.size);
    BOOL resized = !CGSizeEqualToSize(size, sp_told_rect.size);
    BOOL moved = !CGPointEqualToPoint(game.origin, sp_told_rect.origin);
    CGRect screen = sp_screen_rect();
    CGFloat scale = sp_scale;
    BOOL display_changed = !CGRectEqualToRect(screen, sp_told_screen);
    BOOL scale_changed = scale != sp_told_scale;
    if (!resized && !moved && !layer_off && !display_changed && !scale_changed) return;
    // The first time too: at launch the client sized its layer and drawable for the screen.
    static int layer_fixes;  // logged up to 20 times, in case the client keeps at it
    if (resized || moved) {
        CGSize scene = sp_window.bounds.size;
        // The island's rect is in the window's coordinates (UIKit points), as the game rect is.
        NSString *island = CGRectIsNull(sp_game_island) ? @""
            : [NSString stringWithFormat:@" at %.1f,%.1f %.1fx%.1f", sp_game_island.origin.x, sp_game_island.origin.y,
               sp_game_island.size.width, sp_game_island.size.height];
        NSString *cut = CGRectEqualToRect(game, sp_window.bounds) ? (sp_told_rect.size.width ? @", the game all of it" : @"")
            : [NSString stringWithFormat:@", the game %gx%g at %g,%g (Dynamic Island %s; cut %g pt by the %s%@)",
               size.width, size.height, game.origin.x, game.origin.y, game.origin.x > 0 ? "left" : "right",
               scene.width - size.width, sp_game_cut_source, island];
        sp_stub_log([NSString stringWithFormat:@"scene %s %gx%g pt%@",
                     !sp_told_rect.size.width ? "is" : resized ? "resized to" : "is still", scene.width,
                     scene.height, cut].UTF8String);
    } else if (++layer_fixes <= 20) {
        sp_stub_log([NSString stringWithFormat:@"client's layer is %gx%g pt at %g,%g, back to the game's %gx%g at %g,%g",
                     layer.frame.size.width, layer.frame.size.height, layer.frame.origin.x, layer.frame.origin.y,
                     size.width, size.height, game.origin.x, game.origin.y].UTF8String);
    }
    sp_told_rect = game;
    sp_told_screen = screen;
    sp_told_scale = scale;
    if (layer) {
        sp_set_layer_frame(layer, game);
        layer.contentsScale = scale;
    }
    sp_game_moved(game);
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    sp_announcing_display = YES;
    // The game caches its display's drawable ceiling. Send the same display-change signals as a
    // Mac before the resize, so a landscape launch can grow to portrait's taller drawable.
    if (display_changed || scale_changed) {
        void (*changed)(void) = (void (*)(void))dlsym(RTLD_DEFAULT, "sp_display_reconfigured");
        // The launcher may have loaded the game's dependencies RTLD_LOCAL. Find that existing
        // CoreGraphics image by its bundle path as well; never load a second copy for a notification.
        if (!changed) {
            NSString *path = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/libspCoreGraphics.dylib"];
            void *cg = dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
            if (cg) {
                changed = (void (*)(void))dlsym(cg, "sp_display_reconfigured");
                dlclose(cg);
            }
        }
        if (changed) changed();
        [nc postNotificationName:@"NSApplicationDidChangeScreenParametersNotification" object:sp_NSApp];
    }
    if (scale_changed) {
        NSNotification *backing = [NSNotification notificationWithName:@"NSWindowDidChangeBackingPropertiesNotification" object:window];
        id delegate = [window delegate];
        if ([delegate respondsToSelector:@selector(windowDidChangeBackingProperties:)])
            ((void (*)(id, SEL, id))objc_msgSend)(delegate, @selector(windowDidChangeBackingProperties:), backing);
        [nc postNotification:backing];
    }
    if (!resized && !layer_resized && !scale_changed) {
        sp_announcing_display = NO;
        return;  // moved, or the layer displaced, only
    }
    CGRect frame = CGRectMake(0, 0, size.width, size.height);
    sp_set_rect(window, &sp_frame_key, frame);
    if (view) {
        [view setFrame:frame];
        [nc postNotificationName:@"NSViewFrameDidChangeNotification" object:view];
    }
    NSNotification *n = [NSNotification notificationWithName:@"NSWindowDidResizeNotification" object:window];
    id delegate = [window delegate];
    if ([delegate respondsToSelector:@selector(windowDidResize:)])
        ((void (*)(id, SEL, id))objc_msgSend)(delegate, @selector(windowDidResize:), n);
    [nc postNotification:n];
    sp_announcing_display = NO;
}
