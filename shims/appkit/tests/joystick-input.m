// Included by thumb-button.m: exercise Apple's real virtual GCController as well as touch isolation.
static void sp_test_wait_stick(SPJoystick *stick, int attempts, void (^done)(NSString *)) {
    if (stick.controller) { done(nil); return; }
    if (!attempts) { done(@"Virtual left controller did not connect."); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{
        sp_test_wait_stick(stick, attempts - 1, done);
    });
}
static void sp_test_stick_steps(NSArray<dispatch_block_t> *steps, NSUInteger index, void (^done)(NSString *)) {
    if (index == steps.count) { done(nil); return; }
    @try { steps[index](); }
    @catch (NSException *e) { done(e.reason); return; }
    // Values propagate through the real GameController service between touch changes and assertions.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 6), dispatch_get_main_queue(), ^{
        sp_test_stick_steps(steps, index + 1, done);
    });
}
static BOOL sp_test_axis(SPJoystick *stick, CGFloat x, CGFloat y) {
    GCExtendedGamepad *pad = stick.controller.extendedGamepad;
    return pad && fabs(pad.leftThumbstick.xAxis.value - x) < 0.03 && fabs(pad.leftThumbstick.yAxis.value - y) < 0.03;
}
static void sp_test_wait_axis(SPJoystick *stick, CGFloat x, CGFloat y, int attempts, void (^done)(NSString *)) {
    if (sp_test_axis(stick, x, y)) { done(nil); return; }
    if (!attempts) { done(@"The first held touch did not reach the newly connected controller."); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 20), dispatch_get_main_queue(), ^{
        sp_test_wait_axis(stick, x, y, attempts - 1, done);
    });
}
static void sp_test_shield(SPInputView *view, SPThumbButton *thumb, SPJoystick *stick) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    CGRect safe = CGRectIntersection(UIEdgeInsetsInsetRect(view.bounds, view.safeAreaInsets), sp_game_rect());
    [defaults setObject:@[@0.45, @0.45] forKey:sp_joystick_position_key];
    [stick layoutInRect:safe];
    CGFloat r = stick.bounds.size.width / 2, margin = sp_joystick_touch_margin;
    [sp_events removeAllObjects];
    for (int i = 0; i < 8; i++) {
        CGFloat angle = i * M_PI / 4;
        CGPoint at = CGPointMake(stick.center.x + cos(angle) * (r + margin - 2),
                                 stick.center.y + sin(angle) * (r + margin - 2));
        UIView *target = [view hitTest:at withEvent:nil];
        sp_test_check([target isKindOfClass:SPJoystickShield.class], @"Every side and diagonal of the outer margin absorbs touch.");
        SPTestTouch *touch = sp_test_touch(target, at);
        SPTestEvent *event = sp_test_event(@[touch]);
        sp_test_send(touch, UITouchPhaseBegan, event);
        touch.at = stick.center;
        sp_test_send(touch, UITouchPhaseMoved, event);
        touch.at = CGPointMake(300, 200);
        sp_test_send(touch, UITouchPhaseMoved, event);
        sp_test_send(touch, UITouchPhaseEnded, event);
    }
    sp_test_check(sp_events.count == 0 && CGPointEqualToPoint(stick.value, CGPointZero),
                  @"A margin touch cannot become a click, drag, or joystick movement after drifting elsewhere.");
    CGPoint outside = CGPointMake(stick.center.x + r + margin + 2, stick.center.y);
    sp_test_check([view hitTest:outside withEvent:nil] == view, @"Beyond the margin, touches reach the game.");
    SPTestTouch *tap = sp_test_touch(view, outside); SPTestEvent *tapEvent = sp_test_event(@[tap]);
    sp_test_send(tap, UITouchPhaseBegan, tapEvent); sp_test_send(tap, UITouchPhaseEnded, tapEvent);
    sp_test_check([sp_test_buttons() isEqual:@[@(SPLeftMouseDown), @(SPLeftMouseUp)]], @"A tap beyond the shield still clicks normally.");
    CGPoint halo = CGPointMake(stick.center.x + r + margin / 2, stick.center.y);
    SPTestTouch *mouse = sp_test_touch(view, halo); mouse.testType = UITouchTypeIndirectPointer;
    sp_test_check([view hitTest:halo withEvent:sp_test_event(@[mouse])] == view, @"The invisible touch margin does not block hardware pointer clicks.");
    CGPoint thumbCenter = thumb.center;
    thumb.center = halo;
    sp_test_check([view hitTest:halo withEvent:nil] == thumb, @"The R control stays usable above an overlapping shield.");
    thumb.center = thumbCenter;
    [defaults setDouble:260 forKey:sp_joystick_size_key]; [stick layoutInRect:safe];
    r = stick.bounds.size.width / 2;
    CGPoint inner = CGPointMake(stick.center.x + r + margin - 2, stick.center.y);
    outside = CGPointMake(stick.center.x + r + margin + 2, stick.center.y);
    sp_test_check([[view hitTest:inner withEvent:nil] isKindOfClass:SPJoystickShield.class] &&
                  [view hitTest:outside withEvent:nil] == view, @"Resizing keeps the margin at the same physical width.");
    [defaults removeObjectForKey:sp_joystick_position_key];
    [defaults removeObjectForKey:sp_joystick_size_key];
    [stick layoutInRect:safe];
    [sp_events removeAllObjects];
}
static void sp_test_move_hold(SPInputView *view, SPJoystick *stick, void (^done)(NSString *)) {
    SPJoystickHandle *handle;
    for (UIView *child in stick.subviews) if ([child isKindOfClass:SPJoystickHandle.class]) handle = (id)child;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    CGRect safe = CGRectIntersection(UIEdgeInsetsInsetRect(view.bounds, view.safeAreaInsets), sp_game_rect());
    CGPoint center = stick.center, at = [view convertPoint:CGPointMake(22, 22) fromView:handle];
    SPTestTouch *tap = sp_test_touch(handle, at);
    sp_test_send(tap, UITouchPhaseBegan, sp_test_event(@[tap]));
    sp_test_send(tap, UITouchPhaseEnded, sp_test_event(@[tap]));
    SPTestTouch *hold = sp_test_touch(handle, at);
    sp_test_send(hold, UITouchPhaseBegan, sp_test_event(@[hold]));
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        @try {
            sp_test_check(!handle.highlighted && CGPointEqualToPoint(stick.center, center), @"A one-second arrow hold cannot reposition the joystick.");
            CAShapeLayer *progress = nil;
            for (CALayer *layer in handle.layer.sublayers) if ([layer isKindOfClass:CAShapeLayer.class]) progress = (id)layer;
            CGFloat visibleProgress = ((CAShapeLayer *)progress.presentationLayer).strokeEnd;
            sp_test_check(progress && visibleProgress > 0 && visibleProgress < 1, @"The move arrow visibly fills its border while waiting.");
            hold.at = CGPointMake(at.x + 2, at.y);
            sp_test_send(hold, UITouchPhaseMoved, sp_test_event(@[hold]));
        } @catch (NSException *e) { done(e.reason); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 13 * NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{
            @try {
                sp_test_check(handle.highlighted, @"A real two-second hold unlocks the move arrow.");
                sp_test_check(CGPointEqualToPoint(stick.center, center), @"Unlocking does not jump the joystick after minor thumb drift.");
                [sp_events removeAllObjects];
                hold.at = CGPointMake(at.x + 180, at.y - 160);
                sp_test_send(hold, UITouchPhaseMoved, sp_test_event(@[hold]));
                sp_test_check(!CGPointEqualToPoint(stick.center, center), @"Dragging after the hold repositions the joystick.");
                sp_test_check(CGPointEqualToPoint(stick.value, CGPointZero) && sp_events.count == 0, @"An unlocked move still emits neither character movement nor clicks.");
                CGPoint moved = stick.center;
                sp_test_send(hold, UITouchPhaseEnded, sp_test_event(@[hold]));
                sp_test_check(!handle.highlighted, @"Lifting the thumb relocks the move arrow.");
                sp_test_check([defaults arrayForKey:sp_joystick_position_key].count == 2, @"The held-and-dragged position is saved.");
                SPJoystick *restored = [[SPJoystick alloc] initWithFrame:CGRectZero]; [restored layoutInRect:safe];
                sp_test_check(hypot(restored.center.x - moved.x, restored.center.y - moved.y) < 0.01, @"A fresh joystick restores the held-and-dragged position.");
            } @catch (NSException *e) { done(e.reason); return; }
            CGPoint moved = stick.center;
            CGPoint newAt = [view convertPoint:CGPointMake(22, 22) fromView:handle];
            SPTestTouch *cancelled = sp_test_touch(handle, newAt);
            sp_test_send(cancelled, UITouchPhaseBegan, sp_test_event(@[cancelled]));
            [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 23 * NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{
                @try {
                    sp_test_check(!handle.highlighted && CGPointEqualToPoint(stick.center, moved), @"An app switch cancels the pending two-second unlock.");
                    cancelled.at = CGPointMake(newAt.x + 120, newAt.y - 80);
                    sp_test_send(cancelled, UITouchPhaseMoved, sp_test_event(@[cancelled]));
                    sp_test_check(CGPointEqualToPoint(stick.center, moved), @"A cancelled hold cannot drag the joystick later.");
                    [defaults removeObjectForKey:sp_joystick_position_key]; [stick layoutInRect:safe];
                    [view sp_resume_touch:nil];
                } @catch (NSException *e) { done(e.reason); return; }
                sp_test_wait_stick(stick, 120, done);
            });
        });
    });
}

