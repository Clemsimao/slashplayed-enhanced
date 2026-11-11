// Optional touch-owned keyboard keys. Modifier squares drag like R. The whole Space circle presses
// its key and starts the joystick's timed unlock; after two seconds, release Space and allow moving.
static NSString *const sp_keyboard_size_key = @"sp_keyboard_size";
static const CGFloat sp_keyboard_default_size = 76, sp_keyboard_min_size = 44, sp_keyboard_max_size = 152;

@interface SPKeyboardButton : UIControl <SPMovableControl>
@property(nonatomic, readonly) NSString *name;
- (instancetype)initWithName:(NSString *)name label:(NSString *)label usage:(unsigned)usage position:(CGPoint)position;
- (void)layoutInRect:(CGRect)rect;
- (void)cancelInput;
- (void)syncWithEvent:(UIEvent *)event;
- (BOOL)containsKeyPoint:(CGPoint)point;
@end

// As with the joystick, a contact starting in the invisible margin stays inert until it lifts.
@interface SPKeyboardShield : UIView
@property(nonatomic, weak) SPKeyboardButton *button;
@end
@implementation SPKeyboardShield
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGPoint p = [self.button convertPoint:point fromView:self];
    return [self.button pointInside:p withEvent:event] && ![self.button containsKeyPoint:p];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {}
@end

