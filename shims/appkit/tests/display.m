// Exercise the real AppKit and CoreGraphics shims without a game, sign-in, or device pairing.
#include "../../generated/libspAppKit.m"
#include "../../coregraphics/spdisplay.m"

static NSUInteger sp_test_checks, sp_test_resizes, sp_test_display_changes;
static void sp_test_check(BOOL ok, NSString *message) {
    if (!ok) @throw [NSException exceptionWithName:@"Display test failed" reason:message userInfo:nil];
    sp_test_checks++;
}

static void sp_test_display_changed(uint32_t display, uint32_t flags, void *context) {
    sp_test_check(display == 1 && context == &sp_test_checks, @"Display callbacks preserve the display and context.");
    if (flags & (1 << 3)) sp_test_display_changes++;
}

@interface SPDisplayTestDelegate : NSObject
@end
@implementation SPDisplayTestDelegate
- (void)windowDidResize:(NSNotification *)notification {
    sp_test_resizes++;
    id window = notification.object;
    // A client may reapply its point-sized frame during a resize. This must not select Native.
    [window setFrame:[window frame] display:YES];
    NSView *view = [window contentView];
    CAMetalLayer *layer = [view layer];
    layer.drawableSize = [view convertSizeToBacking:[view frame].size];
}
@end

