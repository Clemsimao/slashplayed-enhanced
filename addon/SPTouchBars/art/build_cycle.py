#!/usr/bin/env python3
"""Build our vector cycle icon and its WoW-compatible, antialiased RGBA texture.

Requires Pillow only when regenerating; the addon ships the prebuilt TGA.
SVG and raster use the same geometry, with 8x supersampling before downsampling.
"""
from math import cos, sin, radians
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

root = Path(__file__).resolve().parent
size, scale = 256, 8
factor = size * scale / 56
stroke = 2.4
mask = Image.new('L', (size * scale, size * scale), 0)
draw = ImageDraw.Draw(mask)
paths = []
def point(angle):
    a = radians(angle)
    return 28 + 17 * cos(a), 28 + 17 * sin(a)
def fmt(p):
    return f'{p[0]:.6f} {p[1]:.6f}'
def rounded_line(points):
    coords = [(x * factor, y * factor) for x, y in points]
    width = round(stroke * factor)
    draw.line(coords, fill=255, width=width, joint='curve')
    r = width / 2
    for x, y in coords:
        draw.ellipse((x-r, y-r, x+r, y+r), fill=255)

# Finish each arc with a short tangent before the arrowhead. A symmetric 90-degree
# head then meets a straight shaft; placing it directly on the arc made the inner
# wing crowd the curve and left the opposite wing looking like an upright hook.
for rotation in (0, 180):
    start, end = -180 + rotation, -45 + rotation
    first, shoulder = point(start), point(end)
    def rotate(p):
        return p if rotation == 0 else (56-p[0], 56-p[1])
    tip = rotate((44, 20))
    wings = [rotate((44, 12.5)), rotate((36.5, 20))]
    paths.append(f'<path d="M{fmt(first)} A17 17 0 0 1 {fmt(shoulder)} L{fmt(tip)}"/>')
    paths.append(f'<path d="M{fmt(wings[0])} L{fmt(tip)} L{fmt(wings[1])}"/>')
    rounded_line([point(start + i * 135 / 540) for i in range(541)] + [tip])
    rounded_line([wings[0], tip, wings[1]])
svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 56 56" fill="none" stroke="white" stroke-width="{stroke}" stroke-linecap="round" stroke-linejoin="round">\n  ' + '\n  '.join(paths) + '\n</svg>\n'
(root / 'cycle.svg').write_text(svg)
mask = mask.resize((size, size), Image.Resampling.LANCZOS)
# Separate hollow rim and halo tiles keep the centre transparent. Reusing the
# ordinary filled button shells here would stack opaque discs behind the arrows.
ring = Image.new('L', (size * scale, size * scale), 0)
rd = ImageDraw.Draw(ring)
radius, width = 26.8 * factor, 1.2 * factor
cx = cy = size * scale / 2
rd.ellipse((cx-radius-width/2, cy-radius-width/2, cx+radius+width/2, cy+radius+width/2), fill=255)
rd.ellipse((cx-radius+width/2, cy-radius+width/2, cx+radius-width/2, cy+radius-width/2), fill=0)
ring = ring.resize((size, size), Image.Resampling.LANCZOS)
halo = ring.filter(ImageFilter.GaussianBlur(size * 1.2 / 56))
image = Image.new('RGBA', (size * 4, size), (255, 255, 255, 0))
for index, alpha in enumerate((mask, ring, halo)):
    tile = Image.new('RGBA', (size, size), (255, 255, 255, 255))
    tile.putalpha(alpha)
    image.paste(tile, (index * size, 0))
# Uncompressed power-of-two RGBA atlas. White RGB in transparent pixels avoids
# dark fringes; the unused fourth tile keeps dimensions supported by WoW.
image.save(root.parent / 'SPTouchBars.tga', compression=None)
print('Built cycle.svg and SPTouchBars.tga (1024 x 256 RGBA: arrows, hollow rim, halo)')
