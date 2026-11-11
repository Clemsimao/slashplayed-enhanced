// The loading screen: from the moment the launcher loads the client until the client presents its first
// frame, the scene shows the game's name and what it's doing, in the start screen's look (spstartscreen.swift,
// spstyle.swift: its ground and gold, Goodmountain, and frames drawn in code), instead of black. UIKit and
// Core Animation, not SwiftUI as the launcher's screens are: SwiftUI updates on the run loop's turns, and
// the client holds the main thread for most of the time this is up (below). #included in the generated libspAppKit.m (gen_stubs.py EXTRA_INCLUDES),
// after spuikit.m, before sphover.m, whose present hooks call sp_loading_frame.
//
// From an empty store that's two long spans: the client's data setup (about 13 s on an iPhone; its
// progress dialog, which spnotice.m in the CoreFoundation shim keeps, is never drawn) and then about 90 s
// with its window up and no frames while it streams its startup data. On a full store it's the client's
// few seconds of startup. In both spans the client holds the main thread (it waits in run loop modes of
// its own and doesn't pump events, so UIKit's run loop doesn't turn), so nothing here waits for UIKit
// to commit: each change is committed with an explicit CATransaction flush, and the spinner is a Core
// Animation animation, which the render server runs with the main thread blocked.
//
// The setup's progress comes from spnotice.m as a notification (the two shims are separate libraries):
// SPDataSetupProgress, userInfo percent (0-100, or -1 when the client's setup is done). Our own wording,
// never the dialog's text. With SP_HOVER_OFF=1 the client's presents aren't hooked (sphover.m), so
// nothing would say when to take the screen down: there's none.
//
// SP_LOADING_DRILL, for screenshots: `loading` keeps the screen up past the client's first frame (it
// sits above the game's layer), and a number 0-100 does that showing the setup's progress at that
// percent, whatever the client reports.

static NSString *sp_loading_title;  // the game's name; set once the launcher asks for the screen
static UIView *sp_loading_view;
static UILabel *sp_loading_status;
static UIView *sp_loading_bar;      // the progress bar's frame; its fill is sp_loading_fill
static CAShapeLayer *sp_loading_fill;
static int sp_loading_drill = -2;  // SP_LOADING_DRILL: -2 none, -1 `loading`, else the percent shown
static UIActivityIndicatorView *sp_loading_spinner;
static CFAbsoluteTime sp_loading_since;
static _Atomic int sp_loading_presented;  // the client's first present has been seen

// Its own lines, "[sp:AppKit] loading: …", like the launcher's "[sp:launch] update: …": not through
// sp_stub_log, whose "stub hit:" is for the client's calls into stubs, which these aren't.
static void sp_loading_say(NSString *s) {
    os_log(OS_LOG_DEFAULT, "[sp:AppKit] loading: %{public}s", s.UTF8String);
    fprintf(stderr, "[sp:AppKit] loading: %s\n", s.UTF8String);
}

// Commit now: the client may not let UIKit's run loop turn for a minute or more.
static void sp_loading_commit(void) {
    [sp_loading_view layoutIfNeeded];
    [NSClassFromString(@"CATransaction") flush];  // not linked directly, as spwindow.m
}

// The start screen's colors (spstartscreen.swift, spstyle.swift): the icon's ground and gold.
static UIColor *sp_loading_rgb(uint32_t hex, CGFloat alpha) {
    return [UIColor colorWithRed:(hex >> 16 & 0xff) / 255.0 green:(hex >> 8 & 0xff) / 255.0 blue:(hex & 0xff) / 255.0 alpha:alpha];
}
#define SP_LOADING_GROUND sp_loading_rgb(0x101916, 1)
#define SP_LOADING_GOLD sp_loading_rgb(0xAC9D79, 1)

