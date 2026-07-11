"""Pixel Snap — fix the AI pixel-art noise pattern: snap to a true grid + strict palette.

Python port (numpy) of spritefusion-pixel-snapper (MIT, (c) 2025 Hugo Duprez,
github.com/Hugo-Dz/spritefusion-pixel-snapper) with NoxDev enhancements:
  - --palette "#hex,#hex,..." locks colors to an exact palette (VisualIdentity
    palette-lock) instead of k-means auto-quantization
  - --scale N writes an additional nearest-neighbor preview at N x
  - --json prints machine-readable results (detected pixel size, output dims)

Algorithm: quantize colors -> per-axis luminance-gradient profiles -> peak-median
pixel-size estimate -> elastic walker snaps grid cuts to local gradient maxima
(handles drifting/inconsistent AI grids) -> cross-axis stabilization ->
majority-vote resample to 1px-per-cell.

Usage:
  python pixel_snap.py in.png out.png [--colors 16] [--pixel-size 8]
                       [--palette "#0f380f,#306230,#8bac0f,#9bbc0f"]
                       [--scale 4] [--json]
"""
import argparse
import json
import sys

import numpy as np
from PIL import Image

# ---- tunables (mirror upstream defaults) ----
MAX_KMEANS_ITERATIONS = 15
PEAK_THRESHOLD_MULTIPLIER = 0.2
PEAK_DISTANCE_FILTER = 4
WALKER_SEARCH_WINDOW_RATIO = 0.35
WALKER_MIN_SEARCH_WINDOW = 2.0
WALKER_STRENGTH_THRESHOLD = 0.5
MIN_CUTS_PER_AXIS = 4
FALLBACK_TARGET_SEGMENTS = 64
MAX_STEP_RATIO = 1.8
K_SEED = 42


def parse_palette(spec: str) -> np.ndarray:
    cols = []
    for tok in spec.split(","):
        tok = tok.strip().lstrip("#")
        if len(tok) != 6:
            sys.exit(f"bad palette color: #{tok}")
        cols.append([int(tok[i : i + 2], 16) for i in (0, 2, 4)])
    return np.asarray(cols, dtype=np.float32)


def quantize(rgba: np.ndarray, k_colors: int, palette: np.ndarray | None) -> np.ndarray:
    """Map opaque pixels to nearest of k centroids (k-means++) or a fixed palette."""
    h, w, _ = rgba.shape
    flat = rgba.reshape(-1, 4).astype(np.float32)
    opaque = flat[:, 3] > 0
    pts = flat[opaque][:, :3]
    if pts.size == 0:
        return rgba

    if palette is not None:
        centroids = palette
    else:
        rng = np.random.default_rng(K_SEED)
        k = min(k_colors, len(pts))
        # k-means++ init
        centroids = [pts[rng.integers(len(pts))]]
        d2 = np.full(len(pts), np.inf, dtype=np.float32)
        for _ in range(1, k):
            d2 = np.minimum(d2, ((pts - centroids[-1]) ** 2).sum(axis=1))
            total = float(d2.sum())
            if total <= 0:
                centroids.append(pts[rng.integers(len(pts))])
            else:
                centroids.append(pts[rng.choice(len(pts), p=d2 / total)])
        centroids = np.asarray(centroids, dtype=np.float32)
        # Lloyd iterations
        prev = centroids.copy()
        for it in range(MAX_KMEANS_ITERATIONS):
            # nearest centroid per point, chunked to bound memory
            labels = np.empty(len(pts), dtype=np.int32)
            for s in range(0, len(pts), 262144):
                chunk = pts[s : s + 262144]
                dists = ((chunk[:, None, :] - centroids[None, :, :]) ** 2).sum(axis=2)
                labels[s : s + 262144] = dists.argmin(axis=1)
            for i in range(len(centroids)):
                sel = pts[labels == i]
                if len(sel):
                    centroids[i] = sel.mean(axis=0)
            if it > 0 and float(((centroids - prev) ** 2).sum(axis=1).max()) < 0.01:
                break
            prev = centroids.copy()

    # remap all opaque pixels to nearest centroid
    out = flat.copy()
    idx_opaque = np.where(opaque)[0]
    for s in range(0, len(idx_opaque), 262144):
        sel = idx_opaque[s : s + 262144]
        chunk = flat[sel][:, :3]
        dists = ((chunk[:, None, :] - centroids[None, :, :]) ** 2).sum(axis=2)
        out[sel, :3] = centroids[dists.argmin(axis=1)]
    return np.clip(np.rint(out), 0, 255).astype(np.uint8).reshape(h, w, 4)


