// A touch-owned left stick feeds the same GameController API the client uses for physical pads.
// Included on iPhone and iPad only. A separate handle moves the control, never the character.
static NSString *const sp_joystick_enabled_key = @"sp_joystick_enabled";
static NSString *const sp_joystick_position_key = @"sp_joystick_position";
static NSString *const sp_joystick_size_key = @"sp_joystick_size";
static const CGFloat sp_joystick_default_size = 156, sp_joystick_min_size = 100, sp_joystick_max_size = 260;
// About one centimeter on a full-size iPad. Fixed points keep the shield independent of stick size.
static const CGFloat sp_joystick_touch_margin = 52;
static const NSTimeInterval sp_joystick_move_hold = 2;

@protocol SPMovableControl <NSObject>
- (void)beginMove:(UITouch *)touch;
- (void)moveWithTouch:(UITouch *)touch;
- (void)endMove;
@end

@interface SPJoystick : UIControl <SPMovableControl>
@property(nonatomic, readonly) CGPoint value;
@property(nonatomic, readonly) GCController *controller;
// The touch stick's own pad, set from the moment it connects, and whether its connect is still pending.
@property(nonatomic, readonly) GCController *virtualPad;
@property(nonatomic, readonly) BOOL connectPending;
- (void)layoutInRect:(CGRect)rect;
- (void)cancelInput;
- (void)setSuspended:(BOOL)suspended;
- (void)gameDidStart;
- (void)updateTouch:(UITouch *)touch;
- (BOOL)containsStickPoint:(CGPoint)point;
- (void)beginMove:(UITouch *)touch;
- (void)moveWithTouch:(UITouch *)touch;
- (void)endMove;
@end

// A touch that begins in the margin belongs here until it lifts, even if it drifts onto the game or
// into the stick. Never forward it up the responder chain, and never turn it into movement.
@interface SPJoystickShield : UIView
@property(nonatomic, weak) SPJoystick *joystick;
@end
@implementation SPJoystickShield
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGPoint p = [self.joystick convertPoint:point fromView:self];
    return [self.joystick pointInside:p withEvent:event] && ![self.joystick containsStickPoint:p];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
@end

@interface SPJoystickHandle : UIControl
@property(nonatomic, weak) UIView<SPMovableControl> *joystick;
@property(nonatomic) BOOL ring;
- (void)cancelTouch;
@end

