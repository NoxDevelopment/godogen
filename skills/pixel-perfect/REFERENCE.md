# Pixel Cleanup — Deep Reference (research 2026-07-11)

Why the noise exists: diffusion renders "pixels" as ~4–16px blocks that are
misaligned to any grid, non-uniform in size, anti-aliased at borders, and
color-jittered within blocks. Naive nearest-neighbor downscale keeps the noise.
The fix is **grid rectification**, not filtering.

## The 8-step recipe (verified across unfake.js / proper-pixel-art / Sorceress / Pixellab / AIOriented)

0. **Prevention at generation time**: prompt logical resolution delivered at 4x;
   pass a B/W checkerboard grid reference as conditioning discipline; solid
   chroma background (#FF00FF / #00FF00); negatives: photorealism, painterly
   blending, anti-aliased halos.
1. **Pre-clean**: trim borders; zero alpha < 50%.
2. **Detect true pixel scale**: runs-based (dominant run length of same-color
   pixels) cross-checked with edge autocorrelation; robust fallback for warped
   grids = Canny → morph close → probabilistic Hough → median line spacing
   (non-uniform mesh). ALWAYS expose a manual override (auto fails 10–20%).
3. **Snap phase/crop**: offset grid origin to maximize edge coincidence, crop to
   integer cells — skipping this causes residual shimmer.
4. **Downscale 1px/cell**: dominant/mode (flat-shaded), median (speckle),
   QVote = quantize-then-vote (when palette known). NEVER mean/bilinear.
   Non-pixel art conversion: PixelOE (contrast-aware outline expansion) instead.
5. **Palette quantize**: AFTER grid rectification (except QVote). Fixed-palette
   map or Wu/k-means to 8–128. Optional dither: none/ordered/Floyd-Steinberg.
6. **Morph post-clean**: fill 1px holes, kill orphan pixels, de-jaggy;
   alpha binarize (0/255); chroma-key LAST — flood-fill key from borders beats
   global key; edge-trim + edge-expansion kills halo fringes.
7. **Animation**: detect grid + build palette ONCE across sampled frames, apply
   to all (per-frame detection = flicker). Then normalize: alpha-bbox extract,
   height-correct vs reference cycle, re-canvas at locked center_x/foot_y,
   rebuild atlas, contact sheet + GIF QA.
8. **Human review**: side-by-side before/after; expect an Aseprite pass.

## Tool ecosystem (all open, CPU-fast)

| Tool | Strength |
|---|---|
| `tools/pixel_snap.py` (ours) | elastic-walker grid snap + palette lock; port of spritefusion-pixel-snapper (MIT) |
| unfake.js / `unfake` (PyPI) | runs+edge detection, QVote, morph cleanup, alpha binarize, .gpl support |
| proper-pixel-art (`ppa`) | Hough mesh for NON-uniform grids; `pixelate_video()` = one-grid-one-palette video mode |
| PixelOE | non-pixel → pixel conversion (outline expansion before downscale) |
| Astropulse pixeldetector | the OG auto-detect + downscale; simple, reliable |
| ComfyUI-PixelArt-Detector | in-Comfy palette loader/generator/converter + custom dither masks |

## Parity notes (what the commercial tools add on top)

- Sorceress Pixel Snap: neural chroma key ("CorridorKey"), head/feet anchor
  alignment, sheet metadata (rows/cols/fps/loop) on export.
- Pixellab: skeleton estimation from sprite, animation→animation motion
  retargeting, frozen-frame keyframe regen, frame interpolation, outfit
  transfer across frames, 8-rotation generation, dual-terrain Wang tilesets.
- MagicPixel: silhouette-preserving reskins, matching item sets, .aseprite
  round-trip, palette-file import (.gpl/.hex/.pal), CLI repo sync.

Build plan for closing these: `Noxdev-Studio/docs/PIXEL_STUDIO_SPEC.md`.
