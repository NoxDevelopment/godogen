"""Animation Pipeline — sprite animation cycles, frame interpolation, sheets.

Generates temporally-phased animation cycles (idle / walk / attack / etc.)
by running one ZIT txt2img per frame with a shared seed and a phase-specific
prompt suffix. Style stays consistent (shared seed + style); pose changes
per frame (phase prompt). The pipeline then assembles frames into a sheet
and emits engine companion files (Godot AnimatedSprite2D .tscn, Unity
animation clip JSON).

Subcommands
-----------
cycle         Generate a full N-frame cycle for a named action (walk, idle,
              attack, etc.) at a chosen direction, assemble to sheet.

interpolate   Generate intermediate frames between two key-pose images via
              img2img at progressively varied denoise.

sheet         Assemble existing per-frame PNGs into a sprite sheet + emit
              engine companion files. Use when frames came from another
              source (hand-drawn, Aseprite export, etc).

All commands reuse image-pipeline primitives (comfyui_client.build_zit_*,
pixel_art_toolkit.make_spritesheet / save_gif) and accept --preset / --style.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
SKILL_ROOT = THIS_DIR.parent
SKILLS_ROOT = SKILL_ROOT.parent
IMAGE_PIPELINE_TOOLS = SKILLS_ROOT / "image-pipeline" / "tools"
IMAGE_PIPELINE_PRESETS = SKILLS_ROOT / "image-pipeline" / "presets"

for p in (THIS_DIR, IMAGE_PIPELINE_TOOLS, IMAGE_PIPELINE_PRESETS):
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))


# ---------------------------------------------------------------------------
# Cycle catalog — per-frame phase descriptors for known actions
# ---------------------------------------------------------------------------

# Each cycle key maps to a list of (phase_name, phase_descriptor) tuples that
# get appended to the user's prompt frame-by-frame. The list length sets the
# "natural" frame count for that action; --frames can override (cycle is
# resampled by simple modulo).

CYCLE_PHASES: dict[str, list[tuple[str, str]]] = {
    "idle": [
        ("rest_a",    "neutral standing pose, arms relaxed, slight chest rise"),
        ("rest_b",    "neutral standing pose, head tilts slightly, chest hold"),
        ("rest_c",    "neutral standing pose, arms relaxed, slight chest fall"),
        ("rest_d",    "neutral standing pose, weight shifts subtly to other foot"),
    ],
    "walk": [
        ("contact_r", "walk cycle, right foot forward planted, left foot lifting"),
        ("recoil_r",  "walk cycle, right foot planted under hips, left knee lifted"),
        ("pass_r",    "walk cycle, right foot lifting at toe, left leg passing"),
        ("high_r",    "walk cycle, right leg in air mid-step, left leg planted"),
        ("contact_l", "walk cycle, left foot forward planted, right foot lifting"),
        ("recoil_l",  "walk cycle, left foot planted under hips, right knee lifted"),
        ("pass_l",    "walk cycle, left foot lifting at toe, right leg passing"),
        ("high_l",    "walk cycle, left leg in air mid-step, right leg planted"),
    ],
    "run": [
        ("strike_r",  "running gait, right foot striking ground, full extension"),
        ("recoil_r",  "running gait, right foot supporting weight, body compressed"),
        ("flight_r",  "running gait, airborne, both feet off ground, arms swung"),
        ("strike_l",  "running gait, left foot striking ground, full extension"),
        ("recoil_l",  "running gait, left foot supporting weight, body compressed"),
        ("flight_l",  "running gait, airborne, both feet off ground, arms swung"),
    ],
    "attack": [
        ("wind_up",   "combat pose, weapon drawn back behind body, body coiled"),
        ("commit",    "combat pose, body uncoiling, weapon mid-swing, momentum"),
        ("strike",    "combat pose, weapon at full extension, impact moment"),
        ("recover",   "combat pose, weapon following through past target"),
        ("reset",     "combat pose, weapon returning to ready, body resetting"),
    ],
    "hurt": [
        ("impact",    "recoil pose, body bent backward from impact, arms thrown wide"),
        ("stagger",   "recoil pose, off-balance step backward, arms flailing"),
        ("recover",   "recoil pose, returning to upright, dazed expression"),
    ],
    "death": [
        ("hit",       "death animation, struck pose, body arching backward"),
        ("falling",   "death animation, knees buckling, leaning forward"),
        ("collapse",  "death animation, body crumpling sideways toward ground"),
        ("rest",      "death animation, lying still on ground, limbs splayed"),
    ],
    "jump": [
        ("crouch",    "jump start, knees deeply bent, body compressed, arms swinging back"),
        ("launch",    "jump mid-launch, legs extending, arms swinging forward and up"),
        ("apex",      "jump peak, fully airborne, legs slightly tucked, arms raised"),
        ("descent",   "jump descending, legs preparing for landing, arms forward for balance"),
        ("land",      "jump landing, knees bent absorbing impact, body compressing"),
    ],
    "cast": [
        ("gather",    "spellcast pose, arms drawn inward, energy gathering at hands"),
        ("focus",     "spellcast pose, hands raised, head tilted up, glowing fingertips"),
        ("release",   "spellcast pose, hands thrust forward, energy bursting outward"),
        ("recover",   "spellcast pose, arms lowered, depleted stance"),
    ],
}


DIRECTION_DESCRIPTORS = {
    "right":  "facing right, side view, profile silhouette",
    "left":   "facing left, side view, profile silhouette",
    "down":   "facing camera, 3/4 front view, walking toward viewer",
    "up":     "facing away, 3/4 back view, walking away from viewer",
    "front":  "facing camera, front view",
    "back":   "facing away, back view",
}


# ---------------------------------------------------------------------------
# Lazy imports
# ---------------------------------------------------------------------------

def _imp_comfy():
    import comfyui_client as cc
    return cc


def _imp_pixel_toolkit():
    import pixel_art_toolkit as pt
    return pt


def _load_pixel_presets():
    cached = getattr(_load_pixel_presets, "_cache", None)
    if cached is not None:
        return cached
    import pixel_art_presets as p
    _load_pixel_presets._cache = p.PIXEL_STYLE_PRESETS
    return p.PIXEL_STYLE_PRESETS


def _resolve_zit_style(style_key: str) -> list[dict]:
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
        {"name": le.name, "strength_model": le.strength_model, "strength_clip": le.strength_clip}
        for le in spec.loras
    ]


def _apply_preset(args) -> dict | None:
    name = getattr(args, "preset", "") or ""
    if not name:
        return None
    presets = _load_pixel_presets()
    if name not in presets:
        raise SystemExit(
            f"animation_gen: unknown --preset '{name}'. "
            f"Run 'asset_gen.py list-presets' (image-pipeline) to see options."
        )
    p = presets[name]
    prefix = (p.get("prompt_prefix") or "").rstrip(", ")
    if prefix and getattr(args, "prompt", ""):
        args.prompt = f"{prefix}, {args.prompt}".strip(", ")
    if not getattr(args, "palette", "") and p.get("suggested_palette"):
        args.palette = p["suggested_palette"]
    args._preset_negative_extra = (p.get("negative_extra") or "").strip()
    args._preset_resolution = int(p.get("suggested_resolution") or 0)
    return p


# ---------------------------------------------------------------------------
# Frame generation
# ---------------------------------------------------------------------------

def _zit_frame(
    prompt: str,
    width: int,
    height: int,
    output_path: Path,
    loras: list[dict],
    negative: str,
    seed: int,
    timeout: int = 300,
) -> Path:
    cc = _imp_comfy()
    base_url = os.environ.get("COMFYUI_URL", cc.COMFYUI_URL)
    if not cc.is_available(base_url):
        raise RuntimeError(f"ComfyUI not reachable at {base_url}")
    workflow = cc.build_zit_txt2img_workflow(
        prompt=prompt, negative=negative, loras=loras,
        width=width, height=height,
        steps=cc.ZIT_STEPS, cfg=cc.ZIT_CFG, seed=seed,
    )
    prompt_id = cc.queue_prompt(workflow, base_url)
    history = cc.poll_completion(prompt_id, base_url, timeout=timeout)
    images = cc.get_output_images(history)
    if not images:
        raise RuntimeError("ComfyUI returned no images")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    return cc.download_image(images[0], output_path, base_url)


def _zit_img2img_frame(
    prompt: str,
    reference: Path,
    width: int,
    height: int,
    output_path: Path,
    loras: list[dict],
    negative: str,
    denoise: float,
    seed: int,
    timeout: int = 300,
) -> Path:
    cc = _imp_comfy()
    base_url = os.environ.get("COMFYUI_URL", cc.COMFYUI_URL)
    if not cc.is_available(base_url):
        raise RuntimeError(f"ComfyUI not reachable at {base_url}")
    ref_filename = cc.upload_image(reference, base_url)
    workflow = cc.build_zit_img2img_workflow(
        image_filename=ref_filename, prompt=prompt, negative=negative,
        loras=loras, denoise=denoise,
        steps=cc.ZIT_STEPS, cfg=cc.ZIT_CFG, seed=seed,
    )
    prompt_id = cc.queue_prompt(workflow, base_url)
    history = cc.poll_completion(prompt_id, base_url, timeout=timeout)
    images = cc.get_output_images(history)
    if not images:
        raise RuntimeError("ComfyUI returned no images")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    return cc.download_image(images[0], output_path, base_url)


# ---------------------------------------------------------------------------
# Subcommand: cycle
# ---------------------------------------------------------------------------

def cmd_cycle(args):
    if args.type not in CYCLE_PHASES:
        valid = sorted(CYCLE_PHASES.keys())
        raise SystemExit(f"--type must be one of {valid}, got {args.type!r}")
    if args.direction not in DIRECTION_DESCRIPTORS:
        valid = sorted(DIRECTION_DESCRIPTORS.keys())
        raise SystemExit(f"--direction must be one of {valid}, got {args.direction!r}")

    _apply_preset(args)
    loras = _resolve_zit_style(getattr(args, "style", "") or "")
    if not loras:
        cc = _imp_comfy()
        loras = [{"name": cc.ZIT_PIXEL_LORA, "strength_model": 0.8, "strength_clip": 0.8}]

    cc = _imp_comfy()
    negative = cc.ZIT_NEGATIVE
    extra = getattr(args, "_preset_negative_extra", "") or ""
    if extra:
        negative = f"{negative}, {extra}".strip(", ")

    # Negative bias for animation frames: avoid spurious background bleed.
    negative = f"{negative}, busy background, motion blur, ghosting"

    phases = CYCLE_PHASES[args.type]
    # Resample phases to requested frame count (preserves cycle ordering).
    n = args.frames if args.frames > 0 else len(phases)
    indices = [i * len(phases) // n for i in range(n)]
    direction_desc = DIRECTION_DESCRIPTORS[args.direction]

    seed = args.seed if args.seed != 0 else random.randint(0, 2**32 - 1)

    output_sheet = Path(args.output)
    frames_dir = output_sheet.parent / f"{output_sheet.stem}_frames"
    frames_dir.mkdir(parents=True, exist_ok=True)

    print(
        f"[animation_gen.cycle] {args.type} {args.direction} {n} frames "
        f"@ {args.frame_size}px, seed={seed}",
        file=sys.stderr,
    )

    # Generate frame 0 as the reference, then img2img-from-reference for the
    # remaining frames so style stays locked. Reference frame uses the first
    # phase's descriptor.
    frame_paths: list[Path] = []
    ref_phase_name, ref_phase_desc = phases[indices[0]]
    ref_prompt = (
        f"pixel art sprite, {args.prompt}, {direction_desc}, {ref_phase_desc}, "
        "transparent background, clean silhouette, game sprite, pixel-perfect edges"
    )
    ref_path = frames_dir / "frame_000.png"
    _zit_frame(
        ref_prompt, args.frame_size, args.frame_size, ref_path,
        loras, negative, seed, args.timeout,
    )
    frame_paths.append(ref_path)

    for idx in range(1, n):
        phase_name, phase_desc = phases[indices[idx]]
        frame_prompt = (
            f"pixel art sprite, {args.prompt}, {direction_desc}, {phase_desc}, "
            "transparent background, same character, same style, "
            "clean silhouette, game sprite"
        )
        frame_path = frames_dir / f"frame_{idx:03d}.png"
        if args.use_reference:
            # img2img against frame 0 → tight character + style continuity.
            _zit_img2img_frame(
                frame_prompt, ref_path, args.frame_size, args.frame_size,
                frame_path, loras, negative,
                denoise=args.denoise, seed=seed + idx,
                timeout=args.timeout,
            )
        else:
            # Same seed, different phase prompt → looser but faster.
            _zit_frame(
                frame_prompt, args.frame_size, args.frame_size, frame_path,
                loras, negative, seed, args.timeout,
            )
        frame_paths.append(frame_path)

    # Pixelize each frame to enforce pixel-grid alignment + palette.
    pt = _imp_pixel_toolkit()
    from PIL import Image
    if args.target_size > 0 or args.palette:
        target = args.target_size or args.frame_size
        for fp in frame_paths:
            img = Image.open(fp).convert("RGBA")
            img = pt.pixelize(img, target, args.colors, args.palette, args.dither)
            img.save(fp)

    # Assemble sprite sheet (1 row × N columns).
    frames = [Image.open(fp).convert("RGBA") for fp in frame_paths]
    sheet = pt.make_spritesheet(frames, columns=n)
    output_sheet.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_sheet)

    # Optional GIF preview.
    gif_path = None
    if args.gif:
        gif_path = output_sheet.with_suffix(".gif")
        pt.save_gif(frames, gif_path, args.fps)

    # Engine companions
    engine_outputs: dict[str, str] = {}
    frame_w, frame_h = frames[0].size
    if args.engine in ("godot", "both"):
        from engine_writers import write_godot_animatedsprite2d_tscn
        tscn = write_godot_animatedsprite2d_tscn(
            output_sheet,
            output_sheet.with_suffix(".tscn"),
            frame_size=(frame_w, frame_h),
            frame_count=n,
            fps=args.fps,
            anim_name=f"{args.type}_{args.direction}",
            loop=args.type in {"idle", "walk", "run"},
        )
        engine_outputs["godot_tscn"] = str(tscn)
    if args.engine in ("unity", "both"):
        from engine_writers import write_unity_animation_json
        unity = write_unity_animation_json(
            output_sheet,
            output_sheet.with_suffix(".unity.json"),
            frame_size=(frame_w, frame_h),
            frame_count=n,
            fps=args.fps,
            anim_name=f"{args.type}_{args.direction}",
            loop=args.type in {"idle", "walk", "run"},
        )
        engine_outputs["unity_json"] = str(unity)

    # If not keeping individual frames, remove the frames dir.
    if not args.keep_frames:
        for fp in frame_paths:
            try:
                fp.unlink()
            except OSError:
                pass
        try:
            frames_dir.rmdir()
        except OSError:
            pass

    print(json.dumps({
        "ok": True, "subcommand": "cycle",
        "action": args.type, "direction": args.direction,
        "sheet": str(output_sheet),
        "frame_count": n, "frame_size": [frame_w, frame_h],
        "fps": args.fps,
        "gif": str(gif_path) if gif_path else None,
        "frames_dir": str(frames_dir) if args.keep_frames else None,
        "engine_outputs": engine_outputs,
    }, indent=2))


# ---------------------------------------------------------------------------
# Subcommand: interpolate
# ---------------------------------------------------------------------------

def cmd_interpolate(args):
    """Generate N intermediate frames between two key-pose images via img2img.

    Uses a denoise curve that ramps from low (close to start) through high
    (mid) back to low (close to end). The mid-curve denoise param controls
    how much creative latitude the model has at the midpoint.
    """
    _apply_preset(args)
    loras = _resolve_zit_style(getattr(args, "style", "") or "")
    if not loras:
        cc = _imp_comfy()
        loras = [{"name": cc.ZIT_PIXEL_LORA, "strength_model": 0.8, "strength_clip": 0.8}]

    cc = _imp_comfy()
    negative = cc.ZIT_NEGATIVE

    start = Path(args.start)
    end = Path(args.end)
    if not start.exists():
        raise SystemExit(f"--start not found: {start}")
    if not end.exists():
        raise SystemExit(f"--end not found: {end}")

    n = args.frames
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Frame 0 = start, frame N+1 = end (copied verbatim). Intermediates
    # 1..N use img2img against start with progressively more "in transition"
    # bias in the prompt and a triangular denoise curve.
    from shutil import copyfile
    f0 = output_dir / "frame_000.png"
    fN = output_dir / f"frame_{n + 1:03d}.png"
    copyfile(start, f0)
    copyfile(end, fN)

    seed = args.seed if args.seed != 0 else random.randint(0, 2**32 - 1)
    print(f"[animation_gen.interpolate] {n} intermediate frames, seed={seed}", file=sys.stderr)

    written = [f0]
    for i in range(1, n + 1):
        t = i / (n + 1)  # 0 < t < 1
        # Triangular denoise: low near endpoints, peak in middle.
        denoise = args.denoise_min + (args.denoise_max - args.denoise_min) * (1 - abs(2 * t - 1))
        # Half-way switch reference image from start to end so motion
        # blends from both endpoints.
        ref = start if t < 0.5 else end
        prompt = f"in-between animation frame, mid-motion, {args.prompt}"
        out = output_dir / f"frame_{i:03d}.png"
        _zit_img2img_frame(
            prompt, ref, args.frame_size, args.frame_size, out,
            loras, negative, denoise=denoise, seed=seed + i,
            timeout=args.timeout,
        )
        written.append(out)
    written.append(fN)

    print(json.dumps({
        "ok": True, "subcommand": "interpolate",
        "frame_dir": str(output_dir),
        "frame_count": len(written),
        "denoise_range": [args.denoise_min, args.denoise_max],
    }, indent=2))


# ---------------------------------------------------------------------------
# Subcommand: sheet
# ---------------------------------------------------------------------------

def cmd_sheet(args):
    """Assemble existing per-frame PNGs into a sprite sheet + engine sidecars."""
    pt = _imp_pixel_toolkit()
    from PIL import Image

    frame_dir = Path(args.input_dir)
    if not frame_dir.exists():
        raise SystemExit(f"--input-dir not found: {frame_dir}")

    frame_paths = sorted(frame_dir.glob("*.png"))
    if not frame_paths:
        raise SystemExit(f"No PNG frames in {frame_dir}")
    frames = [Image.open(fp).convert("RGBA") for fp in frame_paths]
    n = len(frames)
    fw, fh = frames[0].size

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet = pt.make_spritesheet(frames, columns=args.columns or n)
    sheet.save(output)

    gif_path = None
    if args.gif:
        gif_path = output.with_suffix(".gif")
        pt.save_gif(frames, gif_path, args.fps)

    engine_outputs: dict[str, str] = {}
    if args.engine in ("godot", "both"):
        from engine_writers import write_godot_animatedsprite2d_tscn
        tscn = write_godot_animatedsprite2d_tscn(
            output, output.with_suffix(".tscn"),
            frame_size=(fw, fh), frame_count=n, fps=args.fps,
            anim_name=args.anim_name, loop=args.loop,
        )
        engine_outputs["godot_tscn"] = str(tscn)
    if args.engine in ("unity", "both"):
        from engine_writers import write_unity_animation_json
        unity = write_unity_animation_json(
            output, output.with_suffix(".unity.json"),
            frame_size=(fw, fh), frame_count=n, fps=args.fps,
            anim_name=args.anim_name, loop=args.loop,
        )
        engine_outputs["unity_json"] = str(unity)

    print(json.dumps({
        "ok": True, "subcommand": "sheet",
        "sheet": str(output), "frame_count": n, "frame_size": [fw, fh],
        "fps": args.fps, "loop": args.loop,
        "gif": str(gif_path) if gif_path else None,
        "engine_outputs": engine_outputs,
    }, indent=2))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="animation-pipeline: cycles / interpolate / sheet")
    sub = parser.add_subparsers(required=True, dest="cmd")

    p = sub.add_parser("cycle", help="Generate a full N-frame animation cycle")
    p.add_argument("--type", required=True, choices=sorted(CYCLE_PHASES.keys()))
    p.add_argument("--direction", default="right", choices=sorted(DIRECTION_DESCRIPTORS.keys()))
    p.add_argument("--prompt", required=True, help="Character / subject description")
    p.add_argument("--frames", type=int, default=0, help="Frame count (0 = use cycle's natural length)")
    p.add_argument("--frame-size", type=int, default=512)
    p.add_argument("-o", "--output", required=True, help="Output sprite-sheet PNG path")
    p.add_argument("--style", default="")
    p.add_argument("--preset", default="")
    p.add_argument("--engine", default="both", choices=["godot", "unity", "both", "none"])
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--use-reference", action="store_true",
                   help="Generate frame 0 via txt2img, then img2img remaining "
                        "frames against frame 0 (better character continuity, "
                        "slightly slower)")
    p.add_argument("--denoise", type=float, default=0.45,
                   help="img2img denoise when --use-reference is set")
    p.add_argument("--keep-frames", action="store_true", help="Keep per-frame PNGs in _frames/ dir")
    p.add_argument("--fps", type=int, default=8)
    p.add_argument("--gif", action="store_true", help="Also save a preview .gif next to the sheet")
    p.add_argument("--target-size", type=int, default=0, help="Pixelize target dim (0 = no resize)")
    p.add_argument("--palette", default="")
    p.add_argument("--colors", type=int, default=0)
    p.add_argument("--dither", action="store_true")
    p.add_argument("--timeout", type=int, default=300)
    p.set_defaults(func=cmd_cycle)

    p = sub.add_parser("interpolate", help="Generate N in-between frames")
    p.add_argument("--start", required=True, help="Start key-pose PNG path")
    p.add_argument("--end", required=True, help="End key-pose PNG path")
    p.add_argument("--frames", type=int, default=4, help="Intermediate frame count")
    p.add_argument("--prompt", default="character mid-motion", help="In-between bias prompt")
    p.add_argument("--frame-size", type=int, default=512)
    p.add_argument("-o", "--output", required=True, help="Output DIRECTORY for frames")
    p.add_argument("--style", default="")
    p.add_argument("--preset", default="")
    p.add_argument("--denoise-min", type=float, default=0.30)
    p.add_argument("--denoise-max", type=float, default=0.55)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--timeout", type=int, default=300)
    p.set_defaults(func=cmd_interpolate)

    p = sub.add_parser("sheet", help="Assemble existing per-frame PNGs into a sprite sheet")
    p.add_argument("--input-dir", required=True)
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--columns", type=int, default=0, help="0 = one row of N columns")
    p.add_argument("--anim-name", default="default")
    p.add_argument("--fps", type=int, default=8)
    p.add_argument("--loop", action="store_true")
    p.add_argument("--gif", action="store_true")
    p.add_argument("--engine", default="both", choices=["godot", "unity", "both", "none"])
    p.set_defaults(func=cmd_sheet)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
