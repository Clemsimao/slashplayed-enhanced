# Icons

Our own artwork: a gold S on a ringed medallion. The S is the Goodmountain typeface by Hermann S
Designs (github.com/Hermann-S-Designs/Goodmountain; its license allows commercial work), outlined, so
the font itself is never needed or committed. Nothing here comes from the game. The design lives in
Figma; these SVGs are exported from it (text outlined) and rendered with `rsvg-convert`.

- `icon.svg`: the full-bleed master (background, medallion, S). `site/icon-1024.png` is it at 1024 px:
  `rsvg-convert -w 1024 -h 1024 icon.svg -o ../site/icon-1024.png`
- `apps/client/icons/AppIcon.icon`: the Icon Composer icon for iOS and the companion (macOS), compiled by
  actool (`apps/client/build-icons.sh` for the device app, Xcode's resources phase for the companion,
  with the legacy fallbacks for older systems). Its background is a solid fill in `icon.json`; its two
  glass layers, `Assets/medallion.svg` and `Assets/S.svg`, are `icon.svg` split apart. Edit them in
  Icon Composer, or by hand alongside `icon.svg`.
- The visionOS icon (visionOS has no `.icon`) is the same three layers as a solid image stack in
  `apps/client/icons/xros.xcassets/AppIcon.solidimagestack/`, each rendered at 1024 px to
  `<Layer>.solidimagestacklayer/Content.imageset/visionos-<layer>.png`: back from
  `icon-visionos-back.svg` (opaque), middle from `Assets/medallion.svg`, front from `Assets/S.svg`
  (transparent). visionOS masks the stack to a circle.