static void sp_test_run(void) {
    NSInteger resolution = sp_resolution_now();
    CGFloat automatic = [NSUserDefaults.standardUserDefaults integerForKey:@"sp_scale"];
    const char *env = getenv("SP_SCALE");
    if (env && isfinite(atof(env)) && atof(env) > 0) automatic = atof(env);
    if (automatic != 1 && automatic != 2) automatic = 1;
    sp_test_check(CGSizeEqualToSize(sp_resolution_pixels(CGSizeMake(1366, 1024), 1920.0 / 1366, YES), CGSizeMake(1920, 1440)),
                  @"1920 preserves the screenshot iPad's aspect ratio with even pixels.");
    sp_test_check(CGSizeEqualToSize(sp_resolution_pixels(CGSizeMake(1024, 1366), 2560.0 / 1366, YES), CGSizeMake(1920, 2560)),
                  @"2560 has the matching portrait dimensions.");
    sp_test_check(sp_CGDisplayRegisterReconfigurationCallback(NULL, NULL) == 1001, @"Null callbacks are rejected.");
    sp_CGDisplayRegisterReconfigurationCallback(sp_test_display_changed, &sp_test_checks);
    sp_CGDisplayRegisterReconfigurationCallback(sp_test_display_changed, &sp_test_checks);

    NSWindow *client = [[NSWindow alloc] initWithContentRect:CGRectZero styleMask:0 backing:0 defer:NO];
    NSView *view = [[NSView alloc] initWithFrame:CGRectZero];
    [client setContentView:view];
    SPDisplayTestDelegate *delegate = [SPDisplayTestDelegate new];
    [client setDelegate:delegate];
    CAMetalLayer *layer = [CAMetalLayer layer];
    layer.device = MTLCreateSystemDefaultDevice();
    [view setLayer:layer];
    CGSize screen = sp_window.windowScene.screen.bounds.size;
    CGFloat longer = MAX(screen.width, screen.height), shorter = MIN(screen.width, screen.height);
    CFTypeRef snapshot = NULL;
    CGSize savedPixels = CGSizeZero;
    for (int i = 0; i < 3; i++) {
        @autoreleasepool {
            BOOL portrait = i == 1;
            CGSize points = portrait ? CGSizeMake(shorter, longer) : CGSizeMake(longer, shorter);
            sp_window.bounds = (CGRect){CGPointZero, points};
            sp_window.rootViewController.view.frame = sp_window.bounds;
            NSUInteger changes = sp_test_display_changes;
            sp_window_track_scene();
            CGFloat full = MAX(1, sp_window.windowScene.screen.scale);
            CGFloat scale = resolution == SPResolutionFullDetail ? full
                          : resolution == SPResolutionLowerPower ? 1
                          : resolution ? resolution / longer : automatic;
            CGSize expected = sp_resolution_pixels(points, scale, resolution != 0);
            sp_test_check(fabs(sp_backing_scale() - scale) < 0.00001, @"The selected preset determines the backing scale.");
            sp_test_check(CGSizeEqualToSize([client frame].size, points), @"The client follows the scene in either orientation.");
            sp_test_check(CGSizeEqualToSize([view convertSizeToBacking:points], expected), @"The view converts to the requested pixels.");
            sp_test_check(CGSizeEqualToSize([view convertRectToBacking:(CGRect){CGPointZero, points}].size, expected),
                          @"Rect and size backing conversions agree.");
            sp_test_check(CGSizeEqualToSize(layer.drawableSize, expected), @"Resize callbacks update the actual Metal drawable size.");
            sp_test_check(CGRectEqualToRect(layer.frame, sp_game_rect()), @"The layer still fills the window.");
            sp_test_check(sp_test_display_changes == changes + 1, @"Rotation sends one display change, including duplicate registration.");
            CFTypeRef mode = sp_CGDisplayCopyDisplayMode(1);
            SPDisplayMode *m = (__bridge SPDisplayMode *)mode;
            sp_test_check((sp_CGDisplayModeGetWidth(m) > sp_CGDisplayModeGetHeight(m)) != portrait,
                          @"The advertised display follows portrait and landscape.");
            sp_test_check(sp_CGDisplayModeGetPixelWidth(m) >= expected.width && sp_CGDisplayModeGetPixelHeight(m) >= expected.height,
                          @"The virtual display can accommodate the active drawable.");
            CFArrayRef modes = sp_CGDisplayCopyAllDisplayModes(1, NULL);
            NSMutableArray<NSValue *> *unique = [NSMutableArray array];
            for (NSNumber *identifier in sp_resolution_catalog()) if (sp_resolution_available(identifier.integerValue)) {
                NSValue *pixels = [NSValue valueWithCGSize:sp_mode_pixels(identifier.integerValue)];
                if (![unique containsObject:pixels]) [unique addObject:pixels];
            }
            sp_test_check(CFArrayGetCount(modes) == unique.count, @"WoW sees every supported resolution without duplicates.");
            if (!sp_scale_overridden()) {
                sp_test_check(sp_resolution_available(1920) && sp_resolution_available(2560) && sp_resolution_available(SPResolutionFullDetail),
                              @"Old availability preferences cannot hide any resolution, including full screen detail.");
                sp_test_check([unique containsObject:[NSValue valueWithCGSize:sp_resolution_pixels(points, full, YES)]],
                              @"The physical screen's full detail resolution is offered alongside the lower-power mode.");
            }
            if (!i) {
                snapshot = CFRetain(mode);
                savedPixels = m->pixels;
            } else {
                SPDisplayMode *old = (__bridge SPDisplayMode *)snapshot;
                sp_test_check(sp_CGDisplayModeGetPixelWidth(old) == savedPixels.width && sp_CGDisplayModeGetPixelHeight(old) == savedPixels.height,
                              @"A retained mode remains a snapshot after rotation.");
            }
            CGPoint at = CGPointMake(points.width * 0.25, points.height * 0.75);
            CGPoint back = sp_to_uikit(sp_from_uikit(at));
            sp_test_check(hypot(back.x - at.x, back.y - at.y) < 0.00001, @"Input coordinates round-trip at every resolution and orientation.");
            if (layer.device) {
                @autoreleasepool {
                    id<CAMetalDrawable> drawable = [layer nextDrawable];
                    sp_test_check(drawable && drawable.texture.width == expected.width && drawable.texture.height == expected.height,
                                  @"Metal allocates the expected pixel dimensions.");
                }
            }
            for (SPDisplayMode *choice in (__bridge NSArray *)modes) {
                @autoreleasepool {
                    sp_test_check(sp_CGDisplayModeGetWidth(choice) == choice->pixels.width && sp_CGDisplayModeGetHeight(choice) == choice->pixels.height,
                                  @"Enumerated mode dimensions are the selectable pixel dimensions.");
                    sp_test_check(sp_CGDisplayModeGetPixelWidth(m) >= choice->pixels.width && sp_CGDisplayModeGetPixelHeight(m) >= choice->pixels.height,
                                  @"The current display ceiling permits every listed resolution.");
                    sp_test_check(sp_CGDisplaySetDisplayMode(1, (__bridge CFTypeRef)choice, NULL) == 0,
                                  @"CoreGraphics mode selection succeeds.");
                    sp_window_track_scene();
                    sp_test_check(CGRectEqualToRect(sp_screen_rect(), (CGRect){CGPointZero, m->size}),
                                  @"Selecting a render mode never shrinks the screen bounds used by the next menu choice.");
                    SPDisplayMode *ceiling = CFBridgingRelease(sp_CGDisplayCopyDisplayMode(1));
                    sp_test_check(CGSizeEqualToSize(ceiling->pixels, m->pixels),
                                  @"The advertised pixel ceiling stays stable across resolution changes.");
                    sp_test_check(CGSizeEqualToSize(layer.drawableSize, choice->pixels), @"Selecting a listed mode changes the rendered pixels.");
                    sp_test_check(sp_CGDisplaySetDisplayMode(1, mode, NULL) == 0, @"The saved current mode can restore the previous selection.");
                    sp_window_track_scene();
                    sp_test_check(sp_resolution_now() == resolution &&
                                  (sp_scale_overridden() || [NSUserDefaults.standardUserDefaults integerForKey:@"sp_resolution"] == resolution),
                                  @"The last selected resolution is persisted for the next launch.");
                    CGFloat previousScale = sp_backing_scale();
                    CGSize requestedPoints = CGSizeMake(choice->pixels.width / previousScale, choice->pixels.height / previousScale);
                    [client setFrame:(CGRect){CGPointZero, requestedPoints} display:YES];
                    sp_window_track_scene();
                    sp_test_check(sp_resolution_now() == choice->resolution && CGSizeEqualToSize(layer.drawableSize, choice->pixels),
                                  @"A point-sized AppKit request switches resolutions from an existing fractional backing scale.");
                    [client setFrame:sp_scene_rect() display:YES];
                    sp_window_track_scene();
                    sp_test_check(sp_resolution_now() == choice->resolution && CGSizeEqualToSize(layer.drawableSize, choice->pixels),
                                  @"Reapplying the physical window frame preserves the selected render resolution.");
                    sp_select_resolution(resolution); sp_window_track_scene();
                    layer.drawableSize = choice->pixels;
                    sp_window_track_scene();
                    sp_test_check(sp_resolution_now() == choice->resolution && CGSizeEqualToSize([view convertSizeToBacking:points], choice->pixels),
                                  @"A fullscreen-windowed drawable request selects the same resolution.");
                    if (layer.device) {
                        id<CAMetalDrawable> drawable = [layer nextDrawable];
                        sp_test_check(drawable && drawable.texture.width == choice->pixels.width && drawable.texture.height == choice->pixels.height,
                                      @"Every selected mode allocates a real Metal texture at the advertised resolution.");
                    }
                }
            }
            CFRelease(modes);
            sp_select_resolution(resolution); sp_window_track_scene();
            CFRelease(mode);
        }
    }
    sp_test_check(sp_test_resizes >= 3, @"Orientation and resolution changes send resize notifications.");
    sp_test_check(sp_CGDisplaySetDisplayMode(2, snapshot, NULL) == 1001, @"Invalid display selections are rejected.");
    CFRelease(snapshot);
    sp_CGDisplayRemoveReconfigurationCallback(sp_test_display_changed, &sp_test_checks);
    NSUInteger changes = sp_test_display_changes;
    sp_display_reconfigured();
    sp_test_check(sp_test_display_changes == changes, @"Removed display observers are no longer called.");
}

