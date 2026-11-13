// Synthetic UIKit input against the actual AppKit shim. No game, account, pairing, or developer service.
#include "../../generated/libspAppKit.m"

@interface SPTestTouch : UITouch
@property(nonatomic) CGPoint at;
@property(nonatomic) UITouchPhase testPhase;
@property(nonatomic) UITouchType testType;
@property(nonatomic, weak) UIView *target;
@end
@implementation SPTestTouch
- (CGPoint)locationInView:(UIView *)view { return [view convertPoint:self.at fromView:sp_window]; }
- (UIView *)view { return self.target; }
- (UITouchPhase)phase { return self.testPhase; }
- (UITouchType)type { return self.testType; }
- (CGFloat)majorRadiusTolerance { return 1; }
@end

@interface SPTestEvent : UIEvent
@property(nonatomic) NSSet<UITouch *> *testTouches;
@property(nonatomic) UIEventButtonMask testMask;
@end
@implementation SPTestEvent
- (NSSet<UITouch *> *)allTouches { return self.testTouches; }
- (UIEventButtonMask)buttonMask { return self.testMask; }
@end

static NSUInteger sp_test_checks;
static void sp_test_check(BOOL ok, NSString *message) {
    if (!ok) @throw [NSException exceptionWithName:@"Thumb input test failed" reason:message userInfo:nil];
    sp_test_checks++;
}
static SPTestTouch *sp_test_touch(UIView *target, CGPoint at) {
    SPTestTouch *touch = [SPTestTouch new];
    touch.target = target; touch.at = at; touch.testPhase = UITouchPhaseBegan;
    touch.testType = UITouchTypeDirect;
    return touch;
}
static SPTestEvent *sp_test_event(NSArray<UITouch *> *touches) {
    SPTestEvent *event = [SPTestEvent new];
    event.testTouches = [NSSet setWithArray:touches];
    return event;
}
static void sp_test_send(SPTestTouch *touch, UITouchPhase phase, SPTestEvent *event) {
    touch.testPhase = phase;
    NSSet *set = [NSSet setWithObject:touch];
    switch (phase) {
    case UITouchPhaseBegan: [touch.target touchesBegan:set withEvent:event]; break;
    case UITouchPhaseMoved: [touch.target touchesMoved:set withEvent:event]; break;
    case UITouchPhaseEnded: [touch.target touchesEnded:set withEvent:event]; break;
    case UITouchPhaseCancelled: [touch.target touchesCancelled:set withEvent:event]; break;
    default: break;
    }
}
static NSArray<NSNumber *> *sp_test_buttons(void) {
    NSMutableArray *types = [NSMutableArray array];
    for (SPEvent *event in sp_events)
        if (event->type == SPLeftMouseDown || event->type == SPLeftMouseUp ||
            event->type == SPRightMouseDown || event->type == SPRightMouseUp ||
            event->type == SPOtherMouseDown || event->type == SPOtherMouseUp) [types addObject:@(event->type)];
    return types;
}
static void sp_test_tap(SPInputView *view, NSArray<SPTestTouch *> *others) {
    SPTestTouch *finger = sp_test_touch(view, CGPointMake(300, 200));
    SPTestEvent *event = sp_test_event([others arrayByAddingObject:finger]);
    sp_test_send(finger, UITouchPhaseBegan, event);
    sp_test_send(finger, UITouchPhaseEnded, event);
}

