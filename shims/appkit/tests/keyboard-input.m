// Included by thumb-button.m; real input queue, optional overlays, and the shared timed move handle.
static SPKeyboardButton *sp_test_keyboard_button(SPInputView *view, NSString *name) {
    for (UIView *child in view.subviews)
        if ([child isKindOfClass:SPKeyboardButton.class] && [((SPKeyboardButton *)child).name isEqual:name]) return (id)child;
    @throw [NSException exceptionWithName:@"Missing keyboard button" reason:name userInfo:nil];
}
static void sp_test_keyboard(SPInputView *view, SPThumbButton *thumb) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults removeObjectForKey:sp_keyboard_size_key];
    NSArray *names = @[@"ctrl", @"shift", @"alt", @"space"];
    unsigned usages[] = {0xE0, 0xE1, 0xE2, 0x2C};
    NSUInteger flags[] = {SPControl | SPDevLCtl, SPShift | SPDevLShift, SPOption | SPDevLAlt};
    for (NSString *name in names) {
        [defaults removeObjectForKey:[NSString stringWithFormat:@"sp_%@_enabled", name]];
        [defaults removeObjectForKey:[NSString stringWithFormat:@"sp_%@_position", name]];
    }
    [view setNeedsLayout]; [view layoutIfNeeded];
    for (NSString *name in names) {
        SPKeyboardButton *button = sp_test_keyboard_button(view, name);
        sp_test_check(button.hidden, @"Optional keyboard buttons start hidden.");
        [defaults setBool:YES forKey:[NSString stringWithFormat:@"sp_%@_enabled", name]];
    }
    [view setNeedsLayout]; [view layoutIfNeeded];
    for (NSUInteger i = 0; i < names.count; i++) {
        SPKeyboardButton *button = sp_test_keyboard_button(view, names[i]);
        [sp_events removeAllObjects];
        SPTestTouch *hold = sp_test_touch(button, button.center);
        SPTestEvent *event = sp_test_event(@[hold]);
        sp_test_send(hold, UITouchPhaseBegan, event);
        sp_test_check(!button.hidden && button.highlighted && sp_events.count == 1, @"A keyboard button presses its key without clicking the game.");
        SPEvent *down = sp_events.lastObject;
        sp_test_check(down->keyCode == sp_hid_to_mac[usages[i]], @"Each screen button maps to the intended Mac key.");
        sp_test_check(i == 3 ? down->type == SPKeyDown && [down->characters isEqual:@" "] : down->type == SPFlagsChanged && sp_mod_flags == flags[i],
                      @"Modifiers emit flagsChanged; Space emits a spacebar key-down.");
        sp_test_send(hold, UITouchPhaseEnded, event);
        sp_test_check(!button.highlighted && sp_mod_flags == 0 && sp_events.count == 2, @"Lifting releases each keyboard key exactly once.");
        sp_test_check(i != 3 || ((SPEvent *)sp_events.lastObject)->type == SPKeyUp, @"Space lift sends key-up.");

        // The same physical key and overlay may overlap in either order without a premature up.
        [sp_events removeAllObjects];
        sp_key_input(usages[i], @" ", @" ", YES, NO);
        hold = sp_test_touch(button, button.center); event = sp_test_event(@[hold]);
        sp_test_send(hold, UITouchPhaseBegan, event);
        sp_key_input(usages[i], @" ", @" ", NO, NO);
        sp_test_check(sp_events.count == 1 && (i == 3 || sp_mod_flags == flags[i]), @"A hardware release cannot release a key still held on screen.");
        sp_test_send(hold, UITouchPhaseEnded, event);
        sp_test_check(sp_events.count == 2 && sp_mod_flags == 0, @"The last source releases the shared key.");
        [sp_events removeAllObjects];
        hold = sp_test_touch(button, button.center); event = sp_test_event(@[hold]);
        sp_test_send(hold, UITouchPhaseBegan, event);
        sp_key_input(usages[i], @" ", @" ", YES, NO);
        sp_test_send(hold, UITouchPhaseCancelled, event);
        sp_test_check(sp_events.count == 1 && (i == 3 || sp_mod_flags == flags[i]), @"Cancelling a screen key preserves a physical hold.");
        sp_key_input(usages[i], @" ", @" ", NO, NO);
        sp_test_check(sp_events.count == 2 && sp_mod_flags == 0 && !sp_repeat_key, @"The hardware key-up clears the last hold and any Space repeat.");
    }

    SPKeyboardButton *ctrl = sp_test_keyboard_button(view, @"ctrl");
    SPKeyboardButton *shift = sp_test_keyboard_button(view, @"shift");
    SPKeyboardButton *alt = sp_test_keyboard_button(view, @"alt");
    SPKeyboardButton *space = sp_test_keyboard_button(view, @"space");
    [sp_events removeAllObjects];
    SPTestTouch *controlTouch = sp_test_touch(ctrl, ctrl.center), *shiftTouch = sp_test_touch(shift, shift.center);
    SPTestTouch *altTouch = sp_test_touch(alt, alt.center), *rTouch = sp_test_touch(thumb, thumb.center);
    SPTestTouch *pencil = sp_test_touch(view, CGPointMake(450, 200)); pencil.testType = UITouchTypePencil;
    SPTestEvent *event = sp_test_event(@[controlTouch, shiftTouch, altTouch, rTouch, pencil]);
    // Deliver the game before any overlay, as UIKit may do when contacts land together.
    sp_test_send(pencil, UITouchPhaseBegan, event);
    SPEvent *click = sp_events.lastObject;
    NSUInteger allFlags = SPControl | SPDevLCtl | SPShift | SPDevLShift | SPOption | SPDevLAlt;
    sp_test_check(click->type == SPRightMouseDown && click->modifierFlags == allFlags,
                  @"Simultaneous Ctrl+Shift+Alt+R modifies a Pencil click before overlay callbacks arrive.");
    sp_test_send(controlTouch, UITouchPhaseBegan, event); sp_test_send(shiftTouch, UITouchPhaseBegan, event);
    sp_test_send(altTouch, UITouchPhaseBegan, event); sp_test_send(rTouch, UITouchPhaseBegan, event);
    sp_test_send(pencil, UITouchPhaseEnded, event);
    SPTestTouch *spaceTouch = sp_test_touch(space, space.center);
    sp_test_send(spaceTouch, UITouchPhaseBegan, sp_test_event(@[spaceTouch]));
    sp_test_check(((SPEvent *)sp_events.lastObject)->type == SPKeyDown && ((SPEvent *)sp_events.lastObject)->modifierFlags == allFlags,
                  @"On-screen modifiers combine with Space.");
    sp_repeat_at = 0; sp_key_repeats();
    sp_test_check(((SPEvent *)sp_events.lastObject)->isARepeat, @"Holding Space uses normal keyboard repeat.");
    [view sp_suspend_touch:nil];
    sp_test_check(sp_mod_flags == 0 && sp_mouse_buttons == 0 && !sp_repeat_key && !space.highlighted,
                  @"App deactivation releases modifiers, Space, R, and repeat state.");
    [view sp_resume_touch:nil];

    [sp_events removeAllObjects];
    CGPoint initial = ctrl.center;
    controlTouch = sp_test_touch(ctrl, initial); event = sp_test_event(@[controlTouch]);
    sp_test_send(controlTouch, UITouchPhaseBegan, event);
    controlTouch.at = CGPointMake(initial.x + 90, initial.y - 100);
    sp_test_send(controlTouch, UITouchPhaseMoved, event); sp_test_send(controlTouch, UITouchPhaseEnded, event);
    sp_test_check(!CGPointEqualToPoint(ctrl.center, initial) && [defaults arrayForKey:@"sp_ctrl_position"].count == 2,
                  @"Modifier squares drag like R and save their own position.");
    CGPoint moved = ctrl.center;
    [view setNeedsLayout]; [view layoutIfNeeded];
    sp_test_check(CGPointEqualToPoint(ctrl.center, moved), @"Modifier layout restores its saved position.");

    controlTouch = sp_test_touch(ctrl, ctrl.center); event = sp_test_event(@[controlTouch]);
    sp_test_send(controlTouch, UITouchPhaseBegan, event);
    [defaults setBool:NO forKey:@"sp_ctrl_enabled"]; [view setNeedsLayout]; [view layoutIfNeeded];
    sp_test_check(ctrl.hidden && sp_mod_flags == 0, @"Disabling a held modifier releases it immediately.");
    sp_test_send(controlTouch, UITouchPhaseMoved, event);
    sp_test_check(sp_mod_flags == 0, @"A disabled key's stale touch cannot restore its modifier.");
    [defaults setBool:YES forKey:@"sp_ctrl_enabled"];
    [defaults setDouble:152 forKey:sp_keyboard_size_key]; [view setNeedsLayout]; [view layoutIfNeeded];
    sp_test_check(ctrl.bounds.size.width == 152 && space.bounds.size.width == 204, @"The shared size setting scales keys and the Space ring.");
    [defaults removeObjectForKey:sp_keyboard_size_key]; [view setNeedsLayout]; [view layoutIfNeeded];
}