@implementation SPKeyboardButton {
    NSString *_name, *_enabledKey, *_positionKey;
    unsigned _usage;
    UIView *_face;
    UILabel *_label;
    SPJoystickHandle *_handle;
    SPKeyboardShield *_shield;
    UITouch *_touch;
    CGPoint _position, _defaultPosition, _fingerStart, _centerStart;
    CGRect _centers;
    BOOL _moving, _keyDown, _placementLocked;
}
- (instancetype)initWithName:(NSString *)name label:(NSString *)label usage:(unsigned)usage position:(CGPoint)position {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _name = name; _usage = usage; _position = _defaultPosition = position;
    _enabledKey = [NSString stringWithFormat:@"sp_%@_enabled", name];
    _positionKey = [NSString stringWithFormat:@"sp_%@_position", name];
    self.hidden = YES;
    self.exclusiveTouch = NO;
    self.multipleTouchEnabled = NO;
    self.layer.zPosition = 1200;
    self.accessibilityIdentifier = [@"sp.key-" stringByAppendingString:name];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = label;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityHint = @"Hold to press this key. Drag to save a new position.";
    _face = [UIView new]; _face.userInteractionEnabled = NO;
    _face.layer.cornerRadius = 8; _face.layer.borderWidth = 1.5;
    [self addSubview:_face];
    _label = [UILabel new]; _label.text = label; _label.textAlignment = NSTextAlignmentCenter;
    _label.adjustsFontSizeToFitWidth = YES; _label.minimumScaleFactor = 0.5;
    [_face addSubview:_label];
    if (usage == 0x2C) {
        self.accessibilityLabel = @"Spacebar";
        self.accessibilityHint = @"Press anywhere in the circle to hold Space. Hold still for two seconds until the ring fills, then drag to move.";
        _shield = [SPKeyboardShield new]; _shield.button = self;
        _shield.multipleTouchEnabled = YES;
        _shield.accessibilityIdentifier = @"sp.key-space-shield";
        [self insertSubview:_shield atIndex:0];
        _handle = [[SPJoystickHandle alloc] initWithFrame:CGRectZero];
        _handle.joystick = self; _handle.ring = YES;
        // The ring only draws feedback. Forward the circle's touch into its existing hold state machine.
        _handle.userInteractionEnabled = NO;
        _handle.isAccessibilityElement = NO;
        _handle.accessibilityIdentifier = @"sp.key-space-move";
        [self addSubview:_handle];
    }
    [self setHighlighted:NO];
    return self;
}
- (NSString *)name { return _name; }
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    UIColor *gold = [UIColor colorWithRed:0.78 green:0.73 blue:0.59 alpha:1];
    _face.backgroundColor = highlighted ? gold : [UIColor colorWithWhite:0.06 alpha:0.8];
    _face.layer.borderColor = [gold colorWithAlphaComponent:highlighted ? 1 : 0.7].CGColor;
    _label.textColor = highlighted ? [UIColor colorWithWhite:0.06 alpha:1] : gold;
    self.accessibilityValue = _face.accessibilityValue = highlighted ? @"Held" : @"Released";
}
- (void)releaseKey {
    if (_keyDown) sp_touch_key(_usage, NO);
    _keyDown = NO;
    [self setHighlighted:NO];
}
- (void)cancelInput {
    [self releaseKey];
    _touch = nil;
    [self endMove];
    [_handle cancelTouch];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self cancelInput];
}
- (void)layoutInRect:(CGRect)rect {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (!_handle) {
        if (_touch && sp_button_positions_locked()) _placementLocked = YES;
        self.accessibilityHint = sp_button_positions_locked()
            ? @"Hold to press this key. Position is locked in Settings."
            : @"Hold to press this key. Drag to save a new position.";
    }
    id savedSize = [defaults objectForKey:sp_keyboard_size_key];
    double size = [savedSize isKindOfClass:NSNumber.class] ? [savedSize doubleValue] : sp_keyboard_default_size;
    if (!isfinite(size)) size = sp_keyboard_default_size;
    size = MAX(sp_keyboard_min_size, MIN(sp_keyboard_max_size, size));
    CGFloat outer = size + (_handle ? 52 : 0), minimum = sp_keyboard_min_size + (_handle ? 52 : 0);
    BOOL room = !CGRectIsNull(rect) && rect.size.width >= minimum + 16 && rect.size.height >= minimum + 16;
    if (room) outer = MIN(outer, MIN(rect.size.width, rect.size.height) - 16);
    CGRect centers = room ? CGRectInset(rect, outer / 2 + 8, outer / 2 + 8) : CGRectZero;
    BOOL enabled = [defaults boolForKey:_enabledKey];  // optional buttons start hidden
    if (!enabled || !room || !CGRectEqualToRect(centers, _centers)) [self cancelInput];
    self.hidden = !enabled || !room;
    if (self.hidden) return;
    _centers = centers;
    if (!_moving && !_touch) {
        _position = _defaultPosition;
        id saved = [defaults objectForKey:_positionKey];
        if ([saved isKindOfClass:NSArray.class] && [saved count] == 2 &&
            [saved[0] isKindOfClass:NSNumber.class] && [saved[1] isKindOfClass:NSNumber.class]) {
            double x = [saved[0] doubleValue], y = [saved[1] doubleValue];
            if (isfinite(x) && isfinite(y)) _position = CGPointMake(MAX(0, MIN(1, x)), MAX(0, MIN(1, y)));
        }
    }
    self.bounds = CGRectMake(0, 0, outer, outer);
    self.center = CGPointMake(centers.origin.x + centers.size.width * _position.x,
                             centers.origin.y + centers.size.height * _position.y);
    CGFloat face = _handle ? outer - 52 : outer;
    _face.bounds = CGRectMake(0, 0, face, _handle ? MAX(32, face * 0.58) : face);
    _face.center = CGPointMake(outer / 2, outer / 2);
    _label.frame = CGRectInset(_face.bounds, 4, 0);
    _label.font = [UIFont systemFontOfSize:round(face * 0.27) weight:UIFontWeightSemibold];
    _handle.frame = self.bounds;
    _shield.frame = CGRectInset(self.bounds, -sp_joystick_touch_margin, -sp_joystick_touch_margin);
}
- (BOOL)containsKeyPoint:(CGPoint)point {
    if (!_handle) return CGRectContainsPoint(self.bounds, point);
    CGFloat r = self.bounds.size.width / 2;
    return hypot(point.x - r, point.y - r) <= r;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (!_handle) return [super pointInside:point withEvent:event];
    if ([self containsKeyPoint:point]) return YES;
    if (event && event.type != UIEventTypeTouches) return NO;
    for (UITouch *touch in event.allTouches) {
        CGPoint p = [touch locationInView:self];
        if (touch.phase == UITouchPhaseBegan && hypot(p.x - point.x, p.y - point.y) < 0.5 &&
            touch.type != UITouchTypeDirect) return NO;
    }
    CGFloat r = self.bounds.size.width / 2;
    return hypot(point.x - r, point.y - r) <= r + sp_joystick_touch_margin;
}
- (void)syncWithEvent:(UIEvent *)event {
    if (self.hidden) return;
    for (UITouch *touch in event.allTouches) {
        if (touch.view != self) continue;
        NSSet *set = [NSSet setWithObject:touch];
        if (touch.phase == UITouchPhaseBegan) [self touchesBegan:set withEvent:event];
        else if (touch.phase == UITouchPhaseEnded) [self touchesEnded:set withEvent:event];
        else if (touch.phase == UITouchPhaseCancelled) [self touchesCancelled:set withEvent:event];
    }
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.hidden || _touch || _moving) return;
    for (UITouch *touch in touches) if (touch.type == UITouchTypeDirect || touch.type == UITouchTypePencil) {
        _touch = touch;
        _placementLocked = !_handle && sp_button_positions_locked();
        _fingerStart = [touch locationInView:self.superview]; _centerStart = self.center;
        sp_touch_key(_usage, YES);
        _keyDown = YES;
        [self setHighlighted:YES];
        [_handle touchesBegan:[NSSet setWithObject:touch] withEvent:event];
        break;
    }
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_touch || ![touches containsObject:_touch]) return;
    if (_handle) { [_handle touchesMoved:touches withEvent:event]; return; }
    if (sp_button_positions_locked()) _placementLocked = YES;
    if (_placementLocked) return;
    CGPoint at = [_touch locationInView:self.superview];
    if (!_moving && hypot(at.x - _fingerStart.x, at.y - _fingerStart.y) < 10) return;
    _moving = YES;
    [self moveWithTouch:_touch];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch && [touches containsObject:_touch]) {
        [_handle touchesEnded:touches withEvent:event];
        [self touchesMoved:touches withEvent:event];
        [self releaseKey]; _touch = nil; [self endMove];
    }
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_touch && [touches containsObject:_touch]) [self cancelInput];
}
- (void)beginMove:(UITouch *)touch {
    [self releaseKey];
    _moving = YES;
    _fingerStart = [touch locationInView:self.superview]; _centerStart = self.center;
}
- (void)moveWithTouch:(UITouch *)touch {
    if (!_moving) return;
    if (!_handle && (_placementLocked || sp_button_positions_locked())) return;
    CGPoint p = [touch locationInView:self.superview];
    self.center = CGPointMake(MAX(CGRectGetMinX(_centers), MIN(CGRectGetMaxX(_centers), _centerStart.x + p.x - _fingerStart.x)),
                              MAX(CGRectGetMinY(_centers), MIN(CGRectGetMaxY(_centers), _centerStart.y + p.y - _fingerStart.y)));
    _position = CGPointMake(_centers.size.width ? (self.center.x - _centers.origin.x) / _centers.size.width : 0,
                            _centers.size.height ? (self.center.y - _centers.origin.y) / _centers.size.height : 0);
}
- (void)endMove {
    if (!_moving) return;
    _moving = NO;
    [NSUserDefaults.standardUserDefaults setObject:@[@(_position.x), @(_position.y)] forKey:_positionKey];
}
@end