static void sp_test_joystick(SPInputView *view, SPThumbButton *thumb, SPJoystick *stick, void (^done)(NSString *)) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in @[sp_joystick_enabled_key, sp_joystick_size_key, sp_joystick_position_key]) [defaults removeObjectForKey:key];
    [view setNeedsLayout]; [view layoutIfNeeded];
    [view sp_resume_touch:nil];
    BOOL launcherDisconnected = stick.controller == nil;
    __block NSUInteger frames = 0;
    id frameObserver = [NSNotificationCenter.defaultCenter addObserverForName:@"SPGameFirstFrame" object:nil queue:nil
                                                                 usingBlock:^(NSNotification *n) { frames++; }];
    sp_loading_frame(); sp_loading_frame();  // a first rendered frame, without loading any game
    // Reproduce a startup deactivation whose matching resume did not reach this input view. The
    // scene itself is active: a new real touch must recover without an app-switch cycle.
    [view sp_suspend_touch:nil];
    void (^run)(NSString *) = ^(NSString *error) {
        [NSNotificationCenter.defaultCenter removeObserver:frameObserver];
        if (error) { done(error); return; }
        __block SPTestTouch *finger, *hold, *handleTouch;
        __block SPJoystickHandle *handle;
        __block GCController *oldController;
        __block CGPoint pointer;
        CGRect safe = CGRectIntersection(UIEdgeInsetsInsetRect(view.bounds, view.safeAreaInsets), sp_game_rect());
        NSArray<dispatch_block_t> *steps = @[
            ^{
                sp_test_check(launcherDisconnected, @"The launcher does not connect a controller before the game starts.");
                sp_test_check(frames == 1, @"The first game frame announces readiness exactly once.");
                sp_test_check(!stick.hidden && stick.bounds.size.width == 156, @"The joystick is enabled at its default size.");
                sp_test_check([GCController.controllers containsObject:stick.controller], @"The virtual stick is enumerated as a connected controller.");
                sp_test_check(sp_test_axis(stick, 0, 0), @"The real controller starts neutral.");
                sp_test_check([view hitTest:stick.center withEvent:nil] == stick, @"The joystick owns its touch.");
                sp_test_check(!CGRectIntersectsRect(thumb.frame, stick.frame), @"Default R and joystick targets do not overlap on iPad.");
                sp_test_shield(view, thumb, stick);
                [sp_events removeAllObjects]; pointer = sp_mouse;
                finger = sp_test_touch(stick, CGPointMake(stick.center.x + 2, stick.center.y));
                sp_test_send(finger, UITouchPhaseBegan, sp_test_event(@[finger]));
            },
            ^{
                sp_test_check(sp_test_axis(stick, 0, 0), @"Small thumb jitter is inside the dead zone.");
                finger.at = CGPointMake(stick.center.x + stick.bounds.size.width * 0.30 * 0.56, stick.center.y);
                sp_test_send(finger, UITouchPhaseMoved, sp_test_event(@[finger]));
            },
            ^{
                sp_test_check(sp_test_axis(stick, 0.5, 0), @"A partial push reaches the real controller as an analog axis.");
                sp_test_check(sp_events.count == 0 && CGPointEqualToPoint(pointer, sp_mouse), @"Joystick input never clicks or moves the mouse.");
                CGPoint halo = CGPointMake(stick.center.x + stick.bounds.size.width / 2 + sp_joystick_touch_margin / 2, stick.center.y);
                UIView *shield = [view hitTest:halo withEvent:nil];
                SPTestTouch *extra = sp_test_touch(shield, halo);
                sp_test_send(extra, UITouchPhaseBegan, sp_test_event(@[extra, finger]));
                sp_test_send(extra, UITouchPhaseEnded, sp_test_event(@[extra, finger]));
                sp_test_check(fabs(stick.value.x - 0.5) < 0.001 && stick.value.y == 0 && sp_events.count == 0,
                              @"A second thumb in the margin neither interrupts movement nor clicks the game.");
                sp_test_tap(view, @[finger]);
                sp_test_check([sp_test_buttons() isEqual:@[@(SPLeftMouseDown), @(SPLeftMouseUp)]], @"Screen taps still left-click while moving.");
                [sp_events removeAllObjects];
                hold = sp_test_touch(thumb, thumb.center);
                sp_test_send(hold, UITouchPhaseBegan, sp_test_event(@[hold, finger]));
                sp_test_tap(view, @[hold, finger]);
                sp_test_send(hold, UITouchPhaseEnded, sp_test_event(@[hold, finger]));
                sp_test_check([sp_test_buttons() isEqual:@[@(SPRightMouseDown), @(SPRightMouseUp)]], @"R plus a game tap still right-clicks while moving.");
                finger.at = CGPointMake(stick.center.x + 500, stick.center.y - 500);
                sp_test_send(finger, UITouchPhaseMoved, sp_test_event(@[finger]));
            },
            ^{
                sp_test_check(sp_test_axis(stick, M_SQRT1_2, M_SQRT1_2), @"Far diagonal motion is circularly clamped with controller Y pointing up.");
                sp_test_check(stick.controller.extendedGamepad.rightThumbstick.xAxis.value == 0 &&
                              stick.controller.extendedGamepad.rightThumbstick.yAxis.value == 0, @"The right stick stays neutral.");
                sp_test_send(finger, UITouchPhaseEnded, sp_test_event(@[finger]));
            },
            ^{
                sp_test_check(sp_test_axis(stick, 0, 0), @"Lifting the thumb releases the real controller axes.");
                finger = sp_test_touch(stick, CGPointMake(stick.center.x, stick.center.y + 60));
                sp_test_send(finger, UITouchPhaseBegan, sp_test_event(@[finger]));
            },
            ^{
                sp_test_check(sp_test_axis(stick, 0, -1), @"A downward push reaches the negative Y axis.");
                sp_test_send(finger, UITouchPhaseCancelled, sp_test_event(@[finger]));
            },
            ^{
                sp_test_check(sp_test_axis(stick, 0, 0), @"A cancelled touch releases both axes.");
                SPTestTouch *mouse = sp_test_touch(stick, CGPointMake(stick.center.x + 100, stick.center.y));
                mouse.testType = UITouchTypeIndirectPointer;
                sp_test_send(mouse, UITouchPhaseBegan, sp_test_event(@[mouse]));
                sp_test_check(CGPointEqualToPoint(stick.value, CGPointZero), @"A hardware pointer cannot become a joystick thumb.");
                for (UIView *child in stick.subviews) if ([child isKindOfClass:SPJoystickHandle.class]) handle = (id)child;
                CGPoint at = [view convertPoint:CGPointMake(22, 22) fromView:handle];
                sp_test_check([view hitTest:at withEvent:nil] == handle, @"The move handle owns its touch separately.");
                [sp_events removeAllObjects];
                CGPoint beforeMove = stick.center;
                handleTouch = sp_test_touch(handle, at);
                sp_test_send(handleTouch, UITouchPhaseBegan, sp_test_event(@[handleTouch]));
                handleTouch.at = CGPointMake(at.x + 180, at.y - 160);
                sp_test_send(handleTouch, UITouchPhaseMoved, sp_test_event(@[handleTouch]));
                sp_test_send(handleTouch, UITouchPhaseEnded, sp_test_event(@[handleTouch]));
                sp_test_check(CGPointEqualToPoint(stick.center, beforeMove) && !handle.highlighted,
                              @"An early arrow drag leaves the joystick locked in place.");
            },
            ^{
                sp_test_check(sp_test_axis(stick, 0, 0) && sp_events.count == 0, @"Repositioning emits neither movement nor mouse events.");
                SPJoystick *restored = [[SPJoystick alloc] initWithFrame:CGRectZero];
                [restored layoutInRect:safe];
                [defaults setDouble:260 forKey:sp_joystick_size_key]; [stick layoutInRect:safe]; [restored layoutInRect:safe];
                sp_test_check(stick.bounds.size.width == 260 && CGRectContainsRect(safe, stick.frame), @"The large joystick stays inside the safe area.");
                sp_test_check(restored.bounds.size.width == 260, @"A fresh joystick restores its size.");
                [restored layoutInRect:CGRectMake(0, 0, 150, 140)];
                sp_test_check(restored.bounds.size.width == 124, @"A small window temporarily shrinks the joystick.");
                [restored layoutInRect:safe];
                sp_test_check(restored.bounds.size.width == 260, @"The preferred size returns when room is available.");
                [defaults setDouble:-10 forKey:sp_joystick_size_key]; [stick layoutInRect:safe];
                sp_test_check(stick.bounds.size.width == 100, @"Too-small saved joystick sizes are clamped.");
                [defaults setDouble:1000 forKey:sp_joystick_size_key]; [stick layoutInRect:safe];
                sp_test_check(stick.bounds.size.width == 260, @"Too-large saved joystick sizes are clamped.");
                [defaults setObject:@"invalid" forKey:sp_joystick_size_key]; [stick layoutInRect:safe];
                sp_test_check(stick.bounds.size.width == 156, @"Malformed joystick sizes use the default.");
                [defaults setObject:@[@"bad", @1] forKey:sp_joystick_position_key]; [stick layoutInRect:safe];
                sp_test_check(CGRectContainsRect(safe, stick.frame), @"Malformed coordinates fall back safely.");
                [defaults setObject:@[@(-20), @100] forKey:sp_joystick_position_key]; [stick layoutInRect:safe];
                sp_test_check(CGRectContainsRect(safe, stick.frame), @"Out-of-range positions are clamped.");
                [defaults removeObjectForKey:sp_joystick_position_key]; [stick layoutInRect:safe];
                finger = sp_test_touch(stick, CGPointMake(stick.center.x + 60, stick.center.y));
                sp_test_send(finger, UITouchPhaseBegan, sp_test_event(@[finger]));
                [defaults setDouble:180 forKey:sp_joystick_size_key]; [stick layoutInRect:safe];
                sp_test_send(finger, UITouchPhaseMoved, sp_test_event(@[finger]));
            },
            ^{
                sp_test_check(sp_test_axis(stick, 0, 0), @"Resizing cancels the old joystick touch without reviving it.");
                finger = sp_test_touch(stick, CGPointMake(stick.center.x + 60, stick.center.y));
                sp_test_send(finger, UITouchPhaseBegan, sp_test_event(@[finger]));
                oldController = stick.controller;
                [view sp_suspend_touch:nil];
                sp_test_check(CGPointEqualToPoint(stick.value, CGPointZero) && !stick.controller, @"App deactivation immediately clears input and disconnects the virtual stick.");
            },
            ^{
                sp_test_check(![GCController.controllers containsObject:oldController], @"Backgrounding removes the virtual controller from enumeration.");
                [view sp_resume_touch:nil];
            }
        ];
        sp_test_stick_steps(steps, 0, ^(NSString *error) {
            if (error) { done(error); return; }
            sp_test_wait_stick(stick, 120, ^(NSString *error) {
                if (error) { done(error); return; }
                @try {
                    sp_test_check(sp_test_axis(stick, 0, 0), @"Resuming reconnects with neutral axes.");
                    CGPoint halo = CGPointMake(stick.center.x + stick.bounds.size.width / 2 + sp_joystick_touch_margin / 2, stick.center.y);
                    [defaults setBool:NO forKey:sp_joystick_enabled_key]; [stick layoutInRect:safe];
                    sp_test_check(stick.hidden && !stick.controller, @"Settings can hide and disconnect the joystick.");
                    sp_test_check([view hitTest:halo withEvent:nil] == view, @"Disabling the joystick removes its touch shield.");
                    // Disable again before the asynchronous reconnect completes.
                    [defaults setBool:YES forKey:sp_joystick_enabled_key]; [stick layoutInRect:safe];
                    [defaults setBool:NO forKey:sp_joystick_enabled_key]; [stick layoutInRect:safe];
                } @catch (NSException *e) { done(e.reason); return; }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
                    @try {
                        sp_test_check(stick.hidden && !stick.controller && CGPointEqualToPoint(stick.value, CGPointZero), @"Disabling during connect cannot revive joystick input.");
                        for (NSString *key in @[sp_joystick_enabled_key, sp_joystick_size_key, sp_joystick_position_key]) [defaults removeObjectForKey:key];
                        [stick layoutInRect:safe];
                    } @catch (NSException *e) { done(e.reason); return; }
                    sp_test_wait_stick(stick, 120, ^(NSString *error) {
                        if (error) { done(error); return; }
                        @try { sp_test_check(sp_test_axis(stick, 0, 0), @"Re-enabling reconnects with neutral axes."); }
                        @catch (NSException *e) { done(e.reason); return; }
                        sp_test_move_hold(view, stick, done);
                    });
                });
            });
        });
    };
    // Menus can render before WoW installs controller listeners. A first frame permits connection,
    // but only a real joystick touch starts it; no minimize/foreground cycle is involved here.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        @try { sp_test_check(!stick.controller, @"A rendered menu alone does not connect the virtual controller."); }
        @catch (NSException *e) { run(e.reason); return; }
        SPTestTouch *first = sp_test_touch(stick, CGPointMake(stick.center.x + 60, stick.center.y));
        sp_test_send(first, UITouchPhaseBegan, sp_test_event(@[first]));
        sp_test_wait_stick(stick, 120, ^(NSString *error) {
            if (error) { run(error); return; }
            sp_test_wait_axis(stick, 1, 0, 40, ^(NSString *error) {
                if (error) { run(error); return; }
                @try { sp_test_check(sp_test_axis(stick, 1, 0), @"An active foreground touch recovers stale suspension and moves without minimizing."); }
                @catch (NSException *e) { run(e.reason); return; }
                sp_test_send(first, UITouchPhaseEnded, sp_test_event(@[first]));
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 5), dispatch_get_main_queue(), ^{ run(nil); });
            });
        });
    });
}