static void sp_test_position_lock(SPInputView *view, SPThumbButton *thumb) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    sp_test_check(!sp_button_positions_locked(), @"Button placement stays movable until the optional lock is enabled.");
    NSArray<UIControl *> *buttons = @[thumb, sp_test_keyboard_button(view, @"ctrl"),
                                    sp_test_keyboard_button(view, @"shift"), sp_test_keyboard_button(view, @"alt")];
    NSArray<NSString *> *keys = @[sp_thumb_position_key, @"sp_ctrl_position", @"sp_shift_position", @"sp_alt_position"];
    NSUInteger flags[] = {0, SPControl | SPDevLCtl, SPShift | SPDevLShift, SPOption | SPDevLAlt};
    NSMutableArray *saved = [NSMutableArray array];
    for (NSString *key in keys) [saved addObject:[defaults objectForKey:key] ?: NSNull.null];
    for (NSUInteger i = 0; i < buttons.count; i++) {
        UIControl *button = buttons[i];
        [defaults setBool:YES forKey:sp_button_positions_locked_key];
        [view setNeedsLayout]; [view layoutIfNeeded];
        CGPoint center = button.center;
        id position = [defaults objectForKey:keys[i]];
        [sp_events removeAllObjects];
        SPTestTouch *hold = sp_test_touch(button, center);
        SPTestTouch *pencil = sp_test_touch(view, CGPointMake(450, 200)); pencil.testType = UITouchTypePencil;
        SPTestEvent *event = sp_test_event(@[hold, pencil]);
        sp_test_send(hold, UITouchPhaseBegan, event);
        hold.at = CGPointMake(center.x + 100, center.y - 100);
        sp_test_send(hold, UITouchPhaseMoved, event);
        sp_test_check(CGPointEqualToPoint(button.center, center) && button.highlighted,
                      @"The placement lock stops R/Ctrl/Shift/Alt dragging without releasing the held control.");
        sp_test_send(pencil, UITouchPhaseBegan, event);
        SPEvent *click = sp_events.lastObject;
        sp_test_check(click->type == (i == 0 ? SPRightMouseDown : SPLeftMouseDown) &&
                      (click->modifierFlags & flags[i]) == flags[i],
                      @"Locked buttons retain their right-click or modifier action with Apple Pencil.");
        pencil.at = CGPointMake(470, 220); sp_test_send(pencil, UITouchPhaseMoved, event);
        sp_test_check(((SPEvent *)sp_events.lastObject)->type == (i == 0 ? SPRightMouseDragged : SPLeftMouseDragged),
                      @"Locking placement does not interfere with a modified game drag.");
        sp_test_send(hold, UITouchPhaseEnded, event);
        sp_test_send(pencil, UITouchPhaseEnded, event);
        sp_test_check(CGPointEqualToPoint(button.center, center) && sp_mod_flags == 0 && sp_mouse_buttons == 0,
                      @"Release keeps the button fixed and balances all key/mouse presses.");
        id after = [defaults objectForKey:keys[i]];
        sp_test_check((!position && !after) || [position isEqual:after], @"A locked drag cannot overwrite a saved position.");

        [defaults setBool:NO forKey:sp_button_positions_locked_key];
        [view setNeedsLayout]; [view layoutIfNeeded];
        hold = sp_test_touch(button, center); event = sp_test_event(@[hold]);
        sp_test_send(hold, UITouchPhaseBegan, event);
        hold.at = CGPointMake(center.x + 65, center.y - 65);
        sp_test_send(hold, UITouchPhaseMoved, event);
        sp_test_send(hold, UITouchPhaseEnded, event);
        sp_test_check(!CGPointEqualToPoint(button.center, center) && [defaults arrayForKey:keys[i]].count == 2,
                      @"Unlocking restores normal repositioning and saves the new location.");

        hold = sp_test_touch(button, button.center); event = sp_test_event(@[hold]);
        sp_test_send(hold, UITouchPhaseBegan, event);
        hold.at = CGPointMake(hold.at.x + 20, hold.at.y - 20);
        sp_test_send(hold, UITouchPhaseMoved, event);
        center = button.center;
        [defaults setBool:YES forKey:sp_button_positions_locked_key];
        [view setNeedsLayout]; [view layoutIfNeeded];
        hold.at = CGPointMake(hold.at.x + 60, hold.at.y - 60);
        sp_test_send(hold, UITouchPhaseMoved, event);
        [defaults setBool:NO forKey:sp_button_positions_locked_key];
        hold.at = CGPointMake(hold.at.x + 60, hold.at.y - 60);
        sp_test_send(hold, UITouchPhaseMoved, event);
        sp_test_send(hold, UITouchPhaseEnded, event);
        sp_test_check(CGPointEqualToPoint(button.center, center) && sp_mod_flags == 0,
                      @"Locking during a drag freezes it; unlocking cannot revive the old gesture or stick a modifier.");
    }
    for (NSUInteger i = 0; i < keys.count; i++) {
        if (saved[i] == NSNull.null) [defaults removeObjectForKey:keys[i]];
        else [defaults setObject:saved[i] forKey:keys[i]];
    }
    // The following real-timer Space and joystick checks run with this enabled, proving their
    // separate hold-to-move paths are unaffected by the modifier/R placement lock.
    [defaults setBool:YES forKey:sp_button_positions_locked_key];
    [view setNeedsLayout]; [view layoutIfNeeded];
}