static void sp_test_run(SPInputView *view, SPThumbButton *thumb) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:sp_thumb_enabled_key];
    [defaults removeObjectForKey:sp_thumb_position_key];
    [defaults removeObjectForKey:sp_thumb_size_key];
    [view setNeedsLayout]; [view layoutIfNeeded];
    [sp_events removeAllObjects];
    NSMutableString *pads = [NSMutableString string];
    for (GCController *c in GCController.controllers)
        [pads appendFormat:@" [%@ / %@ / extended %d]", c.vendorName, c.productCategory, c.extendedGamepad != nil];
    sp_test_check(!thumb.hidden, [@"The thumb button is enabled by default. Controllers:" stringByAppendingString:pads]);
    sp_test_check(thumb.bounds.size.width == 76 && thumb.bounds.size.height == 76, @"The default thumb target is larger.");
    sp_test_check([view hitTest:thumb.center withEvent:nil] == thumb, @"The square owns its touch.");
    sp_test_check([view hitTest:CGPointMake(300, 200) withEvent:nil] == view, @"Other touches reach the game.");

    sp_test_tap(view, @[]);
    sp_test_check([sp_test_buttons() isEqual:@[@(SPLeftMouseDown), @(SPLeftMouseUp)]], @"An ordinary tap left-clicks.");
    [sp_events removeAllObjects];
    CGPoint pointer = sp_mouse;
    SPTestTouch *hold = sp_test_touch(thumb, thumb.center);
    SPTestEvent *heldEvent = sp_test_event(@[hold]);
    sp_test_send(hold, UITouchPhaseBegan, heldEvent);
    sp_test_check(thumb.highlighted && [thumb heldInEvent:heldEvent], @"A held square highlights and modifies clicks.");
    sp_test_check(sp_events.count == 0 && CGPointEqualToPoint(pointer, sp_mouse), @"Holding alone never clicks or moves the pointer.");
    sp_test_tap(view, @[hold]);
    sp_test_tap(view, @[hold]);
    sp_test_check([sp_test_buttons() isEqual:@[@(SPRightMouseDown), @(SPRightMouseUp), @(SPRightMouseDown), @(SPRightMouseUp)]],
                  @"One thumb hold supports repeated independent right clicks.");
    SPEvent *click = nil;
    for (SPEvent *event in sp_events) if (event->type == SPRightMouseDown) { click = event; break; }
    sp_test_check(click && CGPointEqualToPoint(click->location, sp_from_uikit(CGPointMake(300, 200))),
                  @"The click is at the other finger, not the square.");

    [sp_events removeAllObjects];
    SPTestTouch *finger = sp_test_touch(view, CGPointMake(320, 220));
    SPTestEvent *both = sp_test_event(@[hold, finger]);
    sp_test_send(finger, UITouchPhaseBegan, both);
    finger.at = CGPointMake(340, 240);
    sp_test_send(finger, UITouchPhaseMoved, both);
    BOOL rightDrag = NO;
    for (SPEvent *event in sp_events) if (event->type == SPRightMouseDragged) rightDrag = YES;
    sp_test_check(rightDrag, @"The other finger can right-drag while the thumb is held.");
    sp_test_send(hold, UITouchPhaseEnded, both);
    sp_test_check(sp_mouse_buttons == 2, @"Lifting the thumb does not change an already-held game button.");
    sp_test_send(finger, UITouchPhaseEnded, both);
    sp_test_check([sp_test_buttons() isEqual:@[@(SPRightMouseDown), @(SPRightMouseUp)]] && sp_mouse_buttons == 0,
                  @"A right click ends with right-up after the thumb lifts.");
    [sp_events removeAllObjects];
    sp_test_tap(view, @[]);
    sp_test_check([sp_test_buttons() isEqual:@[@(SPLeftMouseDown), @(SPLeftMouseUp)]], @"The next ordinary tap is left again.");

    // Same event, opposite UIKit callback orders: neither may change the chosen mouse button.
    [sp_events removeAllObjects];
    hold = sp_test_touch(thumb, thumb.center);
    finger = sp_test_touch(view, CGPointMake(300, 200)); both = sp_test_event(@[hold, finger]);
    sp_test_send(finger, UITouchPhaseBegan, both);
    sp_test_send(hold, UITouchPhaseBegan, both);
    sp_test_send(finger, UITouchPhaseEnded, both);
    sp_test_check([sp_test_buttons() isEqual:@[@(SPRightMouseDown), @(SPRightMouseUp)]], @"Simultaneous thumb-down works before its callback arrives.");
    [sp_events removeAllObjects];
    hold.testPhase = UITouchPhaseEnded;
    sp_test_tap(view, @[hold]);
    sp_test_check([sp_test_buttons() isEqual:@[@(SPLeftMouseDown), @(SPLeftMouseUp)]], @"A thumb ending in the same event no longer modifies a new tap.");
    sp_test_send(hold, UITouchPhaseEnded, both);

    [sp_events removeAllObjects];
    finger = sp_test_touch(view, CGPointMake(300, 200));
    sp_test_send(finger, UITouchPhaseBegan, sp_test_event(@[finger]));
    hold = sp_test_touch(thumb, thumb.center); both = sp_test_event(@[hold, finger]);
    sp_test_send(hold, UITouchPhaseBegan, both);
    sp_test_send(finger, UITouchPhaseEnded, both);
    sp_test_check([sp_test_buttons() isEqual:@[@(SPLeftMouseDown), @(SPLeftMouseUp)]], @"A thumb pressed later cannot change a pending left click.");

    [sp_events removeAllObjects];
    SPTestTouch *mouse = sp_test_touch(view, CGPointMake(350, 230));
    mouse.testType = UITouchTypeIndirectPointer;
    SPTestEvent *mouseEvent = sp_test_event(@[hold, mouse]); mouseEvent.testMask = UIEventButtonMaskPrimary;
    sp_test_send(mouse, UITouchPhaseBegan, mouseEvent);
    sp_test_send(mouse, UITouchPhaseEnded, mouseEvent);
    sp_test_check([sp_test_buttons() isEqual:@[@(SPLeftMouseDown), @(SPLeftMouseUp)]], @"The thumb does not remap a physical mouse.");
    sp_test_send(hold, UITouchPhaseEnded, both);

    [sp_events removeAllObjects];
    pointer = sp_mouse; CGPoint initial = thumb.center;
    hold = sp_test_touch(thumb, initial); heldEvent = sp_test_event(@[hold]);
    sp_test_send(hold, UITouchPhaseBegan, heldEvent);
    hold.at = CGPointMake(initial.x + 3, initial.y - 3);
    sp_test_send(hold, UITouchPhaseMoved, heldEvent);
    sp_test_check(CGPointEqualToPoint(thumb.center, initial), @"Small thumb drift does not reposition the square.");
    hold.at = CGPointMake(initial.x + 150, initial.y - 120);
    sp_test_send(hold, UITouchPhaseMoved, heldEvent);
    CGPoint moved = thumb.center;
    sp_test_check(!CGPointEqualToPoint(moved, initial), @"Dragging the square moves it.");
    sp_test_check(sp_events.count == 0 && CGPointEqualToPoint(pointer, sp_mouse), @"Dragging the square never reaches the game.");
    sp_test_send(hold, UITouchPhaseEnded, heldEvent);
    sp_test_check([defaults arrayForKey:sp_thumb_position_key].count == 2, @"The position is persisted.");
    SPThumbButton *restored = [[SPThumbButton alloc] initWithFrame:CGRectZero];
    CGRect safe = CGRectIntersection(UIEdgeInsetsInsetRect(view.bounds, view.safeAreaInsets), sp_game_rect());
    [restored layoutInRect:safe];
    sp_test_check(hypot(restored.center.x - moved.x, restored.center.y - moved.y) < 0.01, @"A fresh control restores the saved position.");
    CGRect smaller = CGRectMake(20, 10, 350, 250);
    [restored layoutInRect:smaller];
    sp_test_check(CGRectContainsRect(smaller, restored.frame), @"A resized screen keeps the square inside its safe area.");
    hold = sp_test_touch(thumb, thumb.center); heldEvent = sp_test_event(@[hold]);
    sp_test_send(hold, UITouchPhaseBegan, heldEvent);
    hold.at = CGPointMake(-1000, -1000);
    sp_test_send(hold, UITouchPhaseMoved, heldEvent);
    sp_test_send(hold, UITouchPhaseEnded, heldEvent);
    sp_test_check(CGRectContainsRect(safe, thumb.frame), @"Dragging beyond the screen is clamped.");

    [sp_events removeAllObjects];
    hold = sp_test_touch(thumb, thumb.center); finger = sp_test_touch(view, CGPointMake(300, 200));
    both = sp_test_event(@[hold, finger]);
    sp_test_send(hold, UITouchPhaseBegan, both); sp_test_send(finger, UITouchPhaseBegan, both);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    sp_test_check(!thumb.highlighted && sp_mouse_buttons == 0, @"App deactivation releases the modifier and game button.");
    sp_test_check([sp_test_buttons() isEqual:@[@(SPRightMouseDown), @(SPRightMouseUp)]], @"Cancellation balances right-down with right-up.");
    [sp_events removeAllObjects]; sp_test_tap(view, @[]);
    sp_test_check([sp_test_buttons() isEqual:@[@(SPLeftMouseDown), @(SPLeftMouseUp)]], @"Input recovers after deactivation.");

    [defaults setBool:NO forKey:sp_thumb_enabled_key]; [view setNeedsLayout]; [view layoutIfNeeded];
    sp_test_check(thumb.hidden && ![thumb heldInEvent:both], @"Settings can disable the modifier.");
    [defaults removeObjectForKey:sp_thumb_enabled_key];
    [defaults removeObjectForKey:sp_thumb_position_key]; [view setNeedsLayout]; [view layoutIfNeeded];
    sp_test_check(hypot(thumb.center.x - initial.x, thumb.center.y - initial.y) < 0.01, @"Reset returns to the default position.");
    [defaults setObject:@[@"bad", @1] forKey:sp_thumb_position_key]; [view setNeedsLayout]; [view layoutIfNeeded];
    sp_test_check(CGPointEqualToPoint(thumb.center, initial), @"Malformed saved coordinates fall back safely.");
    [defaults setObject:@[@(-20), @100] forKey:sp_thumb_position_key]; [view setNeedsLayout]; [view layoutIfNeeded];
    sp_test_check(CGRectContainsRect(safe, thumb.frame), @"Out-of-range saved coordinates are clamped.");
    [defaults removeObjectForKey:sp_thumb_position_key]; [view setNeedsLayout]; [view layoutIfNeeded];

    // Preferred size persists independently of position, including when a small window must shrink it.
    [defaults setDouble:152 forKey:sp_thumb_size_key]; [view setNeedsLayout]; [view layoutIfNeeded];
    sp_test_check(thumb.bounds.size.width == 152 && CGRectContainsRect(safe, thumb.frame), @"A larger size stays inside the safe area.");
    [restored layoutInRect:safe];
    sp_test_check(restored.bounds.size.width == 152 && CGPointEqualToPoint(restored.center, thumb.center), @"A fresh control restores size and position.");
    [restored layoutInRect:CGRectMake(0, 0, 100, 90)];
    sp_test_check(restored.bounds.size.width == 74 && CGRectContainsRect(CGRectMake(0, 0, 100, 90), restored.frame), @"A small window temporarily shrinks a large target.");
    [restored layoutInRect:safe];
    sp_test_check(restored.bounds.size.width == 152, @"The preferred size returns when the window grows.");
    [defaults setDouble:44 forKey:sp_thumb_size_key]; [view setNeedsLayout]; [view layoutIfNeeded];
    sp_test_check(thumb.bounds.size.width == 44, @"The minimum size is a usable touch target.");
    [defaults setDouble:-100 forKey:sp_thumb_size_key]; [view setNeedsLayout]; [view layoutIfNeeded];
    sp_test_check(thumb.bounds.size.width == 44, @"Saved sizes below the range are clamped.");
    [defaults setDouble:1000 forKey:sp_thumb_size_key]; [view setNeedsLayout]; [view layoutIfNeeded];
    sp_test_check(thumb.bounds.size.width == 152, @"Saved sizes above the range are clamped.");
    [defaults setObject:@"invalid" forKey:sp_thumb_size_key]; [view setNeedsLayout]; [view layoutIfNeeded];
    sp_test_check(thumb.bounds.size.width == 76, @"Malformed saved sizes fall back to the default.");
    hold = sp_test_touch(thumb, thumb.center); heldEvent = sp_test_event(@[hold]);
    sp_test_send(hold, UITouchPhaseBegan, heldEvent); hold.testPhase = UITouchPhaseStationary;
    [defaults setDouble:100 forKey:sp_thumb_size_key]; [view setNeedsLayout]; [view layoutIfNeeded];
    sp_test_check(!thumb.highlighted && ![thumb heldInEvent:heldEvent], @"Resizing cancels a held modifier without reviving its stationary touch.");
    [defaults removeObjectForKey:sp_thumb_size_key]; [view setNeedsLayout]; [view layoutIfNeeded];

    // The old chord path is still usable when neither finger is on the square.
    [sp_events removeAllObjects];
    SPTestTouch *a = sp_test_touch(view, CGPointMake(280, 200)), *b = sp_test_touch(view, CGPointMake(320, 200));
    NSSet *pair = [NSSet setWithArray:@[a, b]]; SPTestEvent *pairEvent = sp_test_event(@[a, b]);
    [view touchesBegan:pair withEvent:pairEvent];
    a.testPhase = b.testPhase = UITouchPhaseEnded; [view touchesEnded:pair withEvent:pairEvent];
    sp_test_check([sp_test_buttons() isEqual:@[@(SPRightMouseDown), @(SPRightMouseUp)]], @"Existing two-finger right clicks are preserved.");
}

