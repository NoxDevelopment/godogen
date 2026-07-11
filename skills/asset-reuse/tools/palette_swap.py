"""Deterministic palette recoloring for sprites/tiles. Alpha preserved.

Modes:
  hue   --shift <degrees>            rotate hue of all non-transparent pixels
  map   --from "#a,#b" --to "#x,#y"  exact color remap (pixel-art palettes)
  ramp  --target "#hex"              remap the dominant hue ramp to a target hue,
                                     preserving per-pixel value/saturation

Usage:
  python palette_swap.py in.png out.png --mode hue --shift 120
  python palette_swap.py in.png out.png --mode map --from "#4a8f3c,#2d5c24" --to "#7ec8e3,#3a7ca5"
  python palette_swap.py in.png out.png --mode ramp --target "#c0392b"
"""
import argparse
import colorsys
import sys
from collections import Counter

from PIL import Image


def parse_hex(s: str) -> tuple:
    s = s.strip().lstrip("#")
    if len(s) != 6:
        raise ValueError(f"bad hex color: #{s}")
    return tuple(int(s[i : i + 2], 16) for i in (0, 2, 4))


def rotate_hue(img: Image.Image, degrees: float) -> Image.Image:
    px = img.load()
    w, h = img.size
    shift = (degrees % 360.0) / 360.0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, ll, ss = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            r2, g2, b2 = colorsys.hls_to_rgb((hh + shift) % 1.0, ll, ss)
            px[x, y] = (round(r2 * 255), round(g2 * 255), round(b2 * 255), a)
    return img


def map_colors(img: Image.Image, src: list, dst: list) -> Image.Image:
    if len(src) != len(dst):
        sys.exit("--from and --to must list the same number of colors")
    table = dict(zip(src, dst))
    px = img.load()
    w, h = img.size
    replaced = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hit = table.get((r, g, b))
            if hit is not None:
                px[x, y] = (*hit, a)
                replaced += 1
    print(f"remapped {replaced} pixels across {len(table)} palette entries")
    return img


def remap_ramp(img: Image.Image, target: tuple) -> Image.Image:
    """Find the dominant hue among opaque pixels, then shift every pixel whose
    hue is within ±60 degrees of it onto the target hue, preserving lightness
    and saturation (keeps shading ramps intact)."""
    px = img.load()
    w, h = img.size
    hues = Counter()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, ll, ss = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            if ss > 0.15 and 0.08 < ll < 0.92:  # ignore near-gray / near-b&w
                hues[round(hh * 72)] += 1  # 5-degree buckets
    if not hues:
        sys.exit("no saturated pixels found to build a ramp from")
    dominant = hues.most_common(1)[0][0] / 72.0
    t_h, _, _ = colorsys.rgb_to_hls(target[0] / 255, target[1] / 255, target[2] / 255)
    window = 60.0 / 360.0
    changed = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, ll, ss = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            d = min(abs(hh - dominant), 1 - abs(hh - dominant))
            if ss > 0.15 and d <= window:
                r2, g2, b2 = colorsys.hls_to_rgb(t_h, ll, ss)
                px[x, y] = (round(r2 * 255), round(g2 * 255), round(b2 * 255), a)
                changed += 1
    print(f"dominant hue {round(dominant * 360)}deg -> {round(t_h * 360)}deg; {changed} pixels")
    return img


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--mode", choices=["hue", "map", "ramp"], required=True)
    ap.add_argument("--shift", type=float, help="hue mode: degrees to rotate")
    ap.add_argument("--from", dest="src", help="map mode: comma-separated #hex list")
    ap.add_argument("--to", dest="dst", help="map mode: comma-separated #hex list")
    ap.add_argument("--target", help="ramp mode: #hex target hue")
    args = ap.parse_args()

    img = Image.open(args.input).convert("RGBA")
    if args.mode == "hue":
        if args.shift is None:
            sys.exit("--shift required for hue mode")
        img = rotate_hue(img, args.shift)
    elif args.mode == "map":
        if not args.src or not args.dst:
            sys.exit("--from and --to required for map mode")
        img = map_colors(
            img,
            [parse_hex(c) for c in args.src.split(",")],
            [parse_hex(c) for c in args.dst.split(",")],
        )
    else:
        if not args.target:
            sys.exit("--target required for ramp mode")
        img = remap_ramp(img, parse_hex(args.target))
    img.save(args.output)
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