static void sp_test_space_hold(SPInputView *view, void (^done)(NSString *)) {
    SPKeyboardButton *space = sp_test_keyboard_button(view, @"space");
    SPJoystickHandle *ring = nil;
    for (UIView *child in space.subviews) if ([child isKindOfClass:SPJoystickHandle.class]) ring = (id)child;
    CGPoint at = [view convertPoint:CGPointMake(space.bounds.size.width / 2, 10) fromView:space];
    CGPoint center = space.center;
    @try {
        sp_test_check(ring && !ring.userInteractionEnabled && [view hitTest:at withEvent:nil] == space &&
                      [view hitTest:space.center withEvent:nil] == space,
                      @"The center and ring belong to one Space press target, with no separate move target.");
    } @catch (NSException *e) { done(e.reason); return; }
    [sp_events removeAllObjects];
    SPTestTouch *hold = sp_test_touch(space, at); SPTestEvent *event = sp_test_event(@[hold]);
    sp_test_send(hold, UITouchPhaseBegan, event);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        @try {
            sp_test_check(!ring.highlighted && space.highlighted && CGPointEqualToPoint(space.center, center) && sp_events.count == 1 &&
                          ((SPEvent *)sp_events.lastObject)->type == SPKeyDown,
                          @"Holding anywhere in the circle presses Space immediately and stays locked for the first second.");
            CAShapeLayer *progress = nil;
            for (CALayer *layer in ring.layer.sublayers) if ([layer isKindOfClass:CAShapeLayer.class]) progress = (id)layer;
            CGFloat visible = ((CAShapeLayer *)progress.presentationLayer).strokeEnd;
            sp_test_check(visible > 0 && visible < 1, @"The circular ring shows hold progress around Space.");
            hold.at = CGPointMake(at.x + 2, at.y);
            sp_test_send(hold, UITouchPhaseMoved, event);
        } @catch (NSException *e) { done(e.reason); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 13 * NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{
            @try {
                sp_test_check(ring.highlighted && CGPointEqualToPoint(space.center, center), @"Two seconds unlocks the Space ring without jumping.");
                sp_test_check(!space.highlighted && !sp_repeat_key && sp_events.count == 2 &&
                              ((SPEvent *)sp_events.lastObject)->type == SPKeyUp,
                              @"Unlocking releases Space and stops repeat before the button can move.");
                [sp_events removeAllObjects];
                hold.at = CGPointMake(at.x - 180, at.y - 140);
                sp_test_send(hold, UITouchPhaseMoved, event);
                sp_test_send(hold, UITouchPhaseEnded, event);
                sp_test_check(!ring.highlighted && !CGPointEqualToPoint(space.center, center) && sp_events.count == 0,
                              @"The unlocked ring moves Space, relocks on lift, and sends no key or mouse input.");
                CGPoint moved = space.center;
                [view setNeedsLayout]; [view layoutIfNeeded];
                sp_test_check(CGPointEqualToPoint(space.center, moved), @"Space restores its saved ring-dragged position.");
                SPTestTouch *press = sp_test_touch(space, space.center);
                SPTestEvent *pressEvent = sp_test_event(@[press]);
                sp_test_send(press, UITouchPhaseBegan, pressEvent);
                [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"sp_space_enabled"];
                [view setNeedsLayout]; [view layoutIfNeeded];
                sp_test_check(space.hidden && !sp_repeat_key && ((SPEvent *)sp_events.lastObject)->type == SPKeyUp,
                              @"Disabling Space releases its held key and cancels repeat.");
                [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"sp_space_enabled"];
                [view setNeedsLayout]; [view layoutIfNeeded];
            } @catch (NSException *e) { done(e.reason); return; }
            CGPoint newAt = [view convertPoint:CGPointMake(space.bounds.size.width / 2, 10) fromView:space];
            SPTestTouch *cancelled = sp_test_touch(space, newAt);
            sp_test_send(cancelled, UITouchPhaseBegan, sp_test_event(@[cancelled]));
            [view sp_suspend_touch:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 23 * NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{
                @try {
                    sp_test_check(!ring.highlighted && !space.highlighted && !sp_repeat_key,
                                  @"App switching releases Space and invalidates its pending unlock.");
                    [view sp_resume_touch:nil];
                    for (NSString *name in @[@"ctrl", @"shift", @"alt", @"space"]) {
                        [NSUserDefaults.standardUserDefaults removeObjectForKey:[NSString stringWithFormat:@"sp_%@_enabled", name]];
                        [NSUserDefaults.standardUserDefaults removeObjectForKey:[NSString stringWithFormat:@"sp_%@_position", name]];
                    }
                    [view setNeedsLayout]; [view layoutIfNeeded];
                } @catch (NSException *e) { done(e.reason); return; }
                done(nil);
            });
        });
    });
}