static void sp_test_pencil(SPInputView *view, SPThumbButton *thumb) {
    [sp_events removeAllObjects];
    SPTestTouch *pencil = sp_test_touch(view, CGPointMake(320, 220));
    pencil.testType = UITouchTypePencil;
    SPTestEvent *event = sp_test_event(@[pencil]);
    sp_test_send(pencil, UITouchPhaseBegan, event);
    sp_test_check([sp_test_buttons() isEqual:@[@(SPLeftMouseDown)]], @"An unmodified Pencil presses left immediately, without waiting for a finger chord.");
    sp_test_send(pencil, UITouchPhaseEnded, event);
    sp_test_check([sp_test_buttons() isEqual:@[@(SPLeftMouseDown), @(SPLeftMouseUp)]], @"An unmodified Pencil tap releases left.");

    // Exercise both UIKit callback orders, early thumb release, and cancellation through the real shim.
    for (NSUInteger mode = 0; mode < 3; mode++) {
        [sp_events removeAllObjects];
        SPTestTouch *hold = sp_test_touch(thumb, thumb.center);
        pencil = sp_test_touch(view, CGPointMake(320, 220)); pencil.testType = UITouchTypePencil;
        event = sp_test_event(@[hold, pencil]);
        if (mode == 0) sp_test_send(hold, UITouchPhaseBegan, event);
        sp_test_send(pencil, UITouchPhaseBegan, event);
        if (mode != 0) sp_test_send(hold, UITouchPhaseBegan, event);
        sp_test_check([sp_test_buttons() isEqual:@[@(SPRightMouseDown)]], @"R modifies Pencil even when the Pencil callback arrives first.");
        SPEvent *down = sp_events.lastObject;
        sp_test_check(CGPointEqualToPoint(down->location, sp_from_uikit(pencil.at)), @"The Pencil right-click is at its tip, not the R square.");
        pencil.at = CGPointMake(360, 250);
        sp_test_send(pencil, UITouchPhaseMoved, event);
        sp_test_check(((SPEvent *)sp_events.lastObject)->type == SPRightMouseDragged, @"R plus Pencil movement sends a right-button drag.");
        if (mode == 1) {
            sp_test_send(hold, UITouchPhaseEnded, event);
            sp_test_check(sp_mouse_buttons == 2, @"Lifting R keeps the Pencil's right button held.");
            pencil.at = CGPointMake(380, 270);
            sp_test_send(pencil, UITouchPhaseMoved, event);
            sp_test_check(((SPEvent *)sp_events.lastObject)->type == SPRightMouseDragged, @"Pencil keeps right-dragging after R lifts.");
        }
        sp_test_send(pencil, mode == 2 ? UITouchPhaseCancelled : UITouchPhaseEnded, event);
        sp_test_check([sp_test_buttons() isEqual:@[@(SPRightMouseDown), @(SPRightMouseUp)]] && sp_mouse_buttons == 0,
                      @"Pencil lift or cancellation balances the right press without a left click.");
        if (mode != 1) sp_test_send(hold, UITouchPhaseEnded, event);
    }

    [sp_events removeAllObjects];
    pencil = sp_test_touch(view, CGPointMake(320, 220)); pencil.testType = UITouchTypePencil;
    event = sp_test_event(@[pencil]);
    sp_test_send(pencil, UITouchPhaseBegan, event);
    SPTestTouch *hold = sp_test_touch(thumb, thumb.center);
    event = sp_test_event(@[hold, pencil]);
    sp_test_send(hold, UITouchPhaseBegan, event);
    sp_test_send(pencil, UITouchPhaseEnded, event);
    sp_test_check([sp_test_buttons() isEqual:@[@(SPLeftMouseDown), @(SPLeftMouseUp)]], @"Pressing R after Pencil lands leaves the current left click unchanged.");
    sp_test_send(hold, UITouchPhaseEnded, event);
}