@implementation SPJoystickHandle {
    UITouch *_touch;
    CGPoint _pressStart;
    NSUInteger _holdGeneration;
    UILabel *_grip;
    CAShapeLayer *_progress;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.exclusiveTouch = NO;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = @"Move left joystick";
    self.accessibilityHint = @"Hold for two seconds, then drag to save a new joystick position.";
    self.accessibilityIdentifier = @"sp.left-joystick-move";
    UIColor *gold = [UIColor colorWithRed:0.78 green:0.73 blue:0.59 alpha:1];
    _progress = [NSClassFromString(@"CAShapeLayer") layer];  // QuartzCore isn't linked, as spwindow.m
    _progress.frame = self.bounds;
    _progress.path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(2, 2, 40, 40) cornerRadius:10].CGPath;
    _progress.fillColor = UIColor.clearColor.CGColor;
    _progress.strokeColor = gold.CGColor;
    _progress.lineWidth = 2;
    _progress.strokeEnd = 0;
    [self.layer addSublayer:_progress];
    _grip = [[UILabel alloc] initWithFrame:CGRectMake(8, 8, 28, 28)];
    _grip.userInteractionEnabled = NO;
    _grip.text = @"↔";
    _grip.font = [UIFont systemFontOfSize:21 weight:UIFontWeightSemibold];
    _grip.textAlignment = NSTextAlignmentCenter;
    _grip.layer.cornerRadius = 7;
    _grip.clipsToBounds = YES;
    [self addSubview:_grip];
    [self setHighlighted:NO];
    return self;
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    UIColor *gold = [UIColor colorWithRed:0.78 green:0.73 blue:0.59 alpha:1];
    _grip.textColor = highlighted ? [UIColor colorWithWhite:0.06 alpha:1] : gold;
    _grip.backgroundColor = highlighted ? gold : [UIColor colorWithWhite:0.1 alpha:0.95];
    if (self.ring) self.layer.borderColor = [gold colorWithAlphaComponent:highlighted ? 1 : 0.45].CGColor;
    self.accessibilityValue = highlighted ? @"Unlocked for dragging" : @"Hold for two seconds";
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _progress.frame = self.bounds;
    _grip.hidden = self.ring;
    if (self.ring) {
        self.layer.cornerRadius = self.bounds.size.width / 2;
        self.layer.borderWidth = 2;
        self.layer.borderColor = [UIColor colorWithRed:0.78 green:0.73 blue:0.59 alpha:self.highlighted ? 1 : 0.45].CGColor;
        _progress.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds, 3, 3)].CGPath;
    }
}
- (void)cancelTouch {
    _touch = nil;
    _holdGeneration++;
    [_progress removeAllAnimations];
    Class tx = NSClassFromString(@"CATransaction");
    [tx begin]; [tx setDisableActions:YES];
    _progress.strokeEnd = 0;
    [tx commit];
    [self setHighlighted:NO];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch) return;
    for (UITouch *touch in touches) if (touch.type == UITouchTypeDirect || (self.ring && touch.type == UITouchTypePencil)) {
        _touch = touch;
        _pressStart = [touch locationInView:self.joystick.superview];
        NSUInteger generation = ++_holdGeneration;
        CABasicAnimation *countdown = [NSClassFromString(@"CABasicAnimation") animationWithKeyPath:@"strokeEnd"];
        countdown.fromValue = @0; countdown.toValue = @1;
        countdown.duration = sp_joystick_move_hold;
        Class tx = NSClassFromString(@"CATransaction");
        [tx begin]; [tx setDisableActions:YES];
        _progress.strokeEnd = 1;
        [tx commit];
        [_progress addAnimation:countdown forKey:@"sp.move-hold"];
        __weak SPJoystickHandle *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sp_joystick_move_hold * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SPJoystickHandle *self = weakSelf;
            // A quick press, early drag, resize, or app switch invalidates the pending unlock.
            if (!self || self->_holdGeneration != generation || self->_touch != touch ||
                touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) return;
            [self setHighlighted:YES];
            [self.joystick beginMove:touch];
        });
        break;
    }
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_touch || ![touches containsObject:_touch]) return;
    if (self.highlighted) { [self.joystick moveWithTouch:_touch]; return; }
    CGPoint at = [_touch locationInView:self.joystick.superview];
    // A small resting-thumb drift is fine; an early drag is an accidental grab, not a deferred jump.
    if (hypot(at.x - _pressStart.x, at.y - _pressStart.y) > 12) [self cancelTouch];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch && [touches containsObject:_touch]) {
        if (self.highlighted) { [self.joystick moveWithTouch:_touch]; [self.joystick endMove]; }
        [self cancelTouch];
    }
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch && [touches containsObject:_touch]) { [self.joystick endMove]; [self cancelTouch]; }
}
@end