static void sp_test_space_ring(SPInputView *view, void (^done)(NSString *)) {
    SPKeyboardButton *space = sp_test_keyboard_button(view, @"space");
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:@[@0.75, @0.55] forKey:@"sp_space_position"];
    [view setNeedsLayout]; [view layoutIfNeeded];
    CGFloat r = space.bounds.size.width / 2, margin = sp_joystick_touch_margin;
    @try {
        for (int i = 0; i < 8; i++) {
            CGFloat angle = i * M_PI / 4;
            CGPoint edge = CGPointMake(space.center.x + cos(angle) * (r - 2), space.center.y + sin(angle) * (r - 2));
            sp_test_check([view hitTest:edge withEvent:nil] == space, @"Every side of the visible Space circle is clickable.");
            [sp_events removeAllObjects];
            SPTestTouch *tap = sp_test_touch(space, edge); SPTestEvent *event = sp_test_event(@[tap]);
            sp_test_send(tap, UITouchPhaseBegan, event); sp_test_send(tap, UITouchPhaseEnded, event);
            sp_test_check(sp_events.count == 2 && ((SPEvent *)sp_events.firstObject)->type == SPKeyDown &&
                          ((SPEvent *)sp_events.lastObject)->type == SPKeyUp,
                          @"A quick edge tap sends only a normal Space press and release.");
            CGPoint halo = CGPointMake(space.center.x + cos(angle) * (r + margin - 2),
                                       space.center.y + sin(angle) * (r + margin - 2));
            UIView *target = [view hitTest:halo withEvent:nil];
            sp_test_check([target isKindOfClass:SPKeyboardShield.class], @"Space has the same touch margin on every side as the joystick.");
            [sp_events removeAllObjects];
            SPTestTouch *stray = sp_test_touch(target, halo); event = sp_test_event(@[stray]);
            sp_test_send(stray, UITouchPhaseBegan, event); stray.at = space.center;
            sp_test_send(stray, UITouchPhaseMoved, event); sp_test_send(stray, UITouchPhaseEnded, event);
            sp_test_check(sp_events.count == 0, @"A margin contact stays inert after drifting into the Space circle.");
        }
        CGPoint halo = CGPointMake(space.center.x + r + margin / 2, space.center.y);
        SPTestTouch *pointer = sp_test_touch(view, halo); pointer.testType = UITouchTypeIndirectPointer;
        sp_test_check([view hitTest:halo withEvent:sp_test_event(@[pointer])] == view, @"Space's margin lets physical mouse clicks through.");
        pointer.testType = UITouchTypePencil;
        sp_test_check([view hitTest:halo withEvent:sp_test_event(@[pointer])] == view, @"Space's margin lets Pencil contacts through.");
        sp_test_check([view hitTest:CGPointMake(space.center.x + r + margin + 2, space.center.y) withEvent:nil] == view,
                      @"Beyond Space's margin, touches reach the game.");
        SPThumbButton *thumb = nil;
        for (UIView *child in view.subviews) if ([child isKindOfClass:SPThumbButton.class]) thumb = (id)child;
        CGPoint saved = thumb.center; thumb.center = halo;
        sp_test_check([view hitTest:halo withEvent:nil] == thumb, @"R remains usable above Space's touch margin.");
        thumb.center = saved;
        SPKeyboardButton *ctrl = sp_test_keyboard_button(view, @"ctrl"); saved = ctrl.center; ctrl.center = halo;
        sp_test_check([view hitTest:halo withEvent:nil] == ctrl, @"Keyboard modifiers remain usable above Space's touch margin.");
        ctrl.center = saved;
    } @catch (NSException *e) { done(e.reason); return; }

    [sp_events removeAllObjects];
    CGPoint center = space.center;
    SPTestTouch *early = sp_test_touch(space, center); SPTestEvent *event = sp_test_event(@[early]);
    sp_test_send(early, UITouchPhaseBegan, event);
    early.at = CGPointMake(center.x + 20, center.y);
    sp_test_send(early, UITouchPhaseMoved, event);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 23 * NSEC_PER_SEC / 10), dispatch_get_main_queue(), ^{
        @try {
            SPJoystickHandle *ring = nil;
            for (UIView *child in space.subviews) if ([child isKindOfClass:SPJoystickHandle.class]) ring = (id)child;
            sp_test_check(!ring.highlighted && space.highlighted && CGPointEqualToPoint(space.center, center) && sp_events.count == 1,
                          @"Moving early cancels the unlock without moving the button or releasing a held Space key.");
            sp_test_send(early, UITouchPhaseEnded, event);
            sp_test_check(!space.highlighted && !sp_repeat_key, @"The early-moving press still releases Space normally on lift.");
        } @catch (NSException *e) { done(e.reason); return; }
        sp_test_space_hold(view, done);
    });
}
