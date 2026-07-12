#!/usr/bin/env python3
"""pixeltool — unified pixel-art cleanup CLI (NoxDev Pixel Studio P0).

One front-end over four cleanup backends, dispatched per job:

  snap     tools/pixel_snap.py (ours)  — elastic-walker grid snap + palette lock.
           DEFAULT for AI "pixel art" with a drifting but roughly uniform grid.
  unfake   `unfake` (PyPI, Rust-accelerated) — runs/edge scale detection,
           dominant/median downscale, QVote (quantize-then-vote), morphological
           cleanup, alpha binarize, flood background key.
  hough    `proper-pixel-art` (PyPI) — Canny+Hough mesh; handles NON-uniform /
           warped grids that defeat uniform-step walkers.
  pixeloe  `pixeloe` (PyPI) — contrast-aware outline expansion; converts
           NON-pixel sources (photos, renders) into pixel art. Never use it on
           something that already has a grid.

Auto-dispatch (override with --backend):
  --detect hough                          -> hough
  --downscale qvote | --morph
    | --alpha-binarize | --chroma flood   -> unfake
  everything else                         -> snap
  pixeloe is NEVER auto-chosen: pass --backend pixeloe for photo->pixel.

Flags a chosen backend lacks are implemented locally in this file (dither,
global/flood chroma key, morphological majority cleanup, alpha binarize,
exact-palette lock) and applied as post-ops at TRUE resolution — no request
is silently dropped.

Usage:
  pixeltool.py clean in.png out.png [--pixel-size auto|N] [--detect auto|runs|edge|hough]
      [--downscale dominant|median|qvote] [--palette "#hex,..."|--colors N]
      [--dither none|ordered|fs] [--morph] [--alpha-binarize]
      [--chroma global|flood] [--chroma-color "#FF00FF"] [--chroma-tol 40]
      [--backend auto|snap|unfake|hough|pixeloe] [--scale N] [--json]

Output = true-resolution PNG (1 image pixel per art pixel). --scale N writes an
extra <out>_preview.png at Nx nearest-neighbor. Engines import with Nearest.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

# 4x4 Bayer threshold matrix, normalized to [0, 1).
_BAYER4 = (
    np.array(
        [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]],
        dtype=np.float32,
    )
    / 16.0
)


# --------------------------------------------------------------------------
# shared helpers
# --------------------------------------------------------------------------
def parse_palette(spec: str) -> np.ndarray:
    """'#rrggbb,#rrggbb,...' -> (N,3) uint8."""
    cols = []
    for tok in spec.split(","):
        tok = tok.strip().lstrip("#")
        if len(tok) != 6:
            sys.exit(f"pixeltool: bad palette color: #{tok}")
        cols.append([int(tok[i : i + 2], 16) for i in (0, 2, 4)])
    return np.asarray(cols, dtype=np.uint8)


def parse_hex_color(spec: str) -> np.ndarray:
    tok = spec.strip().lstrip("#")
    if len(tok) != 6:
        sys.exit(f"pixeltool: bad color: #{spec}")
    return np.array([int(tok[i : i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


def derive_palette(arr: np.ndarray, n_colors: int) -> np.ndarray:
    """Adaptive palette from the opaque pixels of an RGBA array -> (<=N,3) uint8."""
    rgb = Image.fromarray(arr[..., :3], "RGB")
    try:
        q = rgb.quantize(colors=n_colors, method=Image.Quantize.MAXCOVERAGE, kmeans=n_colors)
    except ValueError:  # MAXCOVERAGE rejects some inputs; MEDIANCUT always works
        q = rgb.quantize(colors=n_colors, method=Image.Quantize.MEDIANCUT, kmeans=n_colors)
    pal = np.asarray(q.getpalette(), dtype=np.uint8).reshape(-1, 3)
    used = sorted(set(np.asarray(q).flatten().tolist()))
    return pal[used]


def _nearest_map(rgb: np.ndarray, palette: np.ndarray) -> np.ndarray:
    """(M,3) float pixels -> (M,3) uint8 nearest palette colors (squared L2)."""
    pf = palette.astype(np.float32)
    d = ((rgb[:, None, :] - pf[None, :, :]) ** 2).sum(axis=2)
    return palette[d.argmin(axis=1)]


def apply_palette(arr: np.ndarray, palette: np.ndarray, dither: str) -> np.ndarray:
    """Lock RGBA array to an exact palette, optionally dithered. Alpha preserved."""
    out = arr.copy()
    opaque = out[..., 3] > 0
    if not opaque.any():
        return out
    h, w = out.shape[:2]

    if dither == "fs":
        # Floyd–Steinberg via PIL's error-diffusion against a fixed palette.
        flat = palette.astype(np.uint8).flatten().tolist()
        flat = flat + flat[-3:] * (256 - len(palette))  # pad P-mode palette
        pal_img = Image.new("P", (1, 1))
        pal_img.putpalette(flat)
        rgb = Image.fromarray(out[..., :3], "RGB")
        q = rgb.quantize(palette=pal_img, dither=Image.Dither.FLOYDSTEINBERG)
        mapped = np.asarray(q.convert("RGB"), dtype=np.uint8)
        out[..., :3] = np.where(opaque[..., None], mapped, out[..., :3])
        return out

    rgbf = out[..., :3].astype(np.float32)
    if dither == "ordered":
        # Spread = mean nearest-neighbor distance inside the palette (how far
        # apart quantization levels are), so dithering strength adapts to the
        # palette instead of using a magic constant.
        pf = palette.astype(np.float32)
        if len(pf) > 1:
            dmat = np.sqrt(((pf[:, None, :] - pf[None, :, :]) ** 2).sum(axis=2))
            np.fill_diagonal(dmat, np.inf)
            spread = float(dmat.min(axis=1).mean())
        else:
            spread = 0.0
        ty = np.tile(_BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
        rgbf = np.clip(rgbf + ((ty - 0.5) * spread)[..., None], 0, 255)

    mapped = _nearest_map(rgbf.reshape(-1, 3), palette).reshape(h, w, 3)
    out[..., :3] = np.where(opaque[..., None], mapped, out[..., :3])
    return out


def _pack_rgba(arr: np.ndarray) -> np.ndarray:
    a = arr.astype(np.uint32)
    return (a[..., 0] << 24) | (a[..., 1] << 16) | (a[..., 2] << 8) | a[..., 3]


def morph_cleanup(arr: np.ndarray) -> np.ndarray:
    """Majority despeckle at true resolution: a pixel whose 8-neighborhood has
    >=6 agreeing on one exact RGBA value gets replaced by it (kills orphan
    pixels / fills 1px holes without eroding edges)."""
    h, w = arr.shape[:2]
    if h < 3 or w < 3:
        return arr
    packed = _pack_rgba(arr)
    pad = np.pad(packed, 1, mode="edge")
    shifts = [
        pad[0:h, 0:w], pad[0:h, 1 : w + 1], pad[0:h, 2 : w + 2],
        pad[1 : h + 1, 0:w], pad[1 : h + 1, 2 : w + 2],
        pad[2 : h + 2, 0:w], pad[2 : h + 2, 1 : w + 1], pad[2 : h + 2, 2 : w + 2],
    ]
    stack = np.stack(shifts)  # (8, h, w)
    counts = np.zeros((8, h, w), dtype=np.int8)
    for i in range(8):
        counts[i] = (stack == stack[i]).sum(axis=0)
    best = counts.argmax(axis=0)
    yy, xx = np.mgrid[0:h, 0:w]
    mode_val = stack[best, yy, xx]
    mode_cnt = counts[best, yy, xx]
    replace = (mode_cnt >= 6) & (mode_val != packed)
    out = arr.copy()
    rv = mode_val[replace]
    out[replace, 0] = (rv >> 24) & 0xFF
    out[replace, 1] = (rv >> 16) & 0xFF
    out[replace, 2] = (rv >> 8) & 0xFF
    out[replace, 3] = rv & 0xFF
    return out


def binarize_alpha(arr: np.ndarray, threshold: int = 128) -> np.ndarray:
    out = arr.copy()
    out[..., 3] = np.where(out[..., 3] >= threshold, 255, 0)
    out[out[..., 3] == 0, :3] = 0
    return out


def chroma_key_global(arr: np.ndarray, key: np.ndarray, tol: float) -> np.ndarray:
    """Zero alpha on EVERY pixel within tol (L2 in RGB) of the key color."""
    out = arr.copy()
    dist = np.sqrt(((out[..., :3].astype(np.float32) - key) ** 2).sum(axis=2))
    hit = dist <= tol
    out[hit, 3] = 0
    out[hit, :3] = 0
    return out


def chroma_key_flood(arr: np.ndarray, key: np.ndarray, tol: float) -> np.ndarray:
    """Flood-fill key from the image border: only key-colored regions CONNECTED
    to the border go transparent (protects key-colored pixels inside the art)."""
    out = arr.copy()
    dist = np.sqrt(((out[..., :3].astype(np.float32) - key) ** 2).sum(axis=2))
    mask = dist <= tol
    reach = np.zeros_like(mask)
    reach[0, :], reach[-1, :], reach[:, 0], reach[:, -1] = (
        mask[0, :], mask[-1, :], mask[:, 0], mask[:, -1],
    )
    while True:  # iterative 4-neighbor dilation constrained to the mask
        grown = reach.copy()
        grown[1:, :] |= reach[:-1, :]
        grown[:-1, :] |= reach[1:, :]
        grown[:, 1:] |= reach[:, :-1]
        grown[:, :-1] |= reach[:, 1:]
        grown &= mask
        if (grown == reach).all():
            break
        reach = grown
    out[reach, 3] = 0
    out[reach, :3] = 0
    return out


# --------------------------------------------------------------------------
# backends
# --------------------------------------------------------------------------
def run_snap(rgba: np.ndarray, colors: int, palette: np.ndarray | None,
             pixel_size: float | None, quantize_requested: bool = True) -> tuple[np.ndarray, dict]:
    """Our pixel_snap pipeline (elastic-walker grid snap), called in-process."""
    import pixel_snap as ps

    h, w = rgba.shape[:2]
    pal = palette.astype(np.float32) if palette is not None else None

    if pixel_size == 1:
        # Already true resolution (e.g. post area-downscale): grid detection is
        # a no-op and the walker would merge weak-gradient cells — skip it.
        # snap at 1px = palette lock only.
        q = ps.quantize(rgba, colors, pal) if (pal is not None or quantize_requested) else rgba
        return q.copy(), {"detected_pixel_size": 1.0}

    q = ps.quantize(rgba, colors, pal)
    col_p, row_p = ps.profiles(q)
    sx, sy = ps.estimate_step(col_p), ps.estimate_step(row_p)
    step_x, step_y = ps.resolve_steps(sx, sy, w, h, pixel_size)
    col_cuts = ps.walk(col_p, step_x, w)
    row_cuts = ps.walk(row_p, step_y, h)
    col_cuts2 = ps.stabilize(col_p, col_cuts, w, row_cuts, h)
    row_cuts2 = ps.stabilize(row_p, row_cuts, h, col_cuts, w)
    ccells, rcells = max(len(col_cuts2) - 1, 1), max(len(row_cuts2) - 1, 1)
    cstep, rstep = w / ccells, h / rcells
    if max(cstep, rstep) / min(cstep, rstep) > ps.MAX_STEP_RATIO:
        target = min(cstep, rstep)
        if cstep > target * 1.2:
            col_cuts2 = ps.snap_uniform(col_p, w, target, ps.MIN_CUTS_PER_AXIS)
        if rstep > target * 1.2:
            row_cuts2 = ps.snap_uniform(row_p, h, target, ps.MIN_CUTS_PER_AXIS)
    out = ps.resample(q, col_cuts2, row_cuts2)
    return out, {"detected_pixel_size": round(step_x, 2)}


def run_unfake(in_path: str, args, palette: np.ndarray | None) -> tuple[np.ndarray, dict]:
    import unfake

    detect = args.detect if args.detect in ("runs", "edge") else "auto"
    downscale = {"dominant": "dominant", "median": "median", "qvote": "dominant"}[args.downscale]
    fixed = (["#%02x%02x%02x" % tuple(c) for c in palette] if palette is not None else None)
    max_colors = len(palette) if palette is not None else (args.colors or None)
    if args.downscale == "qvote" and max_colors is None:
        max_colors = 32  # QVote = quantize-then-vote; needs a quantize step
    manual = int(args.pixel_size) if args.pixel_size else None
    result = unfake.process_image_sync(
        in_path,
        max_colors=max_colors,
        manual_scale=manual,
        detect_method=detect,
        downscale_method=downscale,
        cleanup={"morph": args.morph, "jaggy": args.morph},
        fixed_palette=fixed,
        alpha_threshold=128,
        transparent_background=(args.chroma == "flood"),
        background_mode="corners",
        background_tolerance=max(1, int(args.chroma_tol // 8)),
    )
    arr = np.asarray(result["image"].convert("RGBA"), dtype=np.uint8).copy()
    steps = result["manifest"].processing_steps
    return arr, {
        "detected_pixel_size": steps["scale_detection"]["detected_scale"],
        "unfake_rust": bool(unfake.RUST_AVAILABLE),
    }


def run_hough(img: Image.Image, args, palette: np.ndarray | None) -> tuple[np.ndarray, dict]:
    from proper_pixel_art.pixelate import pixelate as ppa_pixelate

    if palette is not None:
        n_colors = len(palette)
    else:
        n_colors = args.colors or 0  # 0 = keep all colors
    out_img = ppa_pixelate(
        img.convert("RGBA"),
        num_colors=n_colors,
        pixel_width=int(args.pixel_size) if args.pixel_size else 0,
        scale_result=1,
        transparent_background=False,
    )
    arr = np.asarray(out_img.convert("RGBA"), dtype=np.uint8).copy()
    return arr, {"detected_pixel_size": round(img.width / max(arr.shape[1], 1), 2)}


def run_pixeloe(img: Image.Image, args, palette: np.ndarray | None) -> tuple[np.ndarray, dict]:
    import cv2
    from pixeloe.legacy.pixelize import pixelize

    rgb = np.asarray(img.convert("RGB"), dtype=np.uint8)
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    w, h = img.size
    if args.pixel_size:
        n = int(args.pixel_size)
        target = max(16, round(max(w, h) / n))
        patch = max(4, min(32, n))
    else:
        target, patch = 128, 16
    n_colors = len(palette) if palette is not None else (args.colors or None)
    small = pixelize(
        bgr,
        mode="contrast",
        target_size=target,
        patch_size=patch,
        thickness=2,
        colors=n_colors,
        no_upscale=True,
    )
    out_rgb = cv2.cvtColor(small, cv2.COLOR_BGR2RGB)
    arr = np.dstack([out_rgb, np.full(out_rgb.shape[:2], 255, dtype=np.uint8)])
    return arr, {"pixeloe_target": target, "pixeloe_patch": patch}


# --------------------------------------------------------------------------
# dispatch + main
# --------------------------------------------------------------------------
def choose_backend(args) -> str:
    if args.backend != "auto":
        return args.backend
    if args.detect == "hough":
        return "hough"
    if args.downscale == "qvote" or args.morph or args.alpha_binarize or args.chroma == "flood":
        return "unfake"
    return "snap"


def main() -> None:
    ap = argparse.ArgumentParser(
        prog="pixeltool", description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = ap.add_subparsers(dest="cmd", required=True)
    cl = sub.add_parser("clean", help="snap/clean an image to true-resolution pixel art")
    cl.add_argument("input")
    cl.add_argument("output")
    cl.add_argument("--pixel-size", default="auto",
                    help="source pixels per art pixel: auto | N (default auto)")
    cl.add_argument("--detect", choices=["auto", "runs", "edge", "hough"], default="auto",
                    help="grid detection: runs/edge (unfake), hough (proper-pixel-art mesh)")
    cl.add_argument("--downscale", choices=["dominant", "median", "qvote"], default="dominant",
                    help="cell vote: dominant | median | qvote (quantize-then-vote, unfake)")
    cl.add_argument("--palette", help="lock to exact palette: comma-separated #hex list")
    cl.add_argument("--colors", type=int, default=0, help="adaptive palette size (ignored with --palette)")
    cl.add_argument("--dither", choices=["none", "ordered", "fs"], default="none",
                    help="dither during palette lock (ordered=Bayer4x4, fs=Floyd-Steinberg)")
    cl.add_argument("--morph", action="store_true", help="morphological cleanup (despeckle/de-jaggy)")
    cl.add_argument("--alpha-binarize", action="store_true", help="force alpha to 0/255")
    cl.add_argument("--chroma", choices=["global", "flood"],
                    help="key out chroma background: global (whole image) | flood (border-connected only)")
    cl.add_argument("--chroma-color", default="#FF00FF", help="chroma key color (default #FF00FF)")
    cl.add_argument("--chroma-tol", type=float, default=40.0, help="chroma key RGB distance tolerance")
    cl.add_argument("--backend", choices=["auto", "snap", "unfake", "hough", "pixeloe"], default="auto",
                    help="force a backend; pixeloe = photo/render -> pixel conversion")
    cl.add_argument("--scale", type=int, default=0, help="also write <output>_preview.png at Nx nearest")
    cl.add_argument("--json", action="store_true", help="print JSON result")
    args = ap.parse_args()

    if args.pixel_size == "auto":
        args.pixel_size = None
    else:
        try:
            args.pixel_size = float(args.pixel_size)
        except ValueError:
            sys.exit("pixeltool: --pixel-size must be 'auto' or a number")

    palette = parse_palette(args.palette) if args.palette else None
    backend = choose_backend(args)
    img = Image.open(args.input).convert("RGBA")
    rgba = np.asarray(img, dtype=np.uint8).copy()

    if backend == "snap":
        arr, meta = run_snap(rgba, args.colors or 16, palette, args.pixel_size,
                             quantize_requested=args.colors > 0)
    elif backend == "unfake":
        arr, meta = run_unfake(args.input, args, palette)
    elif backend == "hough":
        arr, meta = run_hough(img, args, palette)
    else:
        arr, meta = run_pixeloe(img, args, palette)

    # ---- local post-ops for whatever the backend didn't cover ----
    ops = []
    # exact palette / adaptive palette + dither, at TRUE resolution
    want_palette = palette is not None or args.colors > 0
    backend_locked = (
        (backend == "snap" and args.dither == "none")
        or (backend == "unfake" and args.dither == "none")
    )
    if want_palette and not backend_locked:
        pal = palette if palette is not None else derive_palette(arr, args.colors)
        arr = apply_palette(arr, pal, args.dither)
        ops.append(f"palette({len(pal)},{args.dither})")
    if args.morph and backend != "unfake":
        arr = morph_cleanup(arr)
        ops.append("morph")
    if args.chroma:
        key = parse_hex_color(args.chroma_color)
        if args.chroma == "global":
            arr = chroma_key_global(arr, key, args.chroma_tol)
            ops.append("chroma_global")
        elif backend != "unfake":  # unfake already flood-keyed natively
            arr = chroma_key_flood(arr, key, args.chroma_tol)
            ops.append("chroma_flood")
    if args.alpha_binarize and backend != "unfake":
        arr = binarize_alpha(arr)
        ops.append("alpha_binarize")

    Image.fromarray(arr).save(args.output)
    result = {
        "backend": backend,
        "input": args.input,
        "output": args.output,
        "input_size": [img.width, img.height],
        "output_size": [arr.shape[1], arr.shape[0]],
        "palette_locked": palette is not None,
        "local_post_ops": ops,
        **meta,
    }
    if args.scale and args.scale > 1:
        prev = Image.fromarray(arr).resize(
            (arr.shape[1] * args.scale, arr.shape[0] * args.scale), Image.NEAREST
        )
        pv_path = args.output.rsplit(".", 1)[0] + "_preview.png"
        prev.save(pv_path)
        result["preview"] = pv_path
    if args.json:
        print(json.dumps(result))
    else:
        print(
            f"[{backend}] {img.width}x{img.height} -> "
            f"{arr.shape[1]}x{arr.shape[0]}  {args.output}"
            + (f"  (+{','.join(ops)})" if ops else "")
        )


if __name__ == "__main__":
    main()
