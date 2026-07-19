#!/usr/bin/env python3
"""scene-populate scene emitter — placements.json -> scenes/build_<name>_dress.gd.

Fills the GDScript template (dress_template.gd) with the concrete placements
path, target scene, output path, and dimension, then writes a runnable headless
scene builder. The agent runs it with (always scope to this project with --path):

    godot --headless --path . --script scenes/build_<name>_dress.gd

which patches the target scene (adds/replaces a single `SetDressing` subtree) and
saves the .tscn. All the heavy lifting (GLB AABB-scaling, MultiMesh batching,
owner-chain with GLB guard, greybox fallback) lives in the template — this tool
just parameterizes it, so the emitted builder is small and diff-friendly.

Usage
-----
  python3 emit_scene.py --placements placements.json \
      --target res://scenes/level_1.tscn \
      --out scenes/build_level_1_dress.gd

  # NEW scene (no target to patch) — a ground plane is laid from --ground:
  python3 emit_scene.py --placements placements.json --target NEW \
      --output-scene res://scenes/clearing.tscn --ground=-20,-20,20,20 \
      --out scenes/build_clearing_dress.gd
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Optional

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / "dress_template.gd"


def _res_path(p: str) -> str:
    """Normalize a project-relative or res:// path to a res:// path."""
    if p.startswith("res://"):
        return p
    return "res://" + p.lstrip("/").replace("\\", "/")


def emit(
    placements_path: str,
    target: str,
    output_scene: Optional[str],
    ground: Optional[str],
    out_path: str,
) -> dict:
    template = TEMPLATE.read_text(encoding="utf-8")

    # placements.json lives at project root by convention -> res:// path.
    placements_res = _res_path(placements_path)

    if target == "NEW":
        if not output_scene:
            raise SystemExit("--target NEW requires --output-scene")
        target_token = "NEW"
        output_token = _res_path(output_scene)
    else:
        target_token = _res_path(target)
        output_token = _res_path(output_scene) if output_scene else target_token

    # dimension is read from the placements file so the emitter and solver agree.
    dimension = "3d"
    try:
        data = json.loads(Path(placements_path).read_text(encoding="utf-8"))
        dimension = data.get("dimension", "3d")
    except Exception:
        pass

    ground_token = "null"
    if ground:
        parts = [float(x) for x in ground.split(",")]
        if len(parts) == 4:
            ground_token = json.dumps(parts)

    replacements = {
        "__PLACEMENTS_PATH__": placements_res,
        "__TARGET_SCENE__": target_token,
        "__OUTPUT_SCENE__": output_token,
        "__DIMENSION__": dimension,
        "__NEW_GROUND__": ground_token,
    }
    filled = template
    for token, value in replacements.items():
        filled = filled.replace(token, value)

    # Safety: no token should survive.
    leftover = re.findall(r"__[A-Z_]+__", filled)
    if leftover:
        raise SystemExit(f"unfilled template tokens: {sorted(set(leftover))}")

    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(filled, encoding="utf-8")

    return {
        "ok": True,
        "builder": out_path,
        "target": target_token,
        "output_scene": output_token,
        "dimension": dimension,
        "run": f"godot --headless --path . --script {out_path}",
    }


def main(argv: Optional[list[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="scene-populate scene emitter")
    ap.add_argument("--placements", required=True, help="placements.json path (project-relative)")
    ap.add_argument("--target", required=True, help="res:// scene to patch, or NEW")
    ap.add_argument("--output-scene", help="res:// path to save (default: same as --target)")
    ap.add_argument("--ground", help="NEW-scene ground bounds xmin,zmin,xmax,zmax")
    ap.add_argument("--out", required=True, help="Output builder .gd path")
    args = ap.parse_args(argv)

    result = emit(args.placements, args.target, args.output_scene, args.ground, args.out)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