// spstyle.swift's Octagon: `r` with each corner cut `cut` points along both sides.
static CGPathRef sp_loading_octagon(CGRect r, CGFloat cut) {
    CGMutablePathRef p = CGPathCreateMutable();
    CGFloat x = r.origin.x, y = r.origin.y, X = CGRectGetMaxX(r), Y = CGRectGetMaxY(r);
    CGPathMoveToPoint(p, NULL, x + cut, y);
    CGPathAddLineToPoint(p, NULL, X - cut, y);
    CGPathAddLineToPoint(p, NULL, X, y + cut);
    CGPathAddLineToPoint(p, NULL, X, Y - cut);
    CGPathAddLineToPoint(p, NULL, X - cut, Y);
    CGPathAddLineToPoint(p, NULL, x + cut, Y);
    CGPathAddLineToPoint(p, NULL, x, Y - cut);
    CGPathAddLineToPoint(p, NULL, x, y + cut);
    CGPathCloseSubpath(p);
    return p;
}

// The progress bar, 240 by 14: a gold octagon frame, the ground inside it, and a gold fill 3 points in
// that grows with the percent, its ends cut to match.
static UIView *sp_loading_make_bar(void) {
    CGRect b = CGRectMake(0, 0, 240, 14);
    UIView *bar = [[UIView alloc] initWithFrame:b];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [bar.widthAnchor constraintEqualToConstant:b.size.width].active = YES;
    [bar.heightAnchor constraintEqualToConstant:b.size.height].active = YES;
    CAShapeLayer *frame = [NSClassFromString(@"CAShapeLayer") layer];  // QuartzCore isn't linked (spwindow.m)
    CGPathRef outline = sp_loading_octagon(CGRectInset(b, 0.75, 0.75), 4);
    frame.path = outline;
    CGPathRelease(outline);
    frame.fillColor = SP_LOADING_GROUND.CGColor;
    frame.strokeColor = SP_LOADING_GOLD.CGColor;
    frame.lineWidth = 1.5;
    [bar.layer addSublayer:frame];
    sp_loading_fill = [NSClassFromString(@"CAShapeLayer") layer];
    sp_loading_fill.fillColor = SP_LOADING_GOLD.CGColor;
    [bar.layer addSublayer:sp_loading_fill];
    return bar;
}

static void sp_loading_set_fill(double fraction) {
    CGRect inner = CGRectMake(3, 3, 234, 8);
    inner.size.width = MAX(inner.size.width * MIN(MAX(fraction, 0), 1), 0);
    Class transaction = NSClassFromString(@"CATransaction");
    [transaction begin];
    [transaction setDisableActions:YES];  // no implicit animation: each step is drawn as it's committed
    CGPathRef p = inner.size.width > 0 ? sp_loading_octagon(inner, MIN(2.5, inner.size.width / 2)) : NULL;
    sp_loading_fill.path = p;
    if (p) CGPathRelease(p);
    [transaction commit];
}

// Goodmountain at `size`, scaled like `style` up to `maximum`: the launcher registered it for the process
// before it asked for this screen (launcher.m); the system font stands in when it didn't.
static UIFont *sp_loading_face(CGFloat size, UIFontTextStyle style, CGFloat maximum) {
    UIFont *font = [UIFont fontWithName:@"Goodmountain-Regular" size:size] ?: [UIFont systemFontOfSize:size weight:UIFontWeightBold];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:font maximumPointSize:maximum];
}

// percent 0-100 during the setup; -1 before it and after.
static void sp_loading_show_progress(int percent) {
    if (!sp_loading_view) return;
    if (sp_loading_drill >= 0) percent = sp_loading_drill;
    BOOL setup = percent >= 0;
    sp_loading_status.text = setup ? [NSString stringWithFormat:@"Preparing game data… %d%%", MIN(percent, 100)]
                                   : @"Loading…";
    sp_loading_bar.hidden = !setup;
    if (setup) sp_loading_set_fill(MIN(percent, 100) / 100.0);
    sp_loading_spinner.hidden = setup;
    sp_loading_commit();
}

