// NSBitmapImageRep, NSImage and NSCursor, enough for the client to build cursor images: it makes a
// bitmap rep, writes pixels through -bitmapData, wraps it in an NSImage and makes an NSCursor from
// that. #included at the end of the generated libspAppKit.m. The stub classes have no ivars, so state
// lives in associated objects, as in spwindow.m. visionOS has no app-defined pointer cursor, so -set,
// +hide and +unhide go to the cursor spevent.m draws over the game (sp_cursor_set, sp_cursor_hide).

static char sp_bitmap_key, sp_bitmap_info_key, sp_image_size_key, sp_image_reps_key, sp_cursor_image_key,
    sp_cursor_hot_key;

static void sp_cursor_set(id cursor);
static void sp_cursor_hide(BOOL hide);

@implementation NSBitmapImageRep (SPImage)
- (instancetype)initWithBitmapDataPlanes:(unsigned char **)planes pixelsWide:(NSInteger)width
                              pixelsHigh:(NSInteger)height bitsPerSample:(NSInteger)bps
                         samplesPerPixel:(NSInteger)spp hasAlpha:(BOOL)alpha isPlanar:(BOOL)planar
                          colorSpaceName:(NSString *)colorSpace bitmapFormat:(NSUInteger)format
                             bytesPerRow:(NSInteger)rowBytes bitsPerPixel:(NSInteger)bpp {
    if (!bpp) bpp = bps * spp;
    if (!rowBytes) rowBytes = (width * bpp + 7) / 8;
    sp_stub_log([NSString stringWithFormat:@"-[NSBitmapImageRep initWithBitmapDataPlanes:%s] %ldx%ld %ld bpp, %ld bytes/row",
                 planes && planes[0] ? "caller's" : "own", (long)width, (long)height, (long)bpp, (long)rowBytes].UTF8String);
    if (planar && spp > 1) return nil;  // one plane only; nothing here asks for more
    // With no planes (or a NULL first plane) the rep owns its buffer, zeroed; otherwise it uses the caller's.
    NSMutableData *data = planes && planes[0]
        ? [NSMutableData dataWithBytesNoCopy:planes[0] length:rowBytes * height freeWhenDone:NO]
        : [NSMutableData dataWithLength:rowBytes * height];
    objc_setAssociatedObject(self, &sp_bitmap_key, data, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &sp_bitmap_info_key, @[ @(width), @(height), @(bpp), @(rowBytes), @(format) ],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return self;
}
- (unsigned char *)bitmapData {
    return [objc_getAssociatedObject(self, &sp_bitmap_key) mutableBytes];
}
- (NSInteger)pixelsWide { return [objc_getAssociatedObject(self, &sp_bitmap_info_key)[0] integerValue]; }
- (NSInteger)pixelsHigh { return [objc_getAssociatedObject(self, &sp_bitmap_info_key)[1] integerValue]; }
- (NSInteger)bitsPerPixel { return [objc_getAssociatedObject(self, &sp_bitmap_info_key)[2] integerValue]; }
- (NSInteger)bytesPerRow { return [objc_getAssociatedObject(self, &sp_bitmap_info_key)[3] integerValue]; }
- (NSUInteger)bitmapFormat { return [objc_getAssociatedObject(self, &sp_bitmap_info_key)[4] unsignedIntegerValue]; }
- (CGSize)size { return CGSizeMake(self.pixelsWide, self.pixelsHigh); }
@end

@implementation NSImage (SPImage)
- (instancetype)initWithSize:(CGSize)size {
    [self setSize:size];
    objc_setAssociatedObject(self, &sp_image_reps_key, [NSMutableArray array], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return self;
}
- (void)setSize:(CGSize)size {
    objc_setAssociatedObject(self, &sp_image_size_key, [NSValue valueWithCGSize:size], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (CGSize)size { return [objc_getAssociatedObject(self, &sp_image_size_key) CGSizeValue]; }
- (void)addRepresentation:(id)rep { [objc_getAssociatedObject(self, &sp_image_reps_key) addObject:rep]; }
- (NSArray *)representations { return [objc_getAssociatedObject(self, &sp_image_reps_key) copy] ?: @[]; }
@end

@implementation NSCursor (SPImage)
- (instancetype)initWithImage:(id)image hotSpot:(CGPoint)hotSpot {
    static int logged;
    if (logged++ < 5)
        sp_stub_log([NSString stringWithFormat:@"-[NSCursor initWithImage:hotSpot:] image %gx%g pt, hot spot %g,%g",
                     [image size].width, [image size].height, hotSpot.x, hotSpot.y].UTF8String);
    objc_setAssociatedObject(self, &sp_cursor_image_key, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &sp_cursor_hot_key, [NSValue valueWithCGPoint:hotSpot], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return self;
}
- (id)image { return objc_getAssociatedObject(self, &sp_cursor_image_key); }
- (CGPoint)hotSpot { return [objc_getAssociatedObject(self, &sp_cursor_hot_key) CGPointValue]; }
- (void)set { sp_cursor_set(self); }
+ (void)hide { sp_cursor_hide(YES); }
+ (void)unhide { sp_cursor_hide(NO); }
@end
