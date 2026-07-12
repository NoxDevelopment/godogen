---
name: pixel-perfect
description: Fix the AI pixel-art noise pattern — snap fake pixel art to a true grid with a strict palette — and convert any image/video (photos, movies, GIFs) into clean pixel art and pixel animation. Use after ANY AI pixel-art generation, before an asset ships, and for photo-to-pixel or video-to-pixel-animation requests.
---

# Pixel Perfect — kill the noise pattern

AI image models cannot produce grid-true pixel art: pixels drift in size and
position, the grid wobbles across the image, and colors smear off-palette.
Every "pixel art" output is FAKE pixel art until snapped. This skill makes it real.

## tools/pixeltool.py — unified cleanup CLI (PREFERRED ENTRY POINT)

One front-end over four backends, auto-dispatched: `snap` (our pixel_snap,
default), `unfake` (PyPI: runs/edge detect, QVote, morph, alpha binarize,
flood key), `hough` (proper-pixel-art PyPI: mesh for NON-uniform/warped
grids), `pixeloe` (PyPI: outline expansion — photo/render → pixel; never
auto-chosen, pass `--backend pixeloe`). Backends are pip deps
(`tools/requirements.txt`), not vendored. Missing backend flags (dither,
chroma key, morph, palette lock) are implemented locally — nothing is dropped.

```
# grid-true cleanup, auto backend
python tools/pixeltool.py clean in.png out.png --pixel-size 8 --colors 32 --json

# warped/non-uniform grid            -> hough mesh
python tools/pixeltool.py clean in.png out.png --detect hough --colors 16

# heavy cleanup (QVote + despeckle)  -> unfake
python tools/pixeltool.py clean in.png out.png --downscale qvote --morph --alpha-binarize

# photo -> pixel art (no grid yet)   -> PixelOE
python tools/pixeltool.py clean photo.png out.png --backend pixeloe --pixel-size 8 --colors 32

# chroma-bg sprite: key #FF00FF connected to the border only
python tools/pixeltool.py clean sprite.png out.png --chroma flood --alpha-binarize
```

Full flags (`--dither none|ordered|fs`, `--palette`, `--chroma global|flood`,
`--chroma-color/-tol`, `--scale N` preview, `--backend`): see `clean --help`.
Output is always a true-resolution PNG. `--pixel-size 1` = image already at
true res (skips grid detection; palette/post-ops only).

## tools/pixel_snap.py

Python port of spritefusion-pixel-snapper (MIT, Hugo Duprez) with NoxDev
upgrades: exact palette lock, fundamental-step detection, JSON output, preview
scaling. Algorithm: palette quantize → luminance-gradient grid profiles →
elastic walker snaps cuts to real pixel boundaries (survives drifting grids) →
cross-axis stabilization → majority-vote resample to TRUE 1px cells.

```
# auto-detect grid, 16-color k-means palette
python tools/pixel_snap.py in.png out.png --colors 16 --scale 4 --json

# known grid (ALWAYS pass this in pipelines — our workflows set the grid)
python tools/pixel_snap.py in.png out.png --pixel-size 8 --colors 32

# lock to the project's exact palette (VisualIdentity palette-lock)
python tools/pixel_snap.py in.png out.png --palette "#0f380f,#306230,#8bac0f,#9bbc0f"
```

Output = true-resolution PNG (1 image pixel per art pixel) — the shippable
asset. `--scale N` writes a nearest-neighbor preview. Engines must import with
nearest filtering (Godot: texture filter "Nearest").

**Auto-detect caveat:** when art has no adjacent-cell color changes, cell size
is mathematically ambiguous (4px vs 8px pairs look identical to gradients).
Pass `--pixel-size` whenever the grid is known; try both and eyeball otherwise.

## The cleanup contract

- EVERY AI pixel output gets snapped before it ships or trains. No exceptions —
  unsnapped "pixel art" is the noise pattern the studio bans.
- Snap at TRUE resolution, store the true-res PNG, upscale only at
  display/import time (nearest).
- Palette: use `--palette` with the project's locked palette when one exists
  (VisualIdentity), else `--colors` sized to the style (8–16 retro, 32–64 modern).
- Sprite sheets: snap the whole sheet ONCE (uniform grid across frames), never
  per-frame (per-frame snapping desyncs cell boundaries between frames).

## Photo → pixel art (any image, incl. real people)

Pure downscale+quantize of a photo reads as a mosaic, not pixel ART. The
quality recipe restyles first:

1. `zit-txt2img`-style img2img: photo as init (denoise 0.5–0.65) + pixel LoRA
   (`pixel_art_style_z_image_turbo`) + style prompt ("pixel art portrait, ...").
   For strong likeness keep denoise low + add a face-lock pass if needed.
2. Downscale to target grid (area) → `pixel_snap.py --pixel-size 1 --palette ...`
   (after an area-downscale the grid is already 1:1; snap = palette lock +
   majority cleanup).
3. Fast/lo-fi alternative (no GPU): straight `pixel_snap.py` on the photo with
   `--pixel-size <src_w/target_w>` — honest retro-mosaic look.

## Video/GIF → pixel animation (movies → sprite loops)

1. Extract frames (ffmpeg, cap fps at 8–12 — pixel animation reads better low).
2. Restyle: Wan2.2 V2V (Fun-Control depth/pose from source) + pixel-animate
   LoRA for full restyle; or per-frame img2img with FIXED seed + same LoRA for
   short GIFs.
3. Batch-snap all frames with ONE shared `--pixel-size` and `--palette`
   (temporal palette lock prevents flicker).
4. Reassemble: GIF/spritesheet (kjnodes Image Grid) → `engine-export
   sprite-frames` for Godot.

## Fit in the pipeline

`image-pipeline` pixel types and the `zit-pixel-art` workflow already downscale
+ quantize; pixel_snap is the stronger finisher — prefer it as the post step
(exact-palette + drift correction). Pairs with `asset-reuse` (palette_swap on
SNAPPED art stays perfectly clean) and `animation-pipeline`.