#include "joystick-input.m"
#include "keyboard-input.m"

@interface SPThumbTestScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic) UIWindow *window;
@end
@implementation SPThumbTestScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    sp_window = self.window;
    UIViewController *controller = [UIViewController new];
    SPInputView *view = [[SPInputView alloc] initWithFrame:self.window.bounds];
    controller.view = view; self.window.rootViewController = controller;
    view.backgroundColor = [UIColor colorWithRed:0.06 green:0.1 blue:0.085 alpha:1];
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        SPThumbButton *thumb = nil;
        SPJoystick *stick = nil;
        for (UIView *child in view.subviews) {
            if ([child isKindOfClass:SPThumbButton.class]) thumb = (id)child;
            if ([child isKindOfClass:SPJoystick.class]) stick = (id)child;
        }
        @try { sp_test_run(view, thumb); sp_test_pencil(view, thumb); sp_test_keyboard(view, thumb); }
        @catch (NSException *exception) { [self finish:exception.reason inView:view]; return; }
        sp_test_space_ring(view, ^(NSString *error) {
            if (error) { [self finish:error inView:view]; return; }
            sp_test_joystick(view, thumb, stick, ^(NSString *error) { [self finish:error inView:view]; });
        });
    });
}
- (void)finish:(NSString *)error inView:(SPInputView *)view {
        if (!error) {
            for (NSString *name in @[@"ctrl", @"shift", @"alt", @"space"])
                [NSUserDefaults.standardUserDefaults setBool:YES forKey:[NSString stringWithFormat:@"sp_%@_enabled", name]];
            [view setNeedsLayout]; [view layoutIfNeeded];
        }
        NSString *result = error ? [@"FAIL: " stringByAppendingString:error]
                                : [NSString stringWithFormat:@"PASS: %lu thumb input checks", (unsigned long)sp_test_checks];
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [result writeToFile:[documents stringByAppendingPathComponent:@"thumb-test-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(80, 70, view.bounds.size.width - 160, 180)];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth; label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentCenter; label.textColor = UIColor.whiteColor;
        label.font = [UIFont systemFontOfSize:23 weight:UIFontWeightMedium];
        label.text = [result stringByAppendingString:@"\n\nHold R + tap elsewhere to right-click.\nHold Ctrl, Shift, or Alt to modify input.\nHold the joystick arrow or anywhere in Space for 2 s, then drag.\nReal virtual controller; no game loaded."];
        label.userInteractionEnabled = NO; [view addSubview:label];
}
@end

@interface SPThumbTestDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation SPThumbTestDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session
                             options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:nil sessionRole:session.role];
    configuration.delegateClass = SPThumbTestScene.class;
    return configuration;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(SPThumbTestDelegate.class)); }
}