@implementation SPJoystick {
    UIView *_knob;
    UILabel *_status;
    SPJoystickHandle *_handle;
    SPJoystickShield *_shield;
    UITouch *_stickTouch;
    GCVirtualController *_virtualController;
    CGPoint _value, _position, _fingerStart, _centerStart;
    CGRect _centers;
    BOOL _moving, _suspended, _connected, _gameReady, _requested;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.hidden = YES;
    _gameReady = atomic_load(&sp_game_presented);
    self.exclusiveTouch = NO;
    self.multipleTouchEnabled = NO;
    self.layer.zPosition = 1200;
    self.layer.borderWidth = 1.5;
    UIColor *gold = [UIColor colorWithRed:0.78 green:0.73 blue:0.59 alpha:1];
    self.layer.borderColor = [gold colorWithAlphaComponent:0.6].CGColor;
    self.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.45];
    self.isAccessibilityElement = NO;  // keep the move handle independently discoverable
    self.accessibilityIdentifier = @"sp.left-joystick";
    _shield = [SPJoystickShield new];
    _shield.joystick = self;
    _shield.multipleTouchEnabled = YES;
    _shield.isAccessibilityElement = NO;
    _shield.accessibilityIdentifier = @"sp.left-joystick-shield";
    [self addSubview:_shield];
    _knob = [UIView new];
    _knob.userInteractionEnabled = NO;
    _knob.backgroundColor = [gold colorWithAlphaComponent:0.65];
    [self addSubview:_knob];
    _status = [UILabel new];
    _status.userInteractionEnabled = NO;
    _status.textColor = gold;
    _status.textAlignment = NSTextAlignmentCenter;
    _status.font = [UIFont systemFontOfSize:24 weight:UIFontWeightSemibold];
    [_knob addSubview:_status];
    _handle = [[SPJoystickHandle alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    _handle.joystick = self;
    [self addSubview:_handle];
    return self;
}

- (CGPoint)value { return _value; }
- (GCController *)controller { return _connected ? _virtualController.controller : nil; }
- (GCController *)virtualPad { return _virtualController.controller; }
- (BOOL)connectPending { return _virtualController && !_connected; }

- (void)drawValue {
    CGFloat size = self.bounds.size.width, travel = size * 0.30, knobSize = size * 0.36;
    _knob.bounds = CGRectMake(0, 0, knobSize, knobSize);
    _knob.layer.cornerRadius = knobSize / 2;
    _knob.center = CGPointMake(size / 2 + _value.x * travel, size / 2 - _value.y * travel);
    _status.frame = _knob.bounds;
}

- (void)sendValue:(CGPoint)value {
    _value = value;
    if (_connected) [_virtualController setPosition:value forDirectionPadElement:GCInputLeftThumbstick];
    [self drawValue];
}

- (void)cancelInput {
    _stickTouch = nil;
    [self sendValue:CGPointZero];
    [self endMove];
    [_handle cancelTouch];
}

- (void)updateConnection {
    BOOL want = _gameReady && _requested && self.window && !self.hidden && !_suspended &&
                self.window.windowScene.activationState == UISceneActivationStateForegroundActive;
    if (!want) {
        [self cancelInput];
        [_virtualController disconnect];
        _virtualController = nil;
        _connected = NO;
        _status.text = nil;
        return;
    }
    if (_virtualController) return;  // includes an asynchronous connect already in progress
    GCVirtualControllerConfiguration *config = [GCVirtualControllerConfiguration new];
    config.elements = [NSSet setWithObject:GCInputLeftThumbstick];
    config.hidden = YES;  // our own view supplies the axes, with no system-wide touch overlay
    GCVirtualController *virtualController = [[GCVirtualController alloc] initWithConfiguration:config];
    _virtualController = virtualController;
    sp_stub_log("input: virtual left joystick connecting");
    __weak SPJoystick *weakSelf = self;
    [virtualController connectWithReplyHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SPJoystick *self = weakSelf;
            // Disabling or backgrounding during connect must not leave a phantom controller behind.
            if (!self || self->_virtualController != virtualController) { [virtualController disconnect]; return; }
            self->_connected = !error && virtualController.controller != nil;
            self->_status.text = self->_connected ? nil : @"!";
            if (!self->_connected) {
                sp_stub_log("input: virtual left joystick could not connect; next touch can retry");
                [virtualController disconnect];
                self->_virtualController = nil;
                self->_stickTouch = nil;
                [self sendValue:CGPointZero];
                // A physical pad that arrived during the connect was left undecided (sp_physical_pad).
                if (GCController.controllers.count) [self.superview setNeedsLayout];
                return;
            }
            sp_stub_log("input: virtual left joystick connected");
            [self.superview setNeedsLayout];  // as above: decide now which pads are physical
            // The first touch deliberately starts connection after the game is in use. Preserve
            // that held touch, but never revive one lifted/cancelled while the connection was pending.
            UITouch *touch = self->_stickTouch;
            if (touch && touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled)
                [self updateTouch:touch];
            else {
                self->_stickTouch = nil;
                [self sendValue:CGPointZero];
            }
        });
    }];
}

