"""3D Asset Pipeline — PNG → GLB via Tripo3D + engine-import sidecars.

Promotes the old `asset_gen.py glb` subcommand into its own skill with
quality presets, batch processing, and one-shot prop generation that
chains image-pipeline (txt2img) → Tripo3D (mesh) → engine sidecars
(Godot .import / Unity prefab JSON).

Subcommands
-----------
mesh    PNG → GLB. Wrapper around tripo3d.image_to_glb with quality
        presets (lowpoly / medium / high / ultra) and Godot+Unity
        sidecar emission.

batch   N images → N GLBs. Reads a JSON manifest of {prompt, output}
        items OR a directory of PNGs, runs mesh on each.

prop    One-shot: txt2img a reference via image-pipeline → mesh to GLB.
        Auto-generates a clean transparent-background render suitable
        for photogrammetry-style 3D reconstruction.

All commands emit JSON to stdout with cost_cents (Tripo3D is a paid API)
and engine sidecar paths.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
SKILL_ROOT = THIS_DIR.parent
SKILLS_ROOT = SKILL_ROOT.parent
IMAGE_PIPELINE_TOOLS = SKILLS_ROOT / "image-pipeline" / "tools"

for p in (THIS_DIR, IMAGE_PIPELINE_TOOLS):
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))


# ---------------------------------------------------------------------------
# Quality presets (matches the legacy asset_gen.py table, kept stable)
# ---------------------------------------------------------------------------

QUALITY_PRESETS: dict[str, dict] = {
    "lowpoly": dict(
        face_limit=5000, smart_low_poly=True,
        texture_quality="standard", geometry_quality="standard",
        cost_cents=40,
        notes="Game-ready under 5k tris. Best for mobile / VR / large counts.",
    ),
    "medium": dict(
        face_limit=20000, smart_low_poly=False,
        texture_quality="standard", geometry_quality="standard",
        cost_cents=30,
        notes="Default. ~20k tris. Suitable for most desktop game props.",
    ),
    "high": dict(
        face_limit=None, smart_low_poly=False,
        texture_quality="detailed", geometry_quality="standard",
        cost_cents=40,
        notes="High-poly with detailed textures. For hero props and close-ups.",
    ),
    "ultra": dict(
        face_limit=None, smart_low_poly=False,
        texture_quality="detailed", geometry_quality="detailed",
        cost_cents=60,
        notes="Maximum detail. Cinematic. Slow. Don't use in bulk.",
    ),
}


# ---------------------------------------------------------------------------
# Tripo3D wrapper
# ---------------------------------------------------------------------------

def _generate_glb(image_path: Path, output_path: Path, quality: str) -> dict:
    """Run Tripo3D image_to_glb with the chosen quality preset.

    Returns a dict with {path, cost_cents, quality, notes} on success;
    raises on failure (caller logs + reports JSON error).
    """
    try:
        from tripo3d import MODEL_V3, image_to_glb
    except ImportError as e:
        raise RuntimeError(
            "tripo3d module not importable. Install with `pip install tripo3d` "
            f"or check that TRIPO3D_API_KEY is set. Underlying error: {e}"
        )

    if quality not in QUALITY_PRESETS:
        raise SystemExit(f"--quality must be one of {sorted(QUALITY_PRESETS.keys())}, got {quality!r}")

    p = QUALITY_PRESETS[quality]
    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(
        f"[mesh_gen] Tripo3D quality={quality} face_limit={p['face_limit']} "
        f"cost={p['cost_cents']}c -> {output_path}",
        file=sys.stderr,
    )
    image_to_glb(
        image_path, output_path, model_version=MODEL_V3,
        face_limit=p["face_limit"],
        smart_low_poly=p["smart_low_poly"],
        texture_quality=p["texture_quality"],
        geometry_quality=p["geometry_quality"],
    )
    return {
        "path": str(output_path),
        "cost_cents": p["cost_cents"],
        "quality": quality,
        "notes": p["notes"],
    }


# ---------------------------------------------------------------------------
# Subcommand: mesh
# ---------------------------------------------------------------------------

def cmd_mesh(args):
    image_path = Path(args.image)
    if not image_path.exists():
        raise SystemExit(f"Image not found: {image_path}")
    output_path = Path(args.output)

    result = _generate_glb(image_path, output_path, args.quality)
    engine_outputs = _write_engine_sidecars(output_path, args.engine, source_image=image_path)

    print(json.dumps({
        "ok": True, "subcommand": "mesh",
        **result, "engine_outputs": engine_outputs,
        "source_image": str(image_path),
    }, indent=2))


# ---------------------------------------------------------------------------
# Subcommand: batch
# ---------------------------------------------------------------------------

def cmd_batch(args):
    """Process a manifest of {image, output} pairs OR a directory of PNGs.

    Manifest JSON shape:
      {"items": [{"image": "in/knight.png", "output": "out/knight.glb"}, ...]}
    """
    items: list[dict] = []
    if args.manifest:
        manifest_path = Path(args.manifest)
        if not manifest_path.exists():
            raise SystemExit(f"Manifest not found: {manifest_path}")
        manifest = json.loads(manifest_path.read_text())
        items = manifest.get("items", [])
    elif args.input_dir:
        in_dir = Path(args.input_dir)
        out_dir = Path(args.output_dir or in_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        for png in sorted(in_dir.glob("*.png")):
            items.append({
                "image": str(png),
                "output": str(out_dir / f"{png.stem}.glb"),
            })
    else:
        raise SystemExit("Provide either --manifest or --input-dir")

    if not items:
        raise SystemExit("No items to process")

    results: list[dict] = []
    total_cost = 0
    for item in items:
        img = Path(item["image"])
        out = Path(item["output"])
        try:
            r = _generate_glb(img, out, args.quality)
            engine_outputs = _write_engine_sidecars(out, args.engine, source_image=img)
            r["engine_outputs"] = engine_outputs
            r["ok"] = True
            r["source_image"] = str(img)
        except Exception as e:
            r = {"ok": False, "error": str(e), "source_image": str(img), "output": str(out)}
        results.append(r)
        if r.get("ok"):
            total_cost += r.get("cost_cents", 0)

    print(json.dumps({
        "ok": all(r.get("ok") for r in results),
        "subcommand": "batch",
        "item_count": len(items),
        "total_cost_cents": total_cost,
        "results": results,
    }, indent=2))


# ---------------------------------------------------------------------------
# Subcommand: prop (chain image-pipeline txt2img → mesh)
# ---------------------------------------------------------------------------

def cmd_prop(args):
    """txt2img a clean transparent-background render via image-pipeline,
    then convert it to GLB via Tripo3D. Single-command prop generation.

    Uses image-pipeline's asset_gen.py with --type item (which auto-loads
    the ZIT pixel LoRA and forces a clean-silhouette prompt). Pass --no-
    pixelize to keep the high-res render that Tripo3D needs for good
    geometry reconstruction.
    """
    output_glb = Path(args.output)
    intermediate_png = output_glb.with_suffix(".ref.png")

    # Invoke image-pipeline's asset_gen.py as a subprocess so we don't have
    # to re-import its entire CLI stack here. Pass through style/preset.
    image_pipeline_cli = IMAGE_PIPELINE_TOOLS / "asset_gen.py"
    cmd: list[str] = [
        sys.executable, str(image_pipeline_cli), "image",
        "--type", args.image_type,
        "--prompt", args.prompt,
        "--size", args.image_size,
        "--aspect-ratio", "1:1",
        "-o", str(intermediate_png),
        "--no-face-detailer",  # 3D reconstruction doesn't need face refinement
    ]
    if args.style:
        cmd += ["--style", args.style]
    if args.preset:
        cmd += ["--preset", args.preset]
    # Skip pixelize — Tripo3D wants the smooth high-res render.

    print(f"[mesh_gen.prop] generating reference image -> {intermediate_png}", file=sys.stderr)
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit(f"image-pipeline asset_gen failed: {proc.stderr}")

    # asset_gen prints a JSON line on stdout; surface its details.
    img_result: dict = {}
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                img_result = json.loads(line)
            except json.JSONDecodeError:
                continue

    if not intermediate_png.exists():
        raise SystemExit(f"image-pipeline reported success but {intermediate_png} not found")

    # Now mesh it.
    mesh_result = _generate_glb(intermediate_png, output_glb, args.quality)
    engine_outputs = _write_engine_sidecars(output_glb, args.engine, source_image=intermediate_png)

    print(json.dumps({
        "ok": True, "subcommand": "prop",
        **mesh_result,
        "reference_image": str(intermediate_png),
        "image_pipeline": img_result,
        "engine_outputs": engine_outputs,
    }, indent=2))


# ---------------------------------------------------------------------------
# Engine sidecar writers
# ---------------------------------------------------------------------------

def _write_engine_sidecars(
    glb_path: Path,
    engine: str,
    source_image: Path | None = None,
) -> dict[str, str]:
    out: dict[str, str] = {}
    if engine in ("godot", "both"):
        # Godot 4 .import file for a GLB asset. Godot generates these
        # automatically on first scan, but pre-emitting a minimal one lets
        # the import settle without an editor round-trip.
        imp = glb_path.parent / f"{glb_path.name}.import"
        lines = [
            "[remap]",
            'importer="scene"',
            'type="PackedScene"',
            f'uid="uid://{_uid_for(glb_path)}"',
            f'path="res://.godot/imported/{glb_path.stem}-{_uid_for(glb_path)[:8]}.scn"',
            "",
            "[deps]",
            f'source_file="res://{glb_path.name}"',
            f'dest_files=["res://.godot/imported/{glb_path.stem}-{_uid_for(glb_path)[:8]}.scn"]',
            "",
            "[params]",
            'nodes/use_node_type_suffixes=true',
            "",
        ]
        imp.write_text("\n".join(lines), encoding="utf-8")
        out["godot_import"] = str(imp)

    if engine in ("unity", "both"):
        # Unity prefab JSON sidecar — describes the import settings the
        # user should apply (Unity .meta YAML is too version-specific to
        # auto-generate reliably).
        json_path = glb_path.with_suffix(".unity.json")
        data = {
            "asset": glb_path.name,
            "asset_path": str(glb_path),
            "source_image": str(source_image) if source_image else None,
            "unity_import": {
                "model_importer": {
                    "scale_factor": 1.0,
                    "use_file_scale": True,
                    "import_blend_shapes": False,
                    "import_visibility": True,
                    "import_cameras": False,
                    "import_lights": False,
                    "mesh_compression": "Off",
                    "read_write_enabled": False,
                    "optimize_mesh": True,
                    "generate_colliders": False,
                    "normals": "Import",
                    "tangents": "Calculate Tangent Space",
                },
                "materials": {
                    "location": "Use External Materials (Legacy)",
                    "naming": "By Base Texture Name",
                    "search": "Local Materials Folder",
                },
            },
            "usage": (
                "1. Drop GLB into Unity Assets/. 2. Set ModelImporter per "
                "unity_import.model_importer. 3. Drag into scene for an "
                "instance prefab."
            ),
        }
        json_path.write_text(json.dumps(data, indent=2), encoding="utf-8")
        out["unity_json"] = str(json_path)
    return out


def _uid_for(path: Path) -> str:
    """Deterministic 16-char id from path name for Godot .import uid.

    Real Godot uids are 16 base-36 chars from a random source; we just
    hash the filename so re-running this command doesn't change the uid.
    Godot will rewrite this on next editor scan if it dislikes the form.
    """
    import hashlib
    h = hashlib.sha256(path.name.encode()).hexdigest()
    # Map hex → base-36-ish; not strictly base-36 but Godot is permissive.
    return h[:16]


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="3d-asset-pipeline: PNG → GLB + engine sidecars")
    sub = parser.add_subparsers(required=True, dest="cmd")

    p = sub.add_parser("mesh", help="Convert a PNG to GLB via Tripo3D")
    p.add_argument("--image", required=True, help="Source PNG path")
    p.add_argument("-o", "--output", required=True, help="Output GLB path")
    p.add_argument("--quality", default="medium", choices=list(QUALITY_PRESETS.keys()))
    p.add_argument("--engine", default="both", choices=["godot", "unity", "both", "none"])
    p.set_defaults(func=cmd_mesh)

    p = sub.add_parser("batch", help="Process many PNGs into GLBs")
    p.add_argument("--manifest", help="JSON manifest with {items: [{image, output}, ...]}")
    p.add_argument("--input-dir", help="Directory of PNGs (auto-derives output GLB names)")
    p.add_argument("--output-dir", help="Output dir for --input-dir mode (default: same as input)")
    p.add_argument("--quality", default="medium", choices=list(QUALITY_PRESETS.keys()))
    p.add_argument("--engine", default="both", choices=["godot", "unity", "both", "none"])
    p.set_defaults(func=cmd_batch)

    p = sub.add_parser("prop", help="One-shot: txt2img → mesh → GLB")
    p.add_argument("--prompt", required=True, help="Prop description")
    p.add_argument("--image-type", default="item",
                   choices=["item", "icon", "character", "sprite", "general"])
    p.add_argument("--image-size", default="1K", choices=["512", "1K", "2K", "4K"])
    p.add_argument("--style", default="")
    p.add_argument("--preset", default="")
    p.add_argument("--quality", default="medium", choices=list(QUALITY_PRESETS.keys()))
    p.add_argument("-o", "--output", required=True, help="Output GLB path")
    p.add_argument("--engine", default="both", choices=["godot", "unity", "both", "none"])
    p.set_defaults(func=cmd_prop)

    p = sub.add_parser("list-presets", help="List quality presets and exit")
    p.set_defaults(func=lambda a: print(
        "Tripo3D quality presets:\n" + "\n".join(
            f"  {name:8s} cost={pre['cost_cents']:>2}c  {pre['notes']}"
            for name, pre in QUALITY_PRESETS.items()
        )
    ))

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
