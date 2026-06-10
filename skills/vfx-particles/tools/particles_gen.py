#!/usr/bin/env python3
"""VFX Particles generator — emits Godot 4 GPUParticles2D `.tscn` presets
(explosion / dust / sparkle / trail / impact / magic / smoke / confetti). Drop the
scene in, position it, and `restart()` it (one-shots) or toggle `emitting`.

Distinct from shader-craft (screen-space effects) and game-feel (time/scale juice):
this is the particle layer — the burst at the point of impact, the dust under a
jump, the sparkle on a pickup. Pairs with game-feel: `Feel.impact()` + an
explosion particle at the same spot = a complete hit.

Usage:
  python3 particles_gen.py explosion --color "#ffb347" -o assets/vfx/explosion.tscn
  python3 particles_gen.py dust --color "#c8b89a" -o assets/vfx/dust.tscn

Output: JSON to stdout, the .tscn to -o.
"""

import argparse
import json
import sys
from pathlib import Path


def hex_to_color(h: str) -> str:
    h = h.lstrip("#")
    if len(h) == 6:
        h += "ff"
    r, g, b, a = (int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4, 6))
    return f"Color({r:.4g}, {g:.4g}, {b:.4g}, {a:.4g})"


# Each preset: GPUParticles2D node params + ParticleProcessMaterial params.
PRESETS = {
    "explosion": dict(
        amount=40, lifetime=0.6, one_shot=True, explosiveness=0.95,
        mat=dict(emission_shape=1, emission_sphere_radius=4.0, spread=180.0,
                 initial_velocity_min=120.0, initial_velocity_max=260.0,
                 gravity="Vector3(0, 120, 0)", scale_min=0.6, scale_max=1.4,
                 damping_min=40.0, damping_max=80.0),
    ),
    "dust": dict(
        amount=16, lifetime=0.5, one_shot=True, explosiveness=0.8,
        mat=dict(emission_shape=3, emission_box_extents="Vector3(10, 2, 0)",
                 direction="Vector3(0, -1, 0)", spread=30.0,
                 initial_velocity_min=20.0, initial_velocity_max=60.0,
                 gravity="Vector3(0, -30, 0)", scale_min=0.4, scale_max=0.9),
    ),
    "sparkle": dict(
        amount=24, lifetime=0.8, one_shot=False, explosiveness=0.0,
        mat=dict(emission_shape=1, emission_sphere_radius=12.0, spread=180.0,
                 initial_velocity_min=8.0, initial_velocity_max=30.0,
                 gravity="Vector3(0, 0, 0)", scale_min=0.2, scale_max=0.6),
    ),
    "trail": dict(
        amount=20, lifetime=0.4, one_shot=False, explosiveness=0.0,
        mat=dict(emission_shape=0, spread=10.0,
                 initial_velocity_min=0.0, initial_velocity_max=10.0,
                 gravity="Vector3(0, 0, 0)", scale_min=0.3, scale_max=0.7),
    ),
    "impact": dict(
        amount=18, lifetime=0.35, one_shot=True, explosiveness=1.0,
        mat=dict(emission_shape=0, spread=60.0,
                 initial_velocity_min=140.0, initial_velocity_max=240.0,
                 gravity="Vector3(0, 300, 0)", scale_min=0.5, scale_max=1.0,
                 damping_min=60.0, damping_max=120.0),
    ),
    "magic": dict(
        amount=30, lifetime=1.2, one_shot=False, explosiveness=0.0,
        mat=dict(emission_shape=1, emission_sphere_radius=8.0, spread=180.0,
                 initial_velocity_min=10.0, initial_velocity_max=40.0,
                 gravity="Vector3(0, -50, 0)", scale_min=0.2, scale_max=0.7),
    ),
    "smoke": dict(
        amount=14, lifetime=1.6, one_shot=False, explosiveness=0.0,
        mat=dict(emission_shape=1, emission_sphere_radius=6.0, spread=20.0,
                 direction="Vector3(0, -1, 0)",
                 initial_velocity_min=15.0, initial_velocity_max=35.0,
                 gravity="Vector3(0, -20, 0)", scale_min=0.8, scale_max=2.0),
    ),
    "confetti": dict(
        amount=48, lifetime=2.0, one_shot=True, explosiveness=0.8,
        mat=dict(emission_shape=3, emission_box_extents="Vector3(60, 2, 0)",
                 direction="Vector3(0, -1, 0)", spread=45.0,
                 initial_velocity_min=180.0, initial_velocity_max=320.0,
                 gravity="Vector3(0, 200, 0)", scale_min=0.4, scale_max=0.9,
                 angular_velocity_min=-360.0, angular_velocity_max=360.0),
    ),
}


def build_tscn(name: str, preset: dict, color: str) -> str:
    mat = preset["mat"]
    mat_lines = [f"{k} = {v}" for k, v in mat.items()]
    mat_lines.append(f"color = {color}")
    node_name = name.capitalize()
    node = [
        f'amount = {preset["amount"]}',
        f'lifetime = {preset["lifetime"]}',
        f'one_shot = {str(preset["one_shot"]).lower()}',
        f'explosiveness = {preset["explosiveness"]}',
        'local_coords = false',
        'process_material = SubResource("ppm")',
    ]
    return "\n".join([
        "[gd_scene load_steps=2 format=3]",
        "",
        '[sub_resource type="ParticleProcessMaterial" id="ppm"]',
        *mat_lines,
        "",
        f'[node name="{node_name}" type="GPUParticles2D"]',
        *node,
        "",
    ])


def main():
    ap = argparse.ArgumentParser(description="Emit a Godot 4 GPUParticles2D preset (.tscn).")
    ap.add_argument("preset", choices=list(PRESETS))
    ap.add_argument("--color", default="#ffffff", help="Particle color (#rrggbb[aa]).")
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()

    try:
        color = hex_to_color(args.color)
    except ValueError:
        print(json.dumps({"ok": False, "error": f"bad --color {args.color!r}"}))
        sys.exit(1)

    tscn = build_tscn(args.preset, PRESETS[args.preset], color)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(tscn, encoding="utf-8")
    print(json.dumps({
        "ok": True, "path": str(out), "preset": args.preset,
        "one_shot": PRESETS[args.preset]["one_shot"],
        "usage": "Instance the scene at the effect position; call restart() for one-shots, or set emitting=true for loops.",
        "tip": "Assign a texture to the GPUParticles2D in the editor (a soft white dot from image-pipeline --type icon) for non-square particles.",
    }))


if __name__ == "__main__":
    main()
