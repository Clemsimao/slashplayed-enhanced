// The start screen's logo (spstartscreen.swift), drawn as paths from the app icon's own vectors, with no artwork of
// its own: apps/client/icons/AppIcon.icon/Assets/medallion.svg (a square under a disc with a ring) and S.svg
// (the S), in their 1024-unit space. The companion's StartScreenLogoTests check these against the two
// files, so an icon change that isn't copied here fails the tests.
#ifndef SPLOGO_H
#define SPLOGO_H

// medallion.svg: the square (x, y, width, height), then the disc's center, radius, and ring width (an SVG
// stroke, centered on the radius), and the disc's fill. The square and the ring take the icon's gold.
#define SP_LOGO_SQUARE_ORIGIN 175.0
#define SP_LOGO_SQUARE_SIDE 674.0
#define SP_LOGO_DISC_CENTER 512.0
#define SP_LOGO_DISC_RADIUS 376.5
#define SP_LOGO_RING_WIDTH 47.0
#define SP_LOGO_DISC_FILL "#243b34"
#define SP_LOGO_GOLD "#ac9d79"

// S.svg's path, its `d` attribute verbatim (absolute M, L, H, V, C, and Z only).
#define SP_LOGO_S_PATH "M683.448 551.627L673.285 632.935V718.054L518.291 817.148L402.046 747.909L343.606 772.048L374.732 597.998L400.776 632.935C409.669 645.004 420.468 652.627 435.078 661.52L515.75 711.067L576.096 672.954V608.796L362.663 476.671V423.948L349.323 307.067L515.115 209.879L626.279 277.847H682.813L637.077 415.69L630.09 404.256C621.197 389.646 607.857 374.401 593.247 365.507L513.845 317.231L457.946 350.262V412.514L683.448 551.627Z"

#endif
