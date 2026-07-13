#!/usr/bin/env python3
"""scene-populate placement solver — LAYOUT.json (+ resolved assets, seed) -> placements.json.

This is the deterministic core of NL level population. It reads an authored
LAYOUT.json (named zones with per-zone placement slots) and emits a flat
placements.json that the scene emitter (emit_scene.py -> dress_template.gd)
turns into placed Godot nodes / MultiMesh instances.

Design invariants (do NOT weaken these):

  * DETERMINISTIC. Same LAYOUT.json + seed -> byte-identical placements.json,
    on any machine, regardless of PYTHONHASHSEED. All randomness flows from a
    sha256-derived integer seed (never Python's hash() of a str).
  * AUTHORED, NOT SPRAYED. Every instance lands *inside an authored zone*. There
    is no randi()-over-the-whole-map path. This is world-layout's cardinal rule
    ("author, don't randomize") enforced structurally in 3D/2D.
  * COLLISION-AWARE. Within a slot, blue-noise min_spacing (Bridson). Across
    slots/zones, a global spatial-hash occupancy grid keeps a tree from landing
    on the shrine and set-dressing off keep-out anchors (player spawn, doors).
  * PLANE-AGNOSTIC. The solver works in a 2D plane (a, b). At output it maps to
    3D (a -> x, ground_y -> y, b -> z) or 2D (a -> x, b -> y). One algorithm,
    both dimensions.

stdlib only (json, math, random, hashlib, argparse). numpy is NOT required.

Usage
-----
  python3 scatter.py --layout LAYOUT.json --seed 1337 --out placements.json
  python3 scatter.py --layout LAYOUT.json --resolved resolved.json --out placements.json
  python3 scatter.py --layout LAYOUT.json --density-scale 1.0 --out -    # stdout

resolved.json (optional) maps kit_tag -> concrete asset facts from kit_index.py:
  { "conifer_tree": { "asset": "res://assets/kits/kenney_nature/tree_pineTallA.glb",
                      "footprint": [1.2, 1.2], "multimesh_ok": false, "scale_base": 1.0 },
    "fern":         { "asset": "res://assets/kits/nas/fern_01.glb",
                      "footprint": [0.4, 0.4], "multimesh_ok": true } }
If a tag is unresolved, the solver still runs (asset = "unresolved:<tag>",
footprint from the slot or a default) so layout iteration never blocks on assets.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import sys
from typing import Any, Callable, Optional

SolverPoint = tuple[float, float]

# Density presets scale authored counts and spacing. "medium" == authored values.
DENSITY_SCALE = {
    "sparse": {"count": 0.55, "spacing": 1.45},
    "medium": {"count": 1.0, "spacing": 1.0},
    "dense": {"count": 1.7, "spacing": 0.72},
}

DEFAULT_FOOTPRINT = 0.5  # metres (radius) when nothing else is known


# ---------------------------------------------------------------------------
# Deterministic seeding
# ---------------------------------------------------------------------------

def derive_seed(base: int, *parts: Any) -> int:
    """Deterministic 64-bit int seed from a base seed + arbitrary string parts.

    Uses sha256 so it is stable across processes and immune to PYTHONHASHSEED
    (Python's str hashing is randomized by default — never seed an RNG from it).
    """
    key = str(base) + "\x1f" + "\x1f".join(str(p) for p in parts)
    digest = hashlib.sha256(key.encode("utf-8")).digest()
    return int.from_bytes(digest[:8], "big")


def rng_for(base: int, *parts: Any) -> random.Random:
    return random.Random(derive_seed(base, *parts))


# ---------------------------------------------------------------------------
# Geometry primitives (plane coords a, b)
# ---------------------------------------------------------------------------

def _dist(p: SolverPoint, q: SolverPoint) -> float:
    return math.hypot(p[0] - q[0], p[1] - q[1])


def _in_circle(p: SolverPoint, center: SolverPoint, radius: float) -> bool:
    return _dist(p, center) <= radius


def _in_annulus(p: SolverPoint, center: SolverPoint, inner: float, outer: float) -> bool:
    d = _dist(p, center)
    return inner <= d <= outer


def _in_rect(p: SolverPoint, bounds: list[float]) -> bool:
    x0, y0, x1, y1 = bounds
    return min(x0, x1) <= p[0] <= max(x0, x1) and min(y0, y1) <= p[1] <= max(y0, y1)


def _in_polygon(p: SolverPoint, poly: list[SolverPoint]) -> bool:
    """Ray-casting point-in-polygon (even-odd rule)."""
    x, y = p
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi):
            inside = not inside
        j = i
    return inside


def _polyline_length(pts: list[SolverPoint]) -> float:
    return sum(_dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def _point_at_arclen(pts: list[SolverPoint], s: float) -> tuple[SolverPoint, SolverPoint]:
    """Return (point, unit_tangent) at arc-length s along the polyline."""
    if len(pts) == 1:
        return pts[0], (1.0, 0.0)
    s = max(0.0, s)
    acc = 0.0
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        seg = _dist(a, b)
        if seg < 1e-9:
            continue
        if acc + seg >= s or i == len(pts) - 2:
            t = (s - acc) / seg
            t = max(0.0, min(1.0, t))
            px = a[0] + (b[0] - a[0]) * t
            py = a[1] + (b[1] - a[1]) * t
            tx, ty = (b[0] - a[0]) / seg, (b[1] - a[1]) / seg
            return (px, py), (tx, ty)
        acc += seg
    return pts[-1], (1.0, 0.0)


def _dist_to_polyline(p: SolverPoint, pts: list[SolverPoint]) -> float:
    if len(pts) == 1:
        return _dist(p, pts[0])
    best = float("inf")
    for i in range(len(pts) - 1):
        best = min(best, _dist_point_segment(p, pts[i], pts[i + 1]))
    return best


def _dist_point_segment(p: SolverPoint, a: SolverPoint, b: SolverPoint) -> float:
    ax, ay = a
    bx, by = b
    px, py = p
    dx, dy = bx - ax, by - ay
    seg2 = dx * dx + dy * dy
    if seg2 < 1e-12:
        return _dist(p, a)
    t = ((px - ax) * dx + (py - ay) * dy) / seg2
    t = max(0.0, min(1.0, t))
    cx, cy = ax + dx * t, ay + dy * t
    return math.hypot(px - cx, py - cy)


# ---------------------------------------------------------------------------
# Zone abstraction
# ---------------------------------------------------------------------------

class Zone:
    def __init__(self, spec: dict):
        self.spec = spec
        self.id = spec.get("id", "zone")
        self.shape = spec.get("shape", "rect")
        self.center: SolverPoint = tuple(spec.get("center", [0.0, 0.0]))  # type: ignore
        self.radius = float(spec.get("radius", 0.0))
        self.inner = float(spec.get("inner", 0.0))
        self.outer = float(spec.get("outer", self.radius))
        self.bounds = spec.get("bounds")
        if self.bounds is None and "size" in spec:
            w, h = spec["size"]
            cx, cy = self.center
            self.bounds = [cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2]
        self.points: list[SolverPoint] = [tuple(p) for p in spec.get("points", [])]  # type: ignore
        self.width = float(spec.get("width", 1.0))

    def centroid(self) -> SolverPoint:
        if self.shape in ("circle", "annulus"):
            return self.center
        if self.shape == "rect" and self.bounds:
            x0, y0, x1, y1 = self.bounds
            return ((x0 + x1) / 2, (y0 + y1) / 2)
        if self.shape == "polygon" and self.points:
            n = len(self.points)
            return (sum(p[0] for p in self.points) / n, sum(p[1] for p in self.points) / n)
        if self.shape == "spline" and self.points:
            pt, _ = _point_at_arclen(self.points, _polyline_length(self.points) / 2)
            return pt
        return self.center

    def contains(self, p: SolverPoint) -> bool:
        if self.shape == "circle":
            return _in_circle(p, self.center, self.radius)
        if self.shape == "annulus":
            return _in_annulus(p, self.center, self.inner, self.outer)
        if self.shape == "rect" and self.bounds:
            return _in_rect(p, self.bounds)
        if self.shape == "polygon" and len(self.points) >= 3:
            return _in_polygon(p, self.points)
        if self.shape == "spline" and self.points:
            return _dist_to_polyline(p, self.points) <= self.width / 2
        return False

    def bbox(self) -> tuple[float, float, float, float]:
        if self.shape == "circle":
            cx, cy = self.center
            return (cx - self.radius, cy - self.radius, cx + self.radius, cy + self.radius)
        if self.shape == "annulus":
            cx, cy = self.center
            return (cx - self.outer, cy - self.outer, cx + self.outer, cy + self.outer)
        if self.shape == "rect" and self.bounds:
            x0, y0, x1, y1 = self.bounds
            return (min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))
        if self.shape in ("polygon", "spline") and self.points:
            xs = [p[0] for p in self.points]
            ys = [p[1] for p in self.points]
            pad = self.width / 2 if self.shape == "spline" else 0.0
            return (min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad)
        return (0.0, 0.0, 0.0, 0.0)


# ---------------------------------------------------------------------------
# Keep-out mask
# ---------------------------------------------------------------------------

class KeepOut:
    def __init__(self, specs: list[dict]):
        self.zones = [Zone(s) for s in specs]

    def blocks(self, p: SolverPoint) -> bool:
        return any(z.contains(p) for z in self.zones)


# ---------------------------------------------------------------------------
# Global occupancy — spatial hash for cross-slot collision
# ---------------------------------------------------------------------------

class Occupancy:
    """Uniform-grid spatial hash of placed points with per-point radius.

    A candidate at radius r is free iff no stored point q (radius rq) has
    dist(candidate, q) < r + rq. Query cost is O(neighbours) not O(n).
    """

    def __init__(self, cell: float = 1.0):
        self.cell = max(cell, 1e-3)
        self.buckets: dict[tuple[int, int], list[tuple[float, float, float]]] = {}
        self.max_r = 0.0

    def _key(self, x: float, y: float) -> tuple[int, int]:
        return (int(math.floor(x / self.cell)), int(math.floor(y / self.cell)))

    def add(self, p: SolverPoint, r: float) -> None:
        self.buckets.setdefault(self._key(p[0], p[1]), []).append((p[0], p[1], r))
        self.max_r = max(self.max_r, r)

    def is_free(self, p: SolverPoint, r: float) -> bool:
        reach = r + self.max_r
        span = int(math.ceil(reach / self.cell)) + 1
        gx, gy = self._key(p[0], p[1])
        for dx in range(-span, span + 1):
            for dy in range(-span, span + 1):
                for (qx, qy, qr) in self.buckets.get((gx + dx, gy + dy), ()):
                    if math.hypot(p[0] - qx, p[1] - qy) < r + qr:
                        return False
        return True


# ---------------------------------------------------------------------------
# Bridson blue-noise (Poisson-disk) inside an arbitrary domain predicate
# ---------------------------------------------------------------------------

def bridson(
    rng: random.Random,
    bbox: tuple[float, float, float, float],
    r: float,
    domain_ok: Callable[[SolverPoint], bool],
    k: int = 30,
    cap: Optional[int] = None,
) -> list[SolverPoint]:
    """Bridson (2007) blue-noise sampling restricted to `domain_ok`.

    `r` is the minimum inter-point spacing (within this call). `domain_ok`
    encodes zone membership + bounds + keep-out + cross-slot occupancy.
    """
    xmin, ymin, xmax, ymax = bbox
    if xmax <= xmin or ymax <= ymin or r <= 0:
        return []
    cell = r / math.sqrt(2)
    gw = max(1, int(math.ceil((xmax - xmin) / cell)))
    gh = max(1, int(math.ceil((ymax - ymin) / cell)))
    grid: dict[tuple[int, int], int] = {}
    samples: list[SolverPoint] = []
    active: list[int] = []

    def gi(p: SolverPoint) -> tuple[int, int]:
        return (int((p[0] - xmin) / cell), int((p[1] - ymin) / cell))

    def local_ok(p: SolverPoint) -> bool:
        gx, gy = gi(p)
        for dx in range(-2, 3):
            for dy in range(-2, 3):
                idx = grid.get((gx + dx, gy + dy))
                if idx is not None and _dist(p, samples[idx]) < r:
                    return False
        return True

    # Deterministic seed point: scan a jittered lattice for the first valid cell.
    seed_pt: Optional[SolverPoint] = None
    steps = 24
    for i in range(steps):
        for j in range(steps):
            cx = xmin + (i + 0.5) / steps * (xmax - xmin)
            cy = ymin + (j + 0.5) / steps * (ymax - ymin)
            cand = (cx + rng.uniform(-cell, cell) * 0.25, cy + rng.uniform(-cell, cell) * 0.25)
            if domain_ok(cand):
                seed_pt = cand
                break
        if seed_pt is not None:
            break
    if seed_pt is None:
        return []

    samples.append(seed_pt)
    grid[gi(seed_pt)] = 0
    active.append(0)

    while active:
        # Deterministic pop: rng picks an index in the active list.
        ai = rng.randrange(len(active))
        pi = active[ai]
        origin = samples[pi]
        placed = False
        for _ in range(k):
            ang = rng.uniform(0, 2 * math.pi)
            rad = rng.uniform(r, 2 * r)
            cand = (origin[0] + math.cos(ang) * rad, origin[1] + math.sin(ang) * rad)
            if not (xmin <= cand[0] <= xmax and ymin <= cand[1] <= ymax):
                continue
            if not domain_ok(cand) or not local_ok(cand):
                continue
            idx = len(samples)
            samples.append(cand)
            grid[gi(cand)] = idx
            active.append(idx)
            placed = True
            if cap is not None and len(samples) >= cap * 3:
                # plenty of candidates to trim from; stop early for perf
                active = []
                break
            break
        if not placed:
            active.pop(ai)
    return samples


# ---------------------------------------------------------------------------
# Per-rule placement
# ---------------------------------------------------------------------------

def _default_footprint(rule: str, slot: dict) -> list[float]:
    """Footprint [w, d] (metres) when neither the resolved asset nor the slot
    declares one. Rule-aware so greybox/unresolved scenes still place sensibly:
    hero singles reserve real space; parametric decorations stay small; poisson
    props derive from their own min_spacing (within-slot Bridson already spaces
    them, so the cross-slot footprint just needs to be modest)."""
    if rule == "single":
        return [1.2, 1.2]
    if rule in ("scatter_along", "grid_along", "ring", "grid"):
        return [0.4, 0.4]
    if rule in ("poisson", "poisson_multimesh", "cluster"):
        s = float(slot.get("min_spacing", 1.0)) * 0.5
        return [max(0.3, s), max(0.3, s)]
    return [DEFAULT_FOOTPRINT * 2, DEFAULT_FOOTPRINT * 2]


def _scaled_count(base: int, density: dict) -> int:
    return max(0, int(round(base * density["count"])))


def _scaled_spacing(base: float, density: dict) -> float:
    return max(0.05, base * density["spacing"])


def solve_slot(
    zone: Zone,
    slot: dict,
    slot_index: int,
    seed: int,
    density: dict,
    keepout: KeepOut,
    occ: Occupancy,
    resolved: dict,
    ground_bounds: Optional[list[float]],
    warnings: list[str],
) -> list[dict]:
    """Return a list of instance dicts (plane coords) for one slot."""
    tag = slot.get("kit_tag", "prop")
    rule = slot.get("rule", "poisson")
    info = resolved.get(tag, {})
    fw, fh = (info.get("footprint") or slot.get("footprint")
              or _default_footprint(rule, slot))
    footprint_r = max(fw, fh) / 2.0
    rng = rng_for(seed, zone.id, slot_index, tag)

    # Dense multimesh ground-cover (grass, ferns) intermixes freely: it must
    # dodge SOLID props (trees, rocks, the shrine) and keep-out, but it does not
    # block other foliage or itself in the cross-slot occupancy grid. Everything
    # else is "solid" and reserves its footprint against later placements.
    is_foliage = rule == "poisson_multimesh" and bool(info.get("multimesh_ok", True))

    def in_bounds(p: SolverPoint) -> bool:
        if ground_bounds is None:
            return True
        return _in_rect(p, ground_bounds)

    def hard_ok(p: SolverPoint) -> bool:
        # Constraints that apply to EVERY rule (incl. single/ring/along/grid).
        return in_bounds(p) and not keepout.blocks(p) and occ.is_free(p, footprint_r)

    def domain_ok(p: SolverPoint) -> bool:
        return zone.contains(p) and hard_ok(p)

    raw: list[SolverPoint] = []

    if rule == "single":
        cx, cy = zone.centroid()
        at = slot.get("at")
        pt = (cx + at[0], cy + at[1]) if at else (cx, cy)
        raw = [pt]

    elif rule in ("poisson", "poisson_multimesh"):
        count = _scaled_count(int(slot.get("count", 1)), density)
        spacing = _scaled_spacing(float(slot.get("min_spacing", footprint_r * 2)), density)
        pts = bridson(rng, zone.bbox(), spacing, domain_ok, cap=count)
        rng.shuffle(pts)
        if len(pts) < count:
            warnings.append(
                f"zone '{zone.id}' slot '{tag}': requested {count}, blue-noise fit {len(pts)} "
                f"(spacing {spacing:.2f} too large for the zone area)"
            )
        raw = pts[:count]

    elif rule == "cluster":
        clusters = _scaled_count(int(slot.get("clusters", 4)), density)
        per_lo, per_hi = slot.get("per_cluster", [3, 7])
        cluster_spacing = float(slot.get("cluster_spacing", max(footprint_r * 6, 3.0)))
        member_spacing = _scaled_spacing(float(slot.get("min_spacing", footprint_r * 1.6)), density)
        centers = bridson(rng, zone.bbox(), cluster_spacing, domain_ok, cap=clusters)
        rng.shuffle(centers)
        centers = centers[:clusters]
        for ci, c in enumerate(centers):
            crng = rng_for(seed, zone.id, slot_index, tag, "cluster", ci)
            n = crng.randint(int(per_lo), int(per_hi))
            crad = float(slot.get("cluster_radius", cluster_spacing * 0.4))
            cbbox = (c[0] - crad, c[1] - crad, c[0] + crad, c[1] + crad)

            def cluster_ok(p: SolverPoint, _c=c, _r=crad) -> bool:
                return _dist(p, _c) <= _r and domain_ok(p)

            members = bridson(crng, cbbox, member_spacing, cluster_ok, cap=n)
            crng.shuffle(members)
            raw.extend(members[:n])

    elif rule == "ring":
        count = _scaled_count(int(slot.get("count", 8)), density)
        rad = float(slot.get("radius", zone.radius if zone.shape == "circle" else 4.0))
        cx, cy = zone.centroid()
        phase = float(slot.get("phase_deg", 0.0))
        for i in range(count):
            ang = math.radians(phase) + 2 * math.pi * i / max(1, count)
            raw.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))

    elif rule == "scatter_along":
        if zone.shape != "spline" or not zone.points:
            warnings.append(f"zone '{zone.id}' slot '{tag}': scatter_along needs a spline zone")
        else:
            count = _scaled_count(int(slot.get("count", 6)), density)
            length = _polyline_length(zone.points)
            band = slot.get("band", [0.4, 1.0])  # fraction of half-width
            for i in range(count):
                s = rng.uniform(0, length)
                (px, py), (tx, ty) = _point_at_arclen(zone.points, s)
                side = rng.choice([-1, 1])
                off = rng.uniform(band[0], band[1]) * (zone.width / 2) * side
                nx, ny = -ty, tx  # left normal
                raw.append((px + nx * off, py + ny * off))

    elif rule == "grid_along":
        if zone.shape != "spline" or not zone.points:
            warnings.append(f"zone '{zone.id}' slot '{tag}': grid_along needs a spline zone")
        else:
            spacing = _scaled_spacing(float(slot.get("spacing", 3.0)), density)
            side = slot.get("side", "both")
            length = _polyline_length(zone.points)
            off = zone.width / 2
            n = int(length // spacing) + 1
            for i in range(n):
                s = i * spacing
                (px, py), (tx, ty) = _point_at_arclen(zone.points, s)
                nx, ny = -ty, tx
                sides = {"left": [1], "right": [-1], "both": [1, -1]}.get(side, [1, -1])
                for sgn in sides:
                    raw.append((px + nx * off * sgn, py + ny * off * sgn))

    elif rule == "grid":
        bx = zone.bbox()
        spacing = _scaled_spacing(float(slot.get("spacing", max(footprint_r * 2, 1.0))), density)
        jitter = float(slot.get("jitter", 0.0))
        x = bx[0] + spacing / 2
        while x <= bx[2]:
            y = bx[1] + spacing / 2
            while y <= bx[3]:
                p = (x + rng.uniform(-jitter, jitter), y + rng.uniform(-jitter, jitter))
                if domain_ok(p):
                    raw.append(p)
                y += spacing
            x += spacing
    else:
        warnings.append(f"zone '{zone.id}' slot '{tag}': unknown rule '{rule}', skipped")

    # Materialize instances: filter parametric rules, register solids, jitter.
    instances: list[dict] = []
    yaw_spec = slot.get("yaw", 0)
    scale_jitter = slot.get("scale_jitter", [1.0, 1.0])
    scale_base = float(info.get("scale_base", slot.get("scale_base", 1.0)))
    cx, cy = zone.centroid()
    for i, p in enumerate(raw):
        # single/ring/*_along generate points parametrically (they do not run
        # through domain_ok), so enforce keep-out/bounds/collision here. A single
        # hero prop keeps its authored spot unless it is in keep-out/out of bounds.
        if rule == "single":
            if not (in_bounds(p) and not keepout.blocks(p)):
                warnings.append(f"zone '{zone.id}' slot '{tag}': hero prop dropped (keepout/out-of-bounds)")
                continue
        elif rule in ("ring", "scatter_along", "grid_along"):
            if not hard_ok(p):
                continue
        # poisson / poisson_multimesh / cluster / grid points already satisfied
        # domain_ok at generation time. Reserve footprint only for SOLID props.
        if not is_foliage:
            occ.add(p, footprint_r)
        irng = rng_for(seed, zone.id, slot_index, tag, "inst", i)
        if yaw_spec == "random":
            yaw = irng.uniform(0, 360)
        elif yaw_spec == "face_center":
            yaw = math.degrees(math.atan2(cx - p[0], cy - p[1]))
        else:
            yaw = float(yaw_spec)
        s = scale_base * irng.uniform(scale_jitter[0], scale_jitter[1])
        instances.append({
            "kit_tag": tag,
            "category": zone.id,
            "plane": [round(p[0], 4), round(p[1], 4)],
            "yaw_deg": round(yaw, 2),
            "scale": round(s, 4),
            "footprint": [fw, fh],
            "rule": rule,
            "multimesh": rule == "poisson_multimesh" and bool(info.get("multimesh_ok", True)),
            "asset": info.get("asset", f"unresolved:{tag}"),
        })
    return instances


# ---------------------------------------------------------------------------
# Top-level solve
# ---------------------------------------------------------------------------

def solve(layout: dict, seed: int, density_name: str, resolved: dict) -> dict:
    density = DENSITY_SCALE.get(density_name, DENSITY_SCALE["medium"])
    dimension = layout.get("dimension", "3d")
    ground = layout.get("ground", {})
    ground_bounds = ground.get("bounds")
    ground_y = float(ground.get("y", 0.0))
    keepout = KeepOut(layout.get("keepout", []))

    # Occupancy cell sized to the median footprint keeps neighbour queries cheap.
    occ = Occupancy(cell=1.0)
    warnings: list[str] = []
    all_instances: list[dict] = []
    stats: list[dict] = []

    for zone_spec in layout.get("zones", []):
        zone = Zone(zone_spec)
        for si, slot in enumerate(zone_spec.get("slots", [])):
            insts = solve_slot(
                zone, slot, si, seed, density, keepout, occ, resolved, ground_bounds, warnings
            )
            all_instances.extend(insts)
            stats.append({
                "zone": zone.id,
                "kit_tag": slot.get("kit_tag"),
                "rule": slot.get("rule"),
                "requested": slot.get("count", slot.get("clusters", 1)),
                "placed": len(insts),
            })

    # Split into per-instance list and MultiMesh groups.
    instances_out: list[dict] = []
    mm_groups: dict[str, dict] = {}
    for inst in all_instances:
        a, b = inst["plane"]
        if dimension == "3d":
            pos = [a, ground_y, b]
        else:
            pos = [a, b]
        if inst["multimesh"]:
            key = inst["kit_tag"]
            grp = mm_groups.setdefault(key, {
                "group": key,
                "category": inst["category"],
                "asset": inst["asset"],
                "footprint": inst["footprint"],
                "transforms": [],
            })
            if dimension == "3d":
                grp["transforms"].append([a, ground_y, b, inst["yaw_deg"], inst["scale"]])
            else:
                grp["transforms"].append([a, b, inst["yaw_deg"], inst["scale"]])
        else:
            instances_out.append({
                "kit_tag": inst["kit_tag"],
                "category": inst["category"],
                "asset": inst["asset"],
                "pos": pos,
                "yaw_deg": inst["yaw_deg"],
                "scale": inst["scale"],
                "footprint": inst["footprint"],
            })

    return {
        "version": 1,
        "seed": seed,
        "dimension": dimension,
        "ground_y": ground_y,
        "backdrop": layout.get("backdrop"),
        "instances": instances_out,
        "multimesh": list(mm_groups.values()),
        "stats": stats,
        "warnings": warnings,
        "totals": {
            "instances": len(instances_out),
            "multimesh_groups": len(mm_groups),
            "multimesh_instances": sum(len(g["transforms"]) for g in mm_groups.values()),
        },
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: Optional[list[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="scene-populate placement solver")
    ap.add_argument("--layout", required=True, help="LAYOUT.json path")
    ap.add_argument("--resolved", help="resolved.json (kit_tag -> asset facts) from kit_index.py")
    ap.add_argument("--seed", type=int, help="Override the seed in LAYOUT.json")
    ap.add_argument("--density", default=None, choices=list(DENSITY_SCALE),
                    help="Override density scaling (default: medium / LAYOUT value)")
    ap.add_argument("--out", default="placements.json", help="Output path ('-' for stdout)")
    args = ap.parse_args(argv)

    with open(args.layout, encoding="utf-8") as f:
        layout = json.load(f)
    resolved = {}
    if args.resolved:
        with open(args.resolved, encoding="utf-8") as f:
            resolved = json.load(f)

    seed = args.seed if args.seed is not None else int(layout.get("seed", 0))
    density = args.density or layout.get("density", "medium")

    result = solve(layout, seed, density, resolved)

    text = json.dumps(result, indent=2) + "\n"
    if args.out == "-":
        sys.stdout.write(text)
    else:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text)
        print(json.dumps({
            "ok": True,
            "out": args.out,
            "totals": result["totals"],
            "warnings": len(result["warnings"]),
        }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