def profiles(rgba: np.ndarray) -> tuple:
    a = rgba.astype(np.float64)
    luma = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    luma[a[..., 3] == 0] = 0.0
    gx = np.abs(luma[:, 2:] - luma[:, :-2])  # [-1,0,1] kernel
    gy = np.abs(luma[2:, :] - luma[:-2, :])
    col = np.zeros(rgba.shape[1])
    col[1:-1] = gx.sum(axis=0)
    row = np.zeros(rgba.shape[0])
    row[1:-1] = gy.sum(axis=1)
    return col, row


def estimate_step(profile: np.ndarray) -> float | None:
    if profile.size == 0 or profile.max() == 0:
        return None
    thr = profile.max() * PEAK_THRESHOLD_MULTIPLIER
    p = profile
    peaks = [
        i
        for i in range(1, len(p) - 1)
        if p[i] > thr and p[i] > p[i - 1] and p[i] > p[i + 1]
    ]
    if len(peaks) < 2:
        return None
    clean = [peaks[0]]
    for pk in peaks[1:]:
        if pk - clean[-1] > (PEAK_DISTANCE_FILTER - 1):
            clean.append(pk)
    if len(clean) < 2:
        return None
    diffs = sorted(float(b - a) for a, b in zip(clean, clean[1:]))
    median = diffs[len(diffs) // 2]
    # NoxDev improvement over upstream: peaks only occur at color CHANGES, so on
    # flat art consecutive peaks are often 2-3 cells apart and the median
    # overestimates the cell size. Treat the true cell size as the fundamental
    # step: test candidates median/k and pick the smallest one that most diffs
    # are near-integer multiples of.
    best = median
    best_score = -1.0
    for k in (1, 2, 3, 4):
        cand = median / k
        if cand < 2.0:  # cells below 2px are indistinguishable from noise
            break
        score = 0.0
        for d in diffs:
            m = d / cand
            err = abs(m - round(m))
            if err < 0.2 and round(m) >= 1:
                score += 1.0
        score /= len(diffs)
        # prefer smaller cand only when it explains diffs at least as well
        if score >= best_score + (0.0 if cand < best else 0.05):
            best_score = score
            best = cand
    return best


def resolve_steps(sx, sy, w, h, override) -> tuple:
    if override:
        return override, override
    if sx and sy:
        ratio = max(sx, sy) / min(sx, sy)
        if ratio > MAX_STEP_RATIO:
            m = min(sx, sy)
            return m, m
        avg = (sx + sy) / 2.0
        return avg, avg
    if sx:
        return sx, sx
    if sy:
        return sy, sy
    fb = max(min(w, h) / FALLBACK_TARGET_SEGMENTS, 1.0)
    return fb, fb


def walk(profile: np.ndarray, step: float, limit: int) -> list:
    cuts = [0]
    pos = 0.0
    window = max(step * WALKER_SEARCH_WINDOW_RATIO, WALKER_MIN_SEARCH_WINDOW)
    mean_val = float(profile.mean()) if profile.size else 0.0
    while pos < limit:
        target = pos + step
        if target >= limit:
            cuts.append(limit)
            break
        start = max(int(target - window), int(pos + 1.0))
        end = min(int(target + window), limit)
        if end <= start:
            pos = target
            continue
        seg = profile[start:end]
        mi = int(seg.argmax())
        if float(seg[mi]) > mean_val * WALKER_STRENGTH_THRESHOLD:
            cuts.append(start + mi)
            pos = float(start + mi)
        else:
            cuts.append(int(target))
            pos = target
    return cuts


def sanitize(cuts: list, limit: int) -> list:
    s = set(min(c, limit) for c in cuts)
    s.add(0)
    s.add(limit)
    return sorted(s)


def snap_uniform(profile: np.ndarray, limit: int, target_step: float, min_required: int) -> list:
    if limit == 0:
        return [0]
    if limit == 1:
        return [0, 1]
    cells = int(round(limit / target_step)) if target_step > 0 else 0
    cells = min(max(cells, max(min_required - 1, 1)), limit)
    cw = limit / cells
    window = max(cw * WALKER_SEARCH_WINDOW_RATIO, WALKER_MIN_SEARCH_WINDOW)
    mean_val = float(profile.mean()) if profile.size else 0.0
    cuts = [0]
    for i in range(1, cells):
        target = cw * i
        prev = cuts[-1]
        if prev + 1 >= limit:
            break
        start = max(int(np.floor(target - window)), prev + 1, 0)
        end = min(int(np.ceil(target + window)), limit - 1)
        if end < start:
            start = end = prev + 1
        hi = min(end, len(profile) - 1)
        seg = profile[start : hi + 1]
        if seg.size:
            best = start + int(seg.argmax())
            best_val = float(seg.max())
        else:
            best, best_val = start, -1.0
        if best_val < mean_val * WALKER_STRENGTH_THRESHOLD:
            fb = int(round(target))
            fb = max(fb, prev + 1)
            fb = min(fb, limit - 1)
            best = fb
        cuts.append(best)
    return sanitize(cuts, limit)


def stabilize(profile, cuts, limit, sib_cuts, sib_limit):
    cuts = sanitize(cuts, limit)
    min_req = max(MIN_CUTS_PER_AXIS, 2)
    cells = max(len(cuts) - 1, 0)
    sib_cells = max(len(sib_cuts) - 1, 0)
    sib_grid = sib_limit > 0 and sib_cells >= min_req - 1 and sib_cells > 0
    skewed = False
    if sib_grid and cells > 0:
        r = (limit / cells) / (sib_limit / sib_cells)
        skewed = r > MAX_STEP_RATIO or r < 1.0 / MAX_STEP_RATIO
    if len(cuts) >= min_req and not skewed:
        return cuts
    if sib_grid:
        target = sib_limit / sib_cells
    elif cells > 0:
        target = limit / cells
    else:
        target = limit / FALLBACK_TARGET_SEGMENTS
    return snap_uniform(profile, limit, max(target, 1.0), min_req)


def resample(rgba: np.ndarray, cols: list, rows: list) -> np.ndarray:
    out = np.zeros((len(rows) - 1, len(cols) - 1, 4), dtype=np.uint8)
    for yi in range(len(rows) - 1):
        ys, ye = rows[yi], rows[yi + 1]
        for xi in range(len(cols) - 1):
            xs, xe = cols[xi], cols[xi + 1]
            if xe <= xs or ye <= ys:
                continue
            cell = rgba[ys:ye, xs:xe].reshape(-1, 4)
            # majority vote over exact RGBA values (deterministic tie-break)
            vals, counts = np.unique(cell, axis=0, return_counts=True)
            order = np.lexsort((vals[:, 3], vals[:, 2], vals[:, 1], vals[:, 0]))
            vals, counts = vals[order], counts[order]
            out[yi, xi] = vals[counts.argmax()]
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--colors", type=int, default=16, help="k-means palette size (ignored with --palette)")
    ap.add_argument("--pixel-size", type=float, default=None, help="override detected source pixel size")
    ap.add_argument("--palette", help="lock to exact palette: comma-separated #hex list")
    ap.add_argument("--scale", type=int, default=0, help="also write <output>_preview.png at N x nearest")
    ap.add_argument("--json", action="store_true", help="print JSON result")
    args = ap.parse_args()

    img = Image.open(args.input).convert("RGBA")
    rgba = np.asarray(img).copy()
    h, w = rgba.shape[:2]
    if w < 3 or h < 3 or w > 10000 or h > 10000:
        sys.exit("image dimensions out of range (3..10000)")

    palette = parse_palette(args.palette) if args.palette else None
    q = quantize(rgba, args.colors, palette)
    col_p, row_p = profiles(q)
    sx = estimate_step(col_p)
    sy = estimate_step(row_p)
    step_x, step_y = resolve_steps(sx, sy, w, h, args.pixel_size)
    col_cuts = walk(col_p, step_x, w)
    row_cuts = walk(row_p, step_y, h)
    col_cuts2 = stabilize(col_p, col_cuts, w, row_cuts, h)
    row_cuts2 = stabilize(row_p, row_cuts, h, col_cuts, w)
    # cross-axis coherence pass (mirror upstream stabilize_both_axes)
    ccells, rcells = max(len(col_cuts2) - 1, 1), max(len(row_cuts2) - 1, 1)
    cstep, rstep = w / ccells, h / rcells
    if max(cstep, rstep) / min(cstep, rstep) > MAX_STEP_RATIO:
        target = min(cstep, rstep)
        if cstep > target * 1.2:
            col_cuts2 = snap_uniform(col_p, w, target, MIN_CUTS_PER_AXIS)
        if rstep > target * 1.2:
            row_cuts2 = snap_uniform(row_p, h, target, MIN_CUTS_PER_AXIS)

    out = resample(q, col_cuts2, row_cuts2)
    Image.fromarray(out).save(args.output)

    result = {
        "detected_pixel_size": round(step_x, 2),
        "override": args.pixel_size is not None,
        "output_width": out.shape[1],
        "output_height": out.shape[0],
        "palette_locked": palette is not None,
        "output": args.output,
    }
    if args.scale and args.scale > 1:
        prev = Image.fromarray(out).resize(
            (out.shape[1] * args.scale, out.shape[0] * args.scale), Image.NEAREST
        )
        pv_path = args.output.rsplit(".", 1)[0] + "_preview.png"
        prev.save(pv_path)
        result["preview"] = pv_path
    if args.json:
        print(json.dumps(result))
    else:
        print(
            f"pixel size {result['detected_pixel_size']}px "
            f"({'override' if result['override'] else 'auto'}) -> "
            f"{result['output_width']}x{result['output_height']}  {args.output}"
        )


if __name__ == "__main__":
    main()
