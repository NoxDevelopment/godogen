"""Scene Art generator — parallax backgrounds, skyboxes, tilesets, environments.

Composes the image-pipeline primitives (Z-Image-Turbo via comfyui_client,
zit_styles registry, pixel_art_toolkit, pixel_art_presets) into scene-level
workflows for game art. Output files use Godot- and Unity-friendly naming
and (when --engine is passed) drop companion .tscn/.tres/.json files that
wire the PNGs into a working asset.

Subcommands
-----------
parallax     N consistent-style layered PNGs (sky/far/mid/near/fg)
             + optional Godot ParallaxBackground.tscn / Unity layout.json

skybox       6 cube faces (px/nx/py/ny/pz/nz) OR 1 equirectangular 2:1 PNG
             + optional Godot Sky.tres / Unity setup README.

tileset      Seamless tile atlas sliced into a grid (default 4x4 of 32px)
             with pixelize + palette lock, + optional Godot TileSet.tres /
             Unity atlas slice JSON.

environment  Single wide-aspect (21:9 by default) scene reference. Pair
             with --reference to anchor against an existing project image.

All commands accept --preset (from image-pipeline/presets/pixel_art_presets)
and --style (from image-pipeline/zit_styles) so the project's aesthetic
stays consistent across asset types.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# --- Reach into image-pipeline for the heavy lifting ---
THIS_DIR = Path(__file__).resolve().parent
SCENE_ART_ROOT = THIS_DIR.parent
SKILLS_ROOT = SCENE_ART_ROOT.parent  # godogen/skills/
IMAGE_PIPELINE_TOOLS = SKILLS_ROOT / "image-pipeline" / "tools"
IMAGE_PIPELINE_PRESETS = SKILLS_ROOT / "image-pipeline" / "presets"

for p in (THIS_DIR, IMAGE_PIPELINE_TOOLS, IMAGE_PIPELINE_PRESETS):
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))


# ---------------------------------------------------------------------------
# Per-asset prompt scaffolding
# ---------------------------------------------------------------------------

# Parallax layer descriptors, back-to-front. The dict key is the number of
# layers requested; values are (name, descriptor, motion_scale) tuples used
# both to bias the txt2img prompt and to wire the Godot ParallaxLayer.
PARALLAX_LAYER_SETS: dict[int, list[tuple[str, str, float]]] = {
    3: [
        ("sky", "distant sky and clouds, gradient horizon", 0.1),
        ("mid", "mid-distance hills or buildings, soft silhouette", 0.5),
        ("foreground", "near foreground props, clear hard edges, alpha-cut friendly", 0.9),
    ],
    4: [
        ("sky", "distant sky and clouds, gradient horizon", 0.1),
        ("far", "far mountains or skyline silhouette, atmospheric haze", 0.3),
        ("mid", "mid-distance trees or buildings, more detail", 0.6),
        ("foreground", "near foreground props, hard edges, alpha-cut friendly", 0.9),
    ],
    5: [
        ("sky", "distant sky and clouds, gradient horizon", 0.05),
        ("very_far", "very distant silhouettes, faded by atmospheric haze", 0.2),
        ("far", "far mountains or skyline, light haze", 0.4),
        ("mid", "mid-distance trees or buildings, defined shapes", 0.65),
        ("foreground", "near foreground props, hard edges, alpha-cut friendly", 0.9),
    ],
    6: [
        ("sky", "distant sky gradient, soft clouds", 0.05),
        ("very_far", "very distant silhouettes, atmospheric haze", 0.18),
        ("far", "far mountains, light haze", 0.32),
        ("mid_far", "mid-far buildings or trees, fading detail", 0.5),
        ("mid", "mid-ground props, full color", 0.7),
        ("foreground", "near foreground, hard edges, alpha-cut", 0.92),
    ],
    7: [
        ("sky", "distant sky gradient", 0.04),
        ("very_far", "very distant atmospheric silhouettes", 0.15),
        ("far", "far mountains, haze", 0.28),
        ("mid_far", "mid-far mountains or buildings", 0.42),
        ("mid", "mid-ground trees or structures, defined detail", 0.6),
        ("near", "near-ground larger shapes, sharper detail", 0.78),
        ("foreground", "very near foreground props, hard edges, alpha-cut", 0.95),
    ],
}

# 6-face cube prompts. Z-Image won't stitch a true panorama between faces,
# but biasing each face with a directional descriptor + a shared style/seed
# gets visually close enough for stylized games (warn in SKILL.md).
CUBE_FACE_PROMPTS = {
    "px": "looking east at the horizon, wide panoramic view, no foreground, edge-aligned with adjacent faces",
    "nx": "looking west at the horizon, wide panoramic view, no foreground, edge-aligned with adjacent faces",
    "py": "looking straight up at the sky overhead, clouds radiating outward, no horizon",
    "ny": "looking straight down at the ground directly below, top-down view, no horizon",
    "pz": "looking south at the horizon, wide panoramic view, no foreground, edge-aligned with adjacent faces",
    "nz": "looking north at the horizon, wide panoramic view, no foreground, edge-aligned with adjacent faces",
}

# Environment-type prompt prefixes.
ENVIRONMENT_PREFIXES = {
    "forest": "dense forest, towering trees, dappled sunlight, mossy undergrowth",
    "dungeon": "ancient stone dungeon, torchlit corridor, damp walls, moody shadows",
    "city": "stylized city street, dramatic perspective, neon-lit shopfronts",
    "cave": "vast underground cavern, stalactites, faint glow from crystal formations",
    "space": "cosmic vista, swirling nebula, distant stars, deep space lighting",
    "desert": "sweeping desert dunes, wind-shaped sand, warm late-afternoon light",
    "ruins": "weathered ancient ruins, broken columns, overgrowth, mysterious atmosphere",
    "tundra": "frozen tundra plain, snow drifts, low pale sun, sparse dark trees",
    "swamp": "misty swamp, gnarled trees, still murky water, fog at low height",
    "ocean": "open ocean horizon, rolling waves, distant storm clouds",
}


# ---------------------------------------------------------------------------
# Lazy imports — only pulled when a subcommand actually runs
# ---------------------------------------------------------------------------

def _imp_comfy():
    """Load comfyui_client. Returns the module."""
    import comfyui_client as cc
    return cc


def _imp_pixel_toolkit():
    import pixel_art_toolkit as pt
    return pt


def _load_pixel_presets():
    """Cached loader for pixel_art_presets.PIXEL_STYLE_PRESETS."""
    cached = getattr(_load_pixel_presets, "_cache", None)
    if cached is not None:
        return cached
    import pixel_art_presets as p
    _load_pixel_presets._cache = p.PIXEL_STYLE_PRESETS
    return p.PIXEL_STYLE_PRESETS


def _resolve_zit_style(style_key: str) -> list[dict]:
    """Lookup zit_styles.STYLES → list of {name, strength_model, strength_clip}.

    Returns [] if style_key is empty or not found (caller falls back to the
    default ZIT pixel LoRA).
    """
    if not style_key:
        return []
    try:
        import zit_styles as zs
    except ImportError:
        return []
    spec = zs.STYLES.get(style_key)
    if not spec:
        return []
    return [
        {
            "name": le.name,
            "strength_model": le.strength_model,
            "strength_clip": le.strength_clip,
        }
        for le in spec.loras
    ]


def _apply_preset_to_args(args) -> dict | None:
    """Mirror image-pipeline's _apply_preset behaviour for scene-art.

    Mutates args.prompt (prepends prompt_prefix) and fills palette /
    target_size if unset. Stashes negative_extra on args for downstream.
    """
    name = getattr(args, "preset", "") or ""
    if not name:
        return None
    presets = _load_pixel_presets()
    if name not in presets:
        raise SystemExit(
            f"scene_gen: unknown --preset '{name}'. "
            f"Run 'asset_gen.py list-presets' (in image-pipeline) to see options."
        )
    p = presets[name]
    prefix = (p.get("prompt_prefix") or "").rstrip(", ")
    if prefix and getattr(args, "prompt", ""):
        args.prompt = f"{prefix}, {args.prompt}".strip(", ")
    if not getattr(args, "palette", "") and p.get("suggested_palette"):
        args.palette = p["suggested_palette"]
    args.preset_negative_extra = (p.get("negative_extra") or "").strip()
    args._preset_resolution = int(p.get("suggested_resolution") or 0)
    return p


# ---------------------------------------------------------------------------
# Shared ComfyUI dispatch — wraps build_zit_txt2img_workflow + queue + download
# ---------------------------------------------------------------------------

def _zit_txt2img(
    prompt: str,
    width: int,
    height: int,
    output_path: Path,
    loras: list[dict] | None = None,
    negative: str = "",
    seed: int | None = None,
    timeout: int = 300,
) -> Path:
    """Run one txt2img through Z-Image-Turbo at fixed 8 steps / CFG 4.5."""
    cc = _imp_comfy()
    base_url = os.environ.get("COMFYUI_URL", cc.COMFYUI_URL)
    if not cc.is_available(base_url):
        raise RuntimeError(f"ComfyUI not reachable at {base_url}")
    workflow = cc.build_zit_txt2img_workflow(
        prompt=prompt,
        negative=negative or cc.ZIT_NEGATIVE,
        loras=loras or [{"name": cc.ZIT_PIXEL_LORA, "strength_model": 0.8, "strength_clip": 0.8}],
        width=width,
        height=height,
        steps=cc.ZIT_STEPS,
        cfg=cc.ZIT_CFG,
        seed=seed,
    )
    prompt_id = cc.queue_prompt(workflow, base_url)
    history = cc.poll_completion(prompt_id, base_url, timeout=timeout)
    images = cc.get_output_images(history)
    if not images:
        raise RuntimeError("ComfyUI returned no images")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    return cc.download_image(images[0], output_path, base_url)


def _zit_img2img(
    prompt: str,
    reference_path: Path,
    width: int,
    height: int,
    output_path: Path,
    loras: list[dict] | None = None,
    negative: str = "",
    denoise: float = 0.55,
    seed: int | None = None,
    timeout: int = 300,
) -> Path:
    cc = _imp_comfy()
    base_url = os.environ.get("COMFYUI_URL", cc.COMFYUI_URL)
    if not cc.is_available(base_url):
        raise RuntimeError(f"ComfyUI not reachable at {base_url}")
    ref_filename = cc.upload_image(reference_path, base_url)
    workflow = cc.build_zit_img2img_workflow(
        image_filename=ref_filename,
        prompt=prompt,
        negative=negative or cc.ZIT_NEGATIVE,
        loras=loras or [{"name": cc.ZIT_PIXEL_LORA, "strength_model": 0.8, "strength_clip": 0.8}],
        denoise=denoise,
        steps=cc.ZIT_STEPS,
        cfg=cc.ZIT_CFG,
        seed=seed,
    )
    prompt_id = cc.queue_prompt(workflow, base_url)
    history = cc.poll_completion(prompt_id, base_url, timeout=timeout)
    images = cc.get_output_images(history)
    if not images:
        raise RuntimeError("ComfyUI returned no images")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    return cc.download_image(images[0], output_path, base_url)


# ---------------------------------------------------------------------------
# Optional post-processing
# ---------------------------------------------------------------------------

def _maybe_pixelize(
    src: Path,
    target_w: int,
    target_h: int,
    palette: str = "",
    colors: int = 0,
    dither: bool = False,
) -> Path:
    """Run pixelize on src in place if target_w/target_h are smaller than
    the image's current dimensions. No-op for non-pixel-art runs.
    """
    if target_w <= 0 and target_h <= 0:
        return src
    pt = _imp_pixel_toolkit()
    from PIL import Image
    img = Image.open(src).convert("RGBA")
    # pixel_art_toolkit.pixelize takes a single target dimension; for non-
    # square outputs we pixelize to the longer side and trust its
    # aspect-preserving resize.
    target = max(target_w, target_h)
    result = pt.pixelize(img, target, colors, palette, dither)
    result.save(src)
    return src


def _cut_background_alpha(src: Path, threshold: int = 240) -> Path:
    """Naive luminance-based background cut: pixels brighter than `threshold`
    on all RGB channels become transparent. Useful for foreground parallax
    layers that come back with white/light backgrounds. Not as good as
    rembg, but zero-dep and good-enough for stylized scenes.
    """
    from PIL import Image
    img = Image.open(src).convert("RGBA")
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                pixels[x, y] = (r, g, b, 0)
    img.save(src)
    return src


# ---------------------------------------------------------------------------
# Subcommand: parallax
# ---------------------------------------------------------------------------

def cmd_parallax(args):
    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    preset = _apply_preset_to_args(args)
    loras = _resolve_zit_style(getattr(args, "style", "") or "")

    n = args.layers
    if n not in PARALLAX_LAYER_SETS:
        valid = sorted(PARALLAX_LAYER_SETS.keys())
        raise SystemExit(f"--layers must be one of {valid}, got {n}")
    layer_specs = PARALLAX_LAYER_SETS[n]

    negative_base = ""
    cc = _imp_comfy()
    neg = cc.ZIT_NEGATIVE
    extra_neg = getattr(args, "preset_negative_extra", "") or ""
    if extra_neg:
        neg = f"{neg}, {extra_neg}".strip(", ")

    written_layers: list[tuple[str, Path, float]] = []
    print(
        f"[scene_gen.parallax] {n} layers at {args.width}x{args.height} "
        f"preset={getattr(args, 'preset', '') or '-'} style={getattr(args, 'style', '') or '-'}",
        file=sys.stderr,
    )

    # Seed across layers can be either constant (same seed, different prompt)
    # for tight style coherence, or per-layer (more variety). Default: same
    # seed; pass --vary-seed to randomize per-layer.
    import random
    base_seed = args.seed if args.seed != 0 else random.randint(0, 2**32 - 1)

    for idx, (name, descriptor, scroll) in enumerate(layer_specs):
        prompt = f"parallax scrolling background, {descriptor}, {args.prompt}"
        out_path = out_dir / f"layer_{idx:02d}_{name}.png"
        seed = base_seed if not args.vary_seed else base_seed + idx * 1009
        _zit_txt2img(
            prompt=prompt,
            width=args.width,
            height=args.height,
            output_path=out_path,
            loras=loras or None,
            negative=neg,
            seed=seed,
            timeout=args.timeout,
        )
        # Foreground layer (last) gets alpha-cut so it composites cleanly.
        is_foreground = idx == len(layer_specs) - 1
        if is_foreground and not args.no_bg_cut:
            _cut_background_alpha(out_path, threshold=args.bg_cut_threshold)
        # Optional pixelize per layer.
        if args.pixelize:
            target_w = args.target_width or (args._preset_resolution if preset else 0)
            target_h = args.target_height or target_w
            if target_w > 0:
                _maybe_pixelize(out_path, target_w, target_h, args.palette, args.colors, args.dither)
        written_layers.append((name, out_path, scroll))

    # Engine companion files
    engine_outputs: dict[str, str] = {}
    if args.engine in ("godot", "both"):
        from engine_writers import write_godot_parallax_tscn
        tscn = write_godot_parallax_tscn(
            written_layers,
            out_dir / "parallax.tscn",
            viewport_size=(args.width, args.height),
        )
        engine_outputs["godot_tscn"] = str(tscn)
    if args.engine in ("unity", "both"):
        from engine_writers import write_unity_parallax_json
        unity_json = write_unity_parallax_json(written_layers, out_dir / "parallax_layout.json")
        engine_outputs["unity_json"] = str(unity_json)

    result = {
        "ok": True,
        "subcommand": "parallax",
        "layer_count": n,
        "layers": [
            {"name": name, "path": str(path), "scroll_speed": scroll}
            for (name, path, scroll) in written_layers
        ],
        "engine_outputs": engine_outputs,
    }
    print(json.dumps(result, indent=2))


# ---------------------------------------------------------------------------
# Subcommand: skybox
# ---------------------------------------------------------------------------

def cmd_skybox(args):
    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    _apply_preset_to_args(args)
    loras = _resolve_zit_style(getattr(args, "style", "") or "")

    cc = _imp_comfy()
    neg = cc.ZIT_NEGATIVE
    extra_neg = getattr(args, "preset_negative_extra", "") or ""
    if extra_neg:
        neg = f"{neg}, {extra_neg}".strip(", ")

    import random
    base_seed = args.seed if args.seed != 0 else random.randint(0, 2**32 - 1)

    if args.type == "equirect":
        # Equirectangular: 2:1 aspect. Default 2048x1024 for decent res
        # at standard skybox sampling.
        w = args.size
        h = args.size // 2
        prompt = (
            f"equirectangular panoramic sky, 360-degree wraparound, "
            f"no foreground, seamless horizontal edges, {args.prompt}"
        )
        out_path = out_dir / "sky_equirect.png"
        print(
            f"[scene_gen.skybox] equirect {w}x{h} preset={getattr(args, 'preset', '') or '-'}",
            file=sys.stderr,
        )
        _zit_txt2img(
            prompt=prompt, width=w, height=h, output_path=out_path,
            loras=loras or None, negative=neg, seed=base_seed,
            timeout=args.timeout,
        )
        engine_outputs: dict[str, str] = {}
        if args.engine in ("godot", "both"):
            from engine_writers import write_godot_sky_tres
            tres = write_godot_sky_tres(
                out_dir / "skybox.tres",
                panorama_path=out_path,
            )
            engine_outputs["godot_tres"] = str(tres)
        if args.engine in ("unity", "both"):
            from engine_writers import write_unity_skybox_readme
            readme = write_unity_skybox_readme(out_dir, panorama_path=out_path)
            engine_outputs["unity_readme"] = str(readme)
        print(json.dumps({
            "ok": True, "subcommand": "skybox", "type": "equirect",
            "path": str(out_path), "engine_outputs": engine_outputs,
        }, indent=2))
        return

    # Cube: 6 faces. Use the same seed across faces so the global style
    # stays coherent even though the individual prompts differ.
    if args.type == "cube":
        face_paths: dict[str, Path] = {}
        size = args.size
        print(
            f"[scene_gen.skybox] cube {size}x{size} per face, 6 faces "
            f"preset={getattr(args, 'preset', '') or '-'}",
            file=sys.stderr,
        )
        for face, descriptor in CUBE_FACE_PROMPTS.items():
            prompt = f"skybox face, {descriptor}, no characters, no foreground, {args.prompt}"
            out_path = out_dir / f"{face}.png"
            _zit_txt2img(
                prompt=prompt, width=size, height=size, output_path=out_path,
                loras=loras or None, negative=neg, seed=base_seed,
                timeout=args.timeout,
            )
            face_paths[face] = out_path

        engine_outputs = {}
        if args.engine in ("godot", "both"):
            from engine_writers import write_godot_sky_tres
            tres = write_godot_sky_tres(
                out_dir / "skybox.tres",
                cube_faces=face_paths,
            )
            engine_outputs["godot_tres"] = str(tres)
        if args.engine in ("unity", "both"):
            from engine_writers import write_unity_skybox_readme
            readme = write_unity_skybox_readme(out_dir, cube_faces=face_paths)
            engine_outputs["unity_readme"] = str(readme)
        print(json.dumps({
            "ok": True, "subcommand": "skybox", "type": "cube",
            "faces": {k: str(v) for k, v in face_paths.items()},
            "engine_outputs": engine_outputs,
            "note": (
                "ZIT does not stitch true panoramas — face edges will have "
                "visible seams. Acceptable for stylized games; for "
                "photorealistic skies use a dedicated panorama model."
            ),
        }, indent=2))
        return

    raise SystemExit(f"--type must be 'equirect' or 'cube', got {args.type!r}")


# ---------------------------------------------------------------------------
# Subcommand: tileset
# ---------------------------------------------------------------------------

def cmd_tileset(args):
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    preset = _apply_preset_to_args(args)
    loras = _resolve_zit_style(getattr(args, "style", "") or "")

    cols, rows = _parse_grid(args.grid)
    if cols <= 0 or rows <= 0:
        raise SystemExit(f"--grid must be like '4x4', got {args.grid!r}")

    # Generate at the ATLAS resolution. ZIT's pixel-art LoRA + a
    # seamless-tiling prompt biases toward edge-aligned output; pixelize
    # post-process then snaps to the pixel grid.
    tile = args.tile
    # ZIT prefers powers-of-2 ish around 1024. Render at the next multiple
    # of 64 that's >= cols*tile (with a floor so we don't underrender).
    raw_w = max(512, cols * tile)
    raw_h = max(512, rows * tile)
    # Round up to multiples of 64 for ZIT-friendly latent sizes.
    render_w = ((raw_w + 63) // 64) * 64
    render_h = ((raw_h + 63) // 64) * 64

    cc = _imp_comfy()
    neg = cc.ZIT_NEGATIVE
    extra_neg = getattr(args, "preset_negative_extra", "") or ""
    if extra_neg:
        neg = f"{neg}, {extra_neg}".strip(", ")
    # Bias toward seamless tileable output.
    neg = f"{neg}, seams, edges that don't align, ragged borders"

    prompt = (
        f"pixel art seamless tile atlas, {cols}x{rows} grid of "
        f"edge-aligned game tiles, tileable, no visible seams, {args.prompt}"
    )

    print(
        f"[scene_gen.tileset] render={render_w}x{render_h} atlas={cols*tile}x{rows*tile} "
        f"tile={tile} grid={cols}x{rows} palette={args.palette or '-'}",
        file=sys.stderr,
    )

    import random
    seed = args.seed if args.seed != 0 else random.randint(0, 2**32 - 1)

    # Generate the full atlas at render resolution.
    atlas_path = output
    _zit_txt2img(
        prompt=prompt,
        width=render_w, height=render_h,
        output_path=atlas_path,
        loras=loras or None,
        negative=neg,
        seed=seed,
        timeout=args.timeout,
    )

    # Resize down to exact atlas size (cols*tile × rows*tile) via pixelize,
    # locking to the chosen palette.
    atlas_w = cols * tile
    atlas_h = rows * tile
    pt = _imp_pixel_toolkit()
    from PIL import Image
    img = Image.open(atlas_path).convert("RGBA")
    # First, resize to the atlas dimensions with nearest-neighbor.
    img = img.resize((atlas_w, atlas_h), Image.NEAREST)
    # Then apply palette quantization.
    palette = args.palette or (preset.get("suggested_palette") if preset else "") or ""
    if palette or args.colors:
        img = pt.reduce_palette(img, args.colors or 16, palette, args.dither)
    img.save(atlas_path)

    # Optional: also slice atlas into per-tile PNGs in a subdir.
    sliced_dir: Path | None = None
    if args.slice:
        sliced_dir = atlas_path.parent / f"{atlas_path.stem}_tiles"
        sliced_dir.mkdir(parents=True, exist_ok=True)
        atlas_img = Image.open(atlas_path).convert("RGBA")
        idx = 0
        for y in range(rows):
            for x in range(cols):
                box = (x * tile, y * tile, (x + 1) * tile, (y + 1) * tile)
                tile_img = atlas_img.crop(box)
                tile_path = sliced_dir / f"tile_{idx:03d}_{x}_{y}.png"
                tile_img.save(tile_path)
                idx += 1

    engine_outputs: dict[str, str] = {}
    if args.engine in ("godot", "both"):
        from engine_writers import write_godot_tileset_tres
        tres = write_godot_tileset_tres(
            atlas_path, atlas_path.with_suffix(".tres"),
            tile_size=tile, grid=(cols, rows),
        )
        engine_outputs["godot_tres"] = str(tres)
    if args.engine in ("unity", "both"):
        from engine_writers import write_unity_atlas_json
        unity = write_unity_atlas_json(
            atlas_path, atlas_path.with_suffix(".unity.json"),
            tile_size=tile, grid=(cols, rows),
        )
        engine_outputs["unity_json"] = str(unity)

    print(json.dumps({
        "ok": True, "subcommand": "tileset",
        "atlas": str(atlas_path),
        "tile_size": tile, "grid": [cols, rows],
        "palette": palette or None,
        "sliced_dir": str(sliced_dir) if sliced_dir else None,
        "engine_outputs": engine_outputs,
    }, indent=2))


def _parse_grid(s: str) -> tuple[int, int]:
    """Parse '4x4' or '6x4' → (cols, rows)."""
    try:
        a, b = s.lower().split("x")
        return int(a), int(b)
    except Exception:
        return 0, 0


# ---------------------------------------------------------------------------
# Subcommand: environment
# ---------------------------------------------------------------------------

def cmd_environment(args):
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    preset = _apply_preset_to_args(args)
    loras = _resolve_zit_style(getattr(args, "style", "") or "")

    env_prefix = ENVIRONMENT_PREFIXES.get(args.type, "")
    if not env_prefix and args.type != "custom":
        valid = sorted(ENVIRONMENT_PREFIXES.keys()) + ["custom"]
        raise SystemExit(f"--type must be one of {valid}, got {args.type!r}")

    full_prompt = f"{env_prefix}, {args.prompt}" if env_prefix else args.prompt

    # Aspect handling. Default cinematic 21:9 at 1792x768. User can override.
    w, h = _parse_aspect(args.aspect, base=args.size)

    cc = _imp_comfy()
    neg = cc.ZIT_NEGATIVE
    extra_neg = getattr(args, "preset_negative_extra", "") or ""
    if extra_neg:
        neg = f"{neg}, {extra_neg}".strip(", ")

    print(
        f"[scene_gen.environment] {args.type} {w}x{h} "
        f"preset={getattr(args, 'preset', '') or '-'} style={getattr(args, 'style', '') or '-'}"
        f"{' img2img' if args.reference else ''}",
        file=sys.stderr,
    )

    import random
    seed = args.seed if args.seed != 0 else random.randint(0, 2**32 - 1)

    if args.reference:
        _zit_img2img(
            prompt=full_prompt,
            reference_path=Path(args.reference),
            width=w, height=h,
            output_path=output,
            loras=loras or None,
            negative=neg,
            denoise=args.denoise,
            seed=seed,
            timeout=args.timeout,
        )
    else:
        _zit_txt2img(
            prompt=full_prompt,
            width=w, height=h,
            output_path=output,
            loras=loras or None,
            negative=neg,
            seed=seed,
            timeout=args.timeout,
        )

    if args.pixelize:
        target_w = args.target_width or (args._preset_resolution if preset else 0)
        if target_w > 0:
            _maybe_pixelize(
                output,
                target_w,
                int(target_w * h / w),
                args.palette,
                args.colors,
                args.dither,
            )

    print(json.dumps({
        "ok": True, "subcommand": "environment",
        "type": args.type,
        "path": str(output),
        "dimensions": [w, h],
    }, indent=2))


_ASPECT_TABLE = {
    "1:1":   (1.0,  1.0),
    "16:9":  (16.0, 9.0),
    "9:16":  (9.0,  16.0),
    "21:9":  (21.0, 9.0),
    "4:3":   (4.0,  3.0),
    "3:4":   (3.0,  4.0),
    "3:2":   (3.0,  2.0),
    "2:3":   (2.0,  3.0),
}


def _parse_aspect(aspect: str, base: int = 1024) -> tuple[int, int]:
    """Resolve an aspect string + base size to (width, height) rounded to /64.

    `base` is treated as the longer side. So '21:9' base=1024 → 1024 x 448
    rounded → 1024 x 448 (448 % 64 == 0).
    """
    aw, ah = _ASPECT_TABLE.get(aspect, (1.0, 1.0))
    if aw >= ah:
        w = base
        h = int(round(base * ah / aw))
    else:
        h = base
        w = int(round(base * aw / ah))
    # Round to nearest /64 for ZIT-friendly latent sizes.
    w = ((w + 31) // 64) * 64
    h = ((h + 31) // 64) * 64
    return max(64, w), max(64, h)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="scene-art: parallax / skybox / tileset / environment generators."
    )
    sub = parser.add_subparsers(required=True, dest="cmd")

    # parallax
    p = sub.add_parser("parallax", help="N consistent-style layered backgrounds")
    p.add_argument("--prompt", required=True, help="Subject / scene description")
    p.add_argument("--layers", type=int, default=5, choices=sorted(PARALLAX_LAYER_SETS.keys()))
    p.add_argument("--width", type=int, default=1920)
    p.add_argument("--height", type=int, default=1080)
    p.add_argument("-o", "--output", required=True, help="Output DIRECTORY for layer PNGs")
    p.add_argument("--style", default="", help="ZIT named style key from zit_styles.STYLES")
    p.add_argument("--preset", default="", help="Pixel-art preset name (see image-pipeline)")
    p.add_argument("--engine", default="both", choices=["godot", "unity", "both", "none"])
    p.add_argument("--seed", type=int, default=0, help="Base seed (0 = random)")
    p.add_argument("--vary-seed", action="store_true",
                   help="Use different seeds per layer (default: same seed for tight style)")
    p.add_argument("--no-bg-cut", action="store_true",
                   help="Skip foreground alpha-cut (default: bright pixels in last layer go transparent)")
    p.add_argument("--bg-cut-threshold", type=int, default=240, help="Brightness threshold for alpha-cut")
    p.add_argument("--pixelize", action="store_true")
    p.add_argument("--target-width", type=int, default=0)
    p.add_argument("--target-height", type=int, default=0)
    p.add_argument("--palette", default="")
    p.add_argument("--colors", type=int, default=0)
    p.add_argument("--dither", action="store_true")
    p.add_argument("--timeout", type=int, default=300)
    p.set_defaults(func=cmd_parallax)

    # skybox
    p = sub.add_parser("skybox", help="6 cube faces or 1 equirectangular panorama")
    p.add_argument("--prompt", required=True, help="Sky / environment description")
    p.add_argument("--type", default="cube", choices=["cube", "equirect"])
    p.add_argument("--size", type=int, default=1024, help="Face size (cube) or width (equirect; height = size/2)")
    p.add_argument("-o", "--output", required=True, help="Output DIRECTORY for face PNGs / equirect PNG")
    p.add_argument("--style", default="")
    p.add_argument("--preset", default="")
    p.add_argument("--engine", default="both", choices=["godot", "unity", "both", "none"])
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--timeout", type=int, default=600)
    p.set_defaults(func=cmd_skybox)

    # tileset
    p = sub.add_parser("tileset", help="Seamless tile atlas + grid slice")
    p.add_argument("--prompt", required=True, help="Tile content description")
    p.add_argument("--tile", type=int, default=32, help="Tile size in pixels (16/32/64)")
    p.add_argument("--grid", default="4x4", help="Grid dimensions like '4x4' or '6x4'")
    p.add_argument("-o", "--output", required=True, help="Output atlas PNG path")
    p.add_argument("--slice", action="store_true",
                   help="Also write per-tile PNGs to <output_stem>_tiles/")
    p.add_argument("--style", default="")
    p.add_argument("--preset", default="")
    p.add_argument("--engine", default="both", choices=["godot", "unity", "both", "none"])
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--palette", default="")
    p.add_argument("--colors", type=int, default=0)
    p.add_argument("--dither", action="store_true")
    p.add_argument("--timeout", type=int, default=300)
    p.set_defaults(func=cmd_tileset)

    # environment
    p = sub.add_parser("environment", help="Wide-aspect scene reference image")
    p.add_argument("--prompt", required=True)
    p.add_argument("--type", default="forest",
                   help=f"One of {sorted(ENVIRONMENT_PREFIXES.keys())} or 'custom' (prompt-only)")
    p.add_argument("--aspect", default="21:9", choices=list(_ASPECT_TABLE.keys()))
    p.add_argument("--size", type=int, default=1792, help="Longer-side resolution")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--style", default="")
    p.add_argument("--preset", default="")
    p.add_argument("--reference", default="", help="img2img against this image")
    p.add_argument("--denoise", type=float, default=0.55)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--pixelize", action="store_true")
    p.add_argument("--target-width", type=int, default=0)
    p.add_argument("--palette", default="")
    p.add_argument("--colors", type=int, default=0)
    p.add_argument("--dither", action="store_true")
    p.add_argument("--timeout", type=int, default=300)
    p.set_defaults(func=cmd_environment)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