// On the root view, above the client's CAMetalLayer (added later, as a sublayer) and the hover overlay
// (zPosition 1000), under the cursor (2000). Once the root view exists: at once when UIKit started early
// (iOS), else when the scene connects (spuikit.m; visionOS).
static void sp_loading_attach(void) {
    UIView *root = sp_window.rootViewController.view;
    if (!sp_loading_title || sp_loading_view || sp_loading_presented || !root) return;
    UIView *view = [[UIView alloc] initWithFrame:root.bounds];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.backgroundColor = SP_LOADING_GROUND;
    view.userInteractionEnabled = NO;
    view.layer.zPosition = 1500;
    UILabel *title = [[UILabel alloc] init];
    title.text = sp_loading_title;
    title.textColor = SP_LOADING_GOLD;
    title.font = sp_loading_face(34, UIFontTextStyleLargeTitle, 56);
    title.textAlignment = NSTextAlignmentCenter;
    title.numberOfLines = 0;
    sp_loading_status = [[UILabel alloc] init];
    sp_loading_status.textColor = [SP_LOADING_GOLD colorWithAlphaComponent:0.85];
    sp_loading_status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    sp_loading_status.font = [UIFont monospacedDigitSystemFontOfSize:sp_loading_status.font.pointSize
                                                              weight:UIFontWeightRegular];  // the percentage doesn't jiggle
    sp_loading_bar = sp_loading_make_bar();
    sp_loading_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    sp_loading_spinner.color = SP_LOADING_GOLD;
    [sp_loading_spinner startAnimating];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, sp_loading_spinner, sp_loading_bar,
                                                                         sp_loading_status]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 16;
    [stack setCustomSpacing:24 afterView:title];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:stack];
    // In the safe area: an iPhone's Dynamic Island is at one side in landscape.
    UILayoutGuide *guide = view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:guide.centerYAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToAnchor:guide.widthAnchor constant:-40],
    ]];
    [root addSubview:view];
    sp_loading_view = view;
    sp_loading_show_progress(-1);
    sp_loading_say([NSString stringWithFormat:@"screen up, %.1f s after the client was asked for",
                    CFAbsoluteTimeGetCurrent() - sp_loading_since]);
}

static void sp_loading_remove(void) {
    if (!sp_loading_view) return;
    [sp_loading_view removeFromSuperview];
    sp_loading_view = nil;
    sp_loading_status = nil;
    sp_loading_bar = nil;
    sp_loading_fill = nil;
    sp_loading_spinner = nil;
    [NSClassFromString(@"CATransaction") flush];
    sp_loading_say([NSString stringWithFormat:@"first frame %.1f s after the client was asked for, screen down",
                    CFAbsoluteTimeGetCurrent() - sp_loading_since]);
}

// Each present (sphover.m), on whichever thread the client presents from: the first takes the screen
// down. Not inline: the main thread is the client's, so the screen goes on the next UIKit turn, which
// comes with the client's first frames.
static void sp_loading_frame(void) {
#if !TARGET_OS_VISION
    // Controller discovery must happen after the game has initialized, rather than on the launcher's
    // early UIKit screen. Keep this independent of a loading-screen screenshot drill.
    if (!atomic_exchange(&sp_game_presented, true))
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter postNotificationName:@"SPGameFirstFrame" object:nil];
        });
#endif
    if (sp_loading_drill != -2 || sp_loading_presented || atomic_exchange(&sp_loading_presented, 1)) return;
    dispatch_async(dispatch_get_main_queue(), ^{ sp_loading_remove(); });
}

// The launcher (apps/client/launcher.m), just before it loads the client: the screen, for the game named
// `title`. Before UIKit is up (visionOS), it goes up when the scene connects.
__attribute__((visibility("default"))) void sp_uikit_loading(const char *title) {
    if (getenv("SP_HOVER_OFF") || sp_loading_title) return;
    sp_loading_title = @(title);
    const char *drill = getenv("SP_LOADING_DRILL");
    if (drill && !strcmp(drill, "loading")) sp_loading_drill = -1;
    else if (drill && *drill) sp_loading_drill = MIN(MAX(atoi(drill), 0), 100);
    sp_loading_since = CFAbsoluteTimeGetCurrent();
    [NSNotificationCenter.defaultCenter addObserverForName:@"SPDataSetupProgress" object:nil queue:nil
                                                usingBlock:^(NSNotification *n) {
        int percent = [n.userInfo[@"percent"] intValue];
        if (NSThread.isMainThread) sp_loading_show_progress(percent);
        else dispatch_async(dispatch_get_main_queue(), ^{ sp_loading_show_progress(percent); });
    }];
    sp_loading_attach();
}