- (void)setSuspended:(BOOL)suspended {
    _suspended = suspended;
    [self updateConnection];
}

- (void)gameDidStart {
    if (_gameReady) return;
    _gameReady = YES;
    sp_stub_log("input: virtual left joystick game ready");
    [self updateConnection];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateConnection];
}

- (void)dealloc { [_virtualController disconnect]; }

- (void)layoutInRect:(CGRect)rect {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL enabled = ![defaults objectForKey:sp_joystick_enabled_key] || [defaults boolForKey:sp_joystick_enabled_key];
    id savedSize = [defaults objectForKey:sp_joystick_size_key];
    double size = [savedSize isKindOfClass:NSNumber.class] ? [savedSize doubleValue] : sp_joystick_default_size;
    if (!isfinite(size)) size = sp_joystick_default_size;
    size = MAX(sp_joystick_min_size, MIN(sp_joystick_max_size, size));
    BOOL room = !CGRectIsNull(rect) && rect.size.width >= sp_joystick_min_size + 16 && rect.size.height >= sp_joystick_min_size + 16;
    if (room) size = MIN(size, MIN(rect.size.width, rect.size.height) - 16);
    CGRect centers = room ? CGRectInset(rect, size / 2 + 8, size / 2 + 8) : CGRectZero;
    if (!enabled || !room || !CGRectEqualToRect(centers, _centers)) [self cancelInput];
    self.hidden = !enabled || !room;
    if (!self.hidden) {
        _centers = centers;
        if (!_moving) {
            _position = CGPointMake(0.12, 1);
            id saved = [defaults objectForKey:sp_joystick_position_key];
            if ([saved isKindOfClass:NSArray.class] && [saved count] == 2 &&
                [saved[0] isKindOfClass:NSNumber.class] && [saved[1] isKindOfClass:NSNumber.class]) {
                double x = [saved[0] doubleValue], y = [saved[1] doubleValue];
                if (isfinite(x) && isfinite(y)) _position = CGPointMake(MAX(0, MIN(1, x)), MAX(0, MIN(1, y)));
            }
        }
        self.bounds = CGRectMake(0, 0, size, size);
        self.layer.cornerRadius = size / 2;
        self.center = CGPointMake(centers.origin.x + centers.size.width * _position.x,
                                 centers.origin.y + centers.size.height * _position.y);
        _handle.frame = CGRectMake(size - 44, 0, 44, 44);
        _shield.frame = CGRectInset(self.bounds, -sp_joystick_touch_margin, -sp_joystick_touch_margin);
        [self drawValue];
    }
    [self updateConnection];
}

- (BOOL)containsStickPoint:(CGPoint)point {
    CGFloat r = self.bounds.size.width / 2;
    return CGRectContainsPoint(self.bounds, point) &&
           (hypot(point.x - r, point.y - r) <= r || CGRectContainsPoint(_handle.frame, point));
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if ([self containsStickPoint:point]) return YES;
    // Extend UIKit hit testing outside the visible circle without blocking a hardware pointer's clicks
    // or hover there. allTouches can still be empty during UIKit's initial hit test.
    if (event && event.type != UIEventTypeTouches) return NO;
    for (UITouch *touch in event.allTouches) {
        CGPoint p = [touch locationInView:self];
        if (touch.phase == UITouchPhaseBegan && hypot(p.x - point.x, p.y - point.y) < 0.5 &&
            touch.type != UITouchTypeDirect) return NO;
    }
    CGFloat r = self.bounds.size.width / 2;
    return hypot(point.x - r, point.y - r) <= r + sp_joystick_touch_margin;
}