@interface SPDisplayTestScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic) UIWindow *window;
@end
@implementation SPDisplayTestScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    sp_window = self.window;
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        NSString *result;
        @try {
            sp_test_run();
            result = [NSString stringWithFormat:@"PASS: %lu display checks", (unsigned long)sp_test_checks];
        } @catch (NSException *e) { result = [@"FAIL: " stringByAppendingString:e.reason]; }
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [result writeToFile:[documents stringByAppendingPathComponent:@"display-test-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    });
}
@end

@interface SPDisplayTestApp : UIResponder <UIApplicationDelegate>
@end
@implementation SPDisplayTestApp
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:nil sessionRole:session.role];
    configuration.delegateClass = SPDisplayTestScene.class;
    return configuration;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults setInteger:argc > 1 ? atoi(argv[1]) : 0 forKey:@"sp_resolution"];
        [defaults setInteger:argc > 2 ? atoi(argv[2]) : 0 forKey:@"sp_scale"];
        [defaults removeObjectForKey:@"sp_resolutions"];
        if (argc > 4) [defaults setObject:strcmp(argv[4], "nativeonly") == 0 ? @[] : @[@1920] forKey:@"sp_resolutions"];
        unsetenv("SP_SCALE");
        if (argc > 3) setenv("SP_SCALE", argv[3], 1);
        setenv("SP_HOVER_OFF", "1", 1);
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SPDisplayTestApp.class));
    }
}
