// Pixel geometry shared by the AppKit shim and its game-free tests. Fixed presets name the longer
// edge, so rotating or resizing a window preserves its aspect ratio rather than stretching 16:9.
#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>

static CGSize sp_resolution_pixels(CGSize points, CGFloat scale, BOOL fixed) {
    CGSize pixels = CGSizeMake(points.width * scale, points.height * scale);
    // Whole, even pixels keep render targets valid and round a 1366x1024 iPad to 1920x1440 rather
    // than 1920x1439. Automatic keeps the existing point-to-pixel conversion exactly.
    if (fixed) {
        pixels.width = MAX(2, round(pixels.width / 2) * 2);
        pixels.height = MAX(2, round(pixels.height / 2) * 2);
    }
    return pixels;
}

static CGRect sp_screen_in_orientation(CGSize screen, CGSize window) {
    CGFloat longer = MAX(screen.width, screen.height), shorter = MIN(screen.width, screen.height);
    BOOL portrait = window.height > window.width;
    return CGRectMake(0, 0, portrait ? shorter : longer, portrait ? longer : shorter);
}