- (void)updateTouch:(UITouch *)touch {
    CGPoint p = [touch locationInView:self];
    CGFloat travel = self.bounds.size.width * 0.30;
    CGFloat x = (p.x - self.bounds.size.width / 2) / travel;
    CGFloat y = (self.bounds.size.height / 2 - p.y) / travel;
    CGFloat length = hypot(x, y);
    // A radial dead zone removes thumb jitter while preserving every diagonal and analog speed.
    CGFloat strength = MIN(1, MAX(0, (length - 0.12) / 0.88));
    [self sendValue:length > 0 ? CGPointMake(x / length * strength, y / length * strength) : CGPointZero];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    // The SP_HOVER_OFF development override removes first-frame hooks. A first stick touch is a
    // fallback in that mode. In normal launches a frame permits connection, but the first stick use
    // requests it: the login/menu's first present can precede the game's controller initialization.
    if (!_gameReady && (atomic_load(&sp_game_presented) || getenv("SP_HOVER_OFF"))) [self gameDidStart];
    static int logged;
    if (logged++ < 4)
        sp_stub_log([NSString stringWithFormat:@"input: joystick touch ready=%d suspended=%d moving=%d hidden=%d window=%d scene=%ld",
                     _gameReady, _suspended, _moving, self.hidden, self.window != nil,
                     (long)self.window.windowScene.activationState].UTF8String);
    if (_stickTouch || _moving || !_gameReady || self.hidden) return;
    for (UITouch *touch in touches) if (touch.type == UITouchTypeDirect) {
        if (![self containsStickPoint:[touch locationInView:self]]) continue;
        // A real new touch in an active scene is fresher than a missed activation notification.
        // Keep background cancellation intact: old moved touches never enter this recovery path.
        if (_suspended && self.window && self.window.windowScene &&
            self.window.windowScene.activationState == UISceneActivationStateForegroundActive) {
            _suspended = NO;
            sp_stub_log("input: virtual left joystick recovered foreground touch");
        }
        if (_suspended) return;
        _stickTouch = touch;
        _requested = YES;
        [self updateConnection];
        if (_stickTouch == touch) [self updateTouch:touch];
        break;
    }
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_stickTouch && [touches containsObject:_stickTouch]) [self updateTouch:_stickTouch];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_stickTouch && [touches containsObject:_stickTouch]) [self cancelInput];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_stickTouch && [touches containsObject:_stickTouch]) [self cancelInput];
}

- (void)beginMove:(UITouch *)touch {
    _stickTouch = nil;
    [self sendValue:CGPointZero];
    [self endMove];
    _moving = YES;
    _fingerStart = [touch locationInView:self.superview];
    _centerStart = self.center;
}
- (void)moveWithTouch:(UITouch *)touch {
    if (!_moving) return;
    CGPoint p = [touch locationInView:self.superview];
    self.center = CGPointMake(MAX(CGRectGetMinX(_centers), MIN(CGRectGetMaxX(_centers), _centerStart.x + p.x - _fingerStart.x)),
                              MAX(CGRectGetMinY(_centers), MIN(CGRectGetMaxY(_centers), _centerStart.y + p.y - _fingerStart.y)));
    _position = CGPointMake(_centers.size.width ? (self.center.x - _centers.origin.x) / _centers.size.width : 0,
                            _centers.size.height ? (self.center.y - _centers.origin.y) / _centers.size.height : 0);
}
- (void)endMove {
    if (!_moving) return;
    _moving = NO;
    [NSUserDefaults.standardUserDefaults setObject:@[@(_position.x), @(_position.y)] forKey:sp_joystick_position_key];
}
@end
