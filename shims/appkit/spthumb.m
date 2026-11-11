// A thumb resting here modifies a finger's or Pencil's click; it never presses a mouse button itself.
// Included by spevent.m on iPhone and iPad only. UIKit owns this touch separately from the game view,
// so moving the square cannot steer the camera or join a two-finger chord.
#import <UIKit/UIKit.h>
#include <math.h>

static NSString *const sp_thumb_enabled_key = @"sp_thumb_enabled";
static NSString *const sp_thumb_position_key = @"sp_thumb_position";
static NSString *const sp_thumb_size_key = @"sp_thumb_size";
// Keep the default and limits in step with Settings > Touch (spsettings.swift).
static const CGFloat sp_thumb_default_size = 76, sp_thumb_min_size = 44, sp_thumb_max_size = 152;

@interface SPThumbButton : UIControl
- (void)layoutInRect:(CGRect)rect;
- (BOOL)heldInEvent:(UIEvent *)event;
- (void)cancelHold;
@end

@implementation SPThumbButton {
    UITouch *_thumbTouch;
    UILabel *_label;
    CGPoint _position, _fingerStart, _centerStart;
    CGRect _centers;
    BOOL _dragging;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.exclusiveTouch = NO;  // the other hand must still reach the game
    self.multipleTouchEnabled = NO;
    self.layer.cornerRadius = 8;
    self.layer.borderWidth = 1.5;
    self.layer.zPosition = 1200;  // above the game and hover targets, below the loading screen
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = @"Right-click modifier";
    self.accessibilityHint = @"Hold while tapping the game to right-click. Drag this square to move it.";
    self.accessibilityIdentifier = @"sp.thumb-right-click";
    _label = [[UILabel alloc] initWithFrame:self.bounds];
    _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _label.text = @"R";
    _label.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    _label.textAlignment = NSTextAlignmentCenter;
    _label.userInteractionEnabled = NO;
    [self addSubview:_label];
    [self setHighlighted:NO];
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    UIColor *gold = [UIColor colorWithRed:0.78 green:0.73 blue:0.59 alpha:1];
    self.backgroundColor = highlighted ? [gold colorWithAlphaComponent:0.95]
                                      : [UIColor colorWithWhite:0.06 alpha:0.65];
    self.layer.borderColor = [gold colorWithAlphaComponent:highlighted ? 1 : 0.7].CGColor;
    _label.textColor = highlighted ? [UIColor colorWithWhite:0.06 alpha:1] : gold;
    self.accessibilityValue = highlighted ? @"Held" : @"Released";
}

- (CGPoint)clampedCenter:(CGPoint)point {
    return CGPointMake(MAX(CGRectGetMinX(_centers), MIN(CGRectGetMaxX(_centers), point.x)),
                       MAX(CGRectGetMinY(_centers), MIN(CGRectGetMaxY(_centers), point.y)));
}

- (void)layoutInRect:(CGRect)rect {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL enabled = ![defaults objectForKey:sp_thumb_enabled_key] || [defaults boolForKey:sp_thumb_enabled_key];
    id savedSize = [defaults objectForKey:sp_thumb_size_key];
    double size = [savedSize isKindOfClass:NSNumber.class] ? [savedSize doubleValue] : sp_thumb_default_size;
    if (!isfinite(size)) size = sp_thumb_default_size;
    size = MAX(sp_thumb_min_size, MIN(sp_thumb_max_size, size));
    BOOL room = !CGRectIsNull(rect) && rect.size.width >= sp_thumb_min_size + 16 && rect.size.height >= sp_thumb_min_size + 16;
    // A narrow resized window may need a smaller target temporarily; retain the preferred size.
    if (room) size = MIN(size, MIN(rect.size.width, rect.size.height) - 16);
    CGRect centers = room ? CGRectInset(rect, size / 2 + 8, size / 2 + 8) : CGRectZero;
    if (!enabled || !room || !CGRectEqualToRect(centers, _centers)) [self cancelHold];
    self.hidden = !enabled || !room;
    if (self.hidden) return;
    _centers = centers;
    if (!_thumbTouch) {
        _position = CGPointMake(0, 0.82);
        id saved = [defaults objectForKey:sp_thumb_position_key];
        if ([saved isKindOfClass:NSArray.class] && [saved count] == 2 &&
            [saved[0] isKindOfClass:NSNumber.class] && [saved[1] isKindOfClass:NSNumber.class]) {
            double x = [saved[0] doubleValue], y = [saved[1] doubleValue];
            if (isfinite(x) && isfinite(y)) _position = CGPointMake(MAX(0, MIN(1, x)), MAX(0, MIN(1, y)));
        }
    }
    self.bounds = CGRectMake(0, 0, size, size);
    _label.font = [UIFont systemFontOfSize:round(size * 18 / 52) weight:UIFontWeightSemibold];
    self.layer.cornerRadius = MIN(16, size * 8 / 52);
    self.center = CGPointMake(centers.origin.x + centers.size.width * _position.x,
                             centers.origin.y + centers.size.height * _position.y);
}

static BOOL sp_thumb_touch_active(UITouch *touch) {
    return touch && touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled;
}

- (BOOL)heldInEvent:(UIEvent *)event {
    if (self.hidden || !self.enabled) return NO;
    // UIKit may deliver the game finger before the square's touchesBegan (or touchesEnded) in the
    // same event. Inspect the event too, so callback order cannot change which button the tap gets.
    if (sp_thumb_touch_active(_thumbTouch)) return YES;
    for (UITouch *touch in event.allTouches)
        if (touch.view == self && touch.type == UITouchTypeDirect && touch.phase == UITouchPhaseBegan) return YES;
    return NO;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (_thumbTouch) return;
    for (UITouch *touch in touches) {
        if (touch.type != UITouchTypeDirect) continue;
        _thumbTouch = touch;
        _fingerStart = [touch locationInView:self.superview];
        _centerStart = self.center;
        _dragging = NO;
        [self setHighlighted:YES];
        break;
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!_thumbTouch || ![touches containsObject:_thumbTouch]) return;
    CGPoint at = [_thumbTouch locationInView:self.superview];
    CGFloat dx = at.x - _fingerStart.x, dy = at.y - _fingerStart.y;
    // A resting thumb can drift slightly without relocating the button.
    if (!_dragging && hypot(dx, dy) < 10) return;
    _dragging = YES;
    self.center = [self clampedCenter:CGPointMake(_centerStart.x + dx, _centerStart.y + dy)];
    _position = CGPointMake(_centers.size.width ? (self.center.x - _centers.origin.x) / _centers.size.width : 0,
                            _centers.size.height ? (self.center.y - _centers.origin.y) / _centers.size.height : 0);
}

- (void)cancelHold {
    if (_dragging) {
        // Fractions of the usable center range keep the square reachable after rotation or resizing.
        [NSUserDefaults.standardUserDefaults setObject:@[@(_position.x), @(_position.y)] forKey:sp_thumb_position_key];
    }
    _thumbTouch = nil;
    _dragging = NO;
    [self setHighlighted:NO];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([touches containsObject:_thumbTouch]) {
        [self touchesMoved:touches withEvent:event];
        [self cancelHold];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if ([touches containsObject:_thumbTouch]) [self cancelHold];
}
@end
