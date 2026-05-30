"""Character Sheet — generate a 3x3 grid of poses for one character in a
single ComfyUI/ZIT call, then post-process into 9 individual pose PNGs.

Subcommands
-----------
generate    Generate sheet + slice + tight-crop + pad + save 9 sprites
            (and optionally record to an asset-manifest).
list-poses  Print the default pose catalog and the phrases used per pose.

Composes image-pipeline's `comfyui_client` + `zit_styles` + `pixel_art_toolkit`
primitives — does NOT re-implement ComfyUI plumbing.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import subprocess
import sys
import time
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
SKILL_ROOT = THIS_DIR.parent
SKILLS_ROOT = SKILL_ROOT.parent
IMAGE_PIPELINE_TOOLS = SKILLS_ROOT / "image-pipeline" / "tools"
ASSET_MANIFEST_TOOLS = SKILLS_ROOT / "asset-manifest" / "tools"

for p in (IMAGE_PIPELINE_TOOLS, THIS_DIR):
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))

# Hard runtime deps: ZIT primitives + Pillow
try:
    from comfyui_client import (
        build_zit_txt2img_workflow, queue_prompt, poll_completion,
        get_output_images, download_image, COMFYUI_URL,
    )
    from zit_styles import STYLES, DEFAULT_STYLE_KEY
except ImportError as e:
    print(f"ERROR: character-sheet requires image-pipeline tools on sys.path: {e}",
          file=sys.stderr)
    sys.exit(2)

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow is required (pip install pillow)", file=sys.stderr)
    sys.exit(2)


# ---------------------------------------------------------------------------
# Pose catalog
# ---------------------------------------------------------------------------

# Each pose maps to a short phrase the model gets in the prompt. Phrases are
# action-focused and silhouette-distinct so the 9 cells don't look identical.
DEFAULT_POSES: dict[str, str] = {
    "idle":       "standing relaxed, arms at sides, slight contrapposto",
    "walk_a":     "mid-stride walk, left foot forward, opposite arm swung forward",
    "walk_b":     "mid-stride walk, right foot forward, opposite arm swung forward",
    "attack":     "lunging forward with weapon raised, aggressive stance",
    "hurt":       "knocked back, body arched, one arm flailing, pained expression",
    "death":      "collapsed on the ground, lifeless, on side or back",
    "jump_up":    "leaping upward, knees tucked, arms thrown up",
    "jump_down":  "descending mid-air, legs extended for landing",
    "cast":       "casting a spell, both arms raised, magical glow at fingertips",
}

DEFAULT_POSE_ORDER = list(DEFAULT_POSES.keys())


# ---------------------------------------------------------------------------
# Prompt builder
# ---------------------------------------------------------------------------

def _build_prompt(character: str, poses: list[str], pose_phrases: list[str],
                  bg_hex: str) -> str:
    if len(poses) > 9:
        raise SystemExit(f"max 9 poses (got {len(poses)})")
    while len(poses) < 9:
        poses.append("idle")
        pose_phrases.append(DEFAULT_POSES["idle"])
    pose_list = ", ".join(f"({i+1}) {ph}" for i, ph in enumerate(pose_phrases))
    return (
        f"A 3x3 grid sprite sheet of {character}. The sheet has 9 cells arranged in 3 rows "
        f"and 3 columns. From left to right, top to bottom, the cells show: {pose_list}. "
        f"All cells show the same character, full-body, same lighting, same scale, same "
        f"outline thickness. The background of EVERY cell is solid {bg_hex.lower()} (a flat "
        f"single color with no gradients, no texture). Pixel art, consistent palette across "
        f"all cells. The character is centered in each cell with comfortable headroom."
    )


# ---------------------------------------------------------------------------
# ZIT workflow runner
# ---------------------------------------------------------------------------

def _style_loras(style_key: str) -> list:
    style = STYLES.get(style_key)
    if style is None:
        raise SystemExit(f"unknown style '{style_key}'. "
                         f"Run image-pipeline asset_gen.py list-styles to see options.")
    return list(getattr(style, "loras", []) or [])


def _lora_to_dict(entry) -> dict:
    # LoraEntry NamedTuple/dataclass or dict
    if isinstance(entry, dict):
        return {
            "name": entry.get("name") or entry.get("filename", ""),
            "strength_model": float(entry.get("strength_model", 0.8)),
            "strength_clip": float(entry.get("strength_clip", 0.8)),
        }
    return {
        "name": getattr(entry, "filename", ""),
        "strength_model": float(getattr(entry, "strength_model", 0.8)),
        "strength_clip": float(getattr(entry, "strength_clip", 0.8)),
    }


def _parse_loras_arg(raw: str, default_strength: float = 0.8) -> list[dict]:
    """Parse a --loras CSV of ``name[:strength]`` into LoRA dicts."""
    out: list[dict] = []
    for part in (raw or "").split(","):
        part = part.strip()
        if not part:
            continue
        name, _, strength_s = part.partition(":")
        name = name.strip()
        if not name:
            continue
        try:
            strength = float(strength_s) if strength_s.strip() else default_strength
        except ValueError:
            strength = default_strength
        out.append({"name": name, "strength_model": strength, "strength_clip": strength})
    return out


def _generate_sheet_png(prompt: str, output_path: Path, sheet_size: int,
                        style_key: str, seed: int,
                        explicit_loras: list[dict] | None = None) -> Path:
    """Run a single ZIT txt2img workflow and download the result to output_path.

    An explicit LoRA stack (from --loras) overrides the style's LoRAs."""
    loras = explicit_loras if explicit_loras else [_lora_to_dict(e) for e in _style_loras(style_key)]
    workflow = build_zit_txt2img_workflow(
        prompt=prompt,
        loras=loras,
        width=sheet_size, height=sheet_size,
        seed=seed,
    )
    prompt_id = queue_prompt(workflow, COMFYUI_URL)
    result = poll_completion(prompt_id, COMFYUI_URL)
    images = get_output_images(result)
    if not images:
        raise RuntimeError("ComfyUI returned no images")
    return download_image(images[0], output_path, COMFYUI_URL)


# ---------------------------------------------------------------------------
# Post-processing
# ---------------------------------------------------------------------------

def _hex_to_rgb(hex_str: str) -> tuple[int, int, int]:
    s = hex_str.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


BG_NAMES = {
    "magenta": "#FF00FF",
    "green":   "#00FF00",
    "cyan":    "#00FFFF",
}


def _key_background(img: Image.Image, bg_rgb: tuple[int, int, int],
                    tolerance: int) -> Image.Image:
    """Replace any pixel within `tolerance` of bg_rgb with full transparency."""
    img = img.convert("RGBA")
    pixels = img.load()
    tol_sq = tolerance ** 2
    bg_r, bg_g, bg_b = bg_rgb
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            dr, dg, db = r - bg_r, g - bg_g, b - bg_b
            if dr*dr + dg*dg + db*db <= tol_sq:
                pixels[x, y] = (0, 0, 0, 0)
    return img


def _slice_3x3(img: Image.Image) -> list[Image.Image]:
    w, h = img.size
    cw, ch = w // 3, h // 3
    cells: list[Image.Image] = []
    for row in range(3):
        for col in range(3):
            box = (col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)
            cells.append(img.crop(box))
    return cells


def _tight_crop(img: Image.Image) -> Image.Image:
    """Crop to the alpha bbox. Returns the original image if alpha is all opaque
    (no transparent border) — defensive against pre-keyed input."""
    if img.mode != "RGBA":
        return img
    bbox = img.getbbox()
    if bbox is None:
        # All-transparent — return a 1x1 transparent stub rather than crashing
        return Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    return img.crop(bbox)


def _pad_to_aspect(img: Image.Image, target_w: int, target_h: int) -> Image.Image:
    """Pad with transparent pixels so img fits target_w x target_h centered."""
    if img.size == (target_w, target_h):
        return img
    new = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    iw, ih = img.size
    # Scale down if the sprite is bigger than the target box (preserve aspect).
    if iw > target_w or ih > target_h:
        scale = min(target_w / iw, target_h / ih)
        new_w = max(1, int(iw * scale))
        new_h = max(1, int(ih * scale))
        img = img.resize((new_w, new_h), Image.NEAREST)
        iw, ih = img.size
    x = (target_w - iw) // 2
    y = (target_h - ih) // 2
    new.paste(img, (x, y), img)
    return new


def _count_distinct_blobs(img: Image.Image, min_area: int = 32) -> int:
    """Cheap blob count via 4-connected flood fill on the alpha channel.
    Returns the number of connected non-transparent regions of at least
    `min_area` pixels. Used to validate the 9-cell prompt actually produced
    9 sprites and not, e.g., 3 sprites + 6 magenta voids."""
    if img.mode != "RGBA":
        img = img.convert("RGBA")
    w, h = img.size
    pixels = img.load()
    visited = bytearray(w * h)
    blobs = 0
    for sy in range(h):
        for sx in range(w):
            if visited[sy * w + sx]:
                continue
            if pixels[sx, sy][3] == 0:
                visited[sy * w + sx] = 1
                continue
            # BFS flood fill (avoid recursion-depth issues on large images)
            stack = [(sx, sy)]
            area = 0
            while stack:
                cx, cy = stack.pop()
                idx = cy * w + cx
                if visited[idx]:
                    continue
                visited[idx] = 1
                if pixels[cx, cy][3] == 0:
                    continue
                area += 1
                if cx > 0: stack.append((cx - 1, cy))
                if cx + 1 < w: stack.append((cx + 1, cy))
                if cy > 0: stack.append((cx, cy - 1))
                if cy + 1 < h: stack.append((cx, cy + 1))
            if area >= min_area:
                blobs += 1
    return blobs


# ---------------------------------------------------------------------------
# Label derivation
# ---------------------------------------------------------------------------

def _character_label(character: str) -> str:
    """Derive a filename-safe short label from the character description."""
    # Strip articles + take first 1-2 meaningful words
    words = re.findall(r"[a-zA-Z][a-zA-Z0-9]+", character.lower())
    stopwords = {"a", "an", "the", "with", "in", "of", "and"}
    words = [w for w in words if w not in stopwords]
    if not words:
        return "character"
    return "_".join(words[:2])


# ---------------------------------------------------------------------------
# Manifest recording
# ---------------------------------------------------------------------------

def _record_to_manifest(manifest_path: Path, sprite_paths: list[tuple[str, Path]],
                        character: str, style: str, seed: int, sheet_path: Path) -> None:
    """Call asset-manifest's CLI for each pose sprite."""
    cli = ASSET_MANIFEST_TOOLS / "manifest.py"
    if not cli.exists():
        print(f"[character-sheet] asset-manifest CLI not found at {cli} — skipping record",
              file=sys.stderr)
        return
    char_label = _character_label(character)
    for pose, path in sprite_paths:
        cmd = [
            sys.executable, str(cli), "add",
            "--manifest", str(manifest_path),
            "--path", str(path),
            "--kind", "sprite",
            "--provider", "character-sheet.zit",
            "--labels", f"{char_label},{pose}",
            "--param", f"prompt_character={character}",
            "--param", f"style={style}",
            "--param", f"seed={seed}",
            "--param", f"pose={pose}",
            "--param", f"source_sheet={sheet_path.name}",
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            print(f"[character-sheet] manifest add failed for {path.name}: "
                  f"{proc.stderr.strip()[:200]}", file=sys.stderr)


# ---------------------------------------------------------------------------
# Main generate flow
# ---------------------------------------------------------------------------

def cmd_generate(args) -> None:
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # 1. Resolve poses
    pose_keys: list[str] = []
    if args.poses:
        pose_keys = [p.strip() for p in args.poses.split(",") if p.strip()]
    else:
        pose_keys = list(DEFAULT_POSE_ORDER)
    if len(pose_keys) > 9:
        raise SystemExit(f"--poses gave {len(pose_keys)} entries; max 9")
    pose_phrases = []
    for pk in pose_keys:
        phrase = DEFAULT_POSES.get(pk)
        if phrase is None:
            # Allow custom pose keys — use the key itself as the phrase
            phrase = pk.replace("_", " ")
        pose_phrases.append(phrase)

    # 2. Pad with idle if user gave <9
    while len(pose_keys) < 9:
        pose_keys.append("idle")
        pose_phrases.append(DEFAULT_POSES["idle"])

    # 3. Resolve background sentinel
    bg_name = args.bg.lower()
    bg_hex = BG_NAMES.get(bg_name, args.bg)
    if not bg_hex.startswith("#") or len(bg_hex) != 7:
        raise SystemExit(f"--bg must be a named color {list(BG_NAMES)} or a #RRGGBB hex")
    bg_rgb = _hex_to_rgb(bg_hex)

    # 4. Resolve aspect
    if ":" not in args.aspect:
        raise SystemExit("--aspect must be like 2:3 or 1:1")
    aw, ah = args.aspect.split(":")
    aw, ah = int(aw), int(ah)
    target_w = args.cell_size
    target_h = int(round(args.cell_size * ah / aw))
    if ah > aw:
        # Vertical aspect — cell width drives, height extends
        target_w = args.cell_size
        target_h = int(round(args.cell_size * ah / aw))
    else:
        # Horizontal aspect — cell height drives
        target_h = args.cell_size
        target_w = int(round(args.cell_size * aw / ah))

    # 5. Build prompt
    prompt = _build_prompt(args.character, pose_keys[:9], pose_phrases[:9], bg_hex)
    sheet_size = args.cell_size * 3

    # 6. Generate (with retries for blob-count validation)
    sheet_path = output_dir / "_raw_sheet.png"
    seed = args.seed if args.seed is not None else random.randint(1, 2**31 - 1)
    last_blob_count = 0
    attempt = 0
    while True:
        attempt += 1
        print(f"[character-sheet] attempt {attempt}: generating 3x3 sheet "
              f"(seed={seed}, size={sheet_size}x{sheet_size})", file=sys.stderr)
        try:
            _generate_sheet_png(
                prompt, sheet_path, sheet_size, args.style, seed,
                explicit_loras=_parse_loras_arg(getattr(args, "loras", "") or ""),
            )
        except Exception as e:
            raise SystemExit(f"sheet generation failed: {type(e).__name__}: {e}")
        # Validate
        sheet = Image.open(sheet_path)
        keyed = _key_background(sheet, bg_rgb, args.tolerance)
        last_blob_count = _count_distinct_blobs(keyed, min_area=max(8, args.cell_size // 4))
        print(f"[character-sheet] detected {last_blob_count} distinct sprite blob(s)",
              file=sys.stderr)
        if last_blob_count >= 9:
            break
        if attempt > args.retries:
            print(f"[character-sheet] WARNING: only {last_blob_count}/9 blobs after "
                  f"{attempt} attempts. Proceeding anyway — empty cells will save as "
                  f"1x1 transparent stubs.", file=sys.stderr)
            break
        seed = random.randint(1, 2**31 - 1)

    # 7. Save the keyed sheet
    keyed_path = output_dir / "_sheet_keyed.png"
    keyed.save(keyed_path)

    # 8. Slice + crop + pad + save each pose
    cells = _slice_3x3(keyed)
    char_label = _character_label(args.character)
    sprite_paths: list[tuple[str, Path]] = []
    for i, cell in enumerate(cells):
        if i >= len(pose_keys):
            break
        cropped = _tight_crop(cell)
        padded = _pad_to_aspect(cropped, target_w, target_h)
        path = output_dir / f"{char_label}_{pose_keys[i]}.png"
        padded.save(path)
        sprite_paths.append((pose_keys[i], path))

    # 9. Optional: delete raw sheet
    if not args.keep_raw:
        sheet_path.unlink(missing_ok=True)

    # 10. Optional: record to manifest
    if args.manifest:
        _record_to_manifest(Path(args.manifest), sprite_paths,
                            character=args.character, style=args.style,
                            seed=seed, sheet_path=sheet_path)

    print(json.dumps({
        "ok": True,
        "sheet": str(sheet_path) if args.keep_raw else None,
        "keyed_sheet": str(keyed_path),
        "sprites": [{"pose": p, "path": str(pth)} for p, pth in sprite_paths],
        "sprite_count": len(sprite_paths),
        "blob_count_detected": last_blob_count,
        "seed_used": seed,
        "attempts": attempt,
        "style": args.style,
        "cell_size": args.cell_size,
        "padded_size": [target_w, target_h],
    }, indent=2))


def cmd_list_poses(_args) -> None:
    print(json.dumps({"poses": [{"key": k, "phrase": v} for k, v in DEFAULT_POSES.items()]},
                     indent=2))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="character-sheet: 3x3 pose-grid generator (single-call → 9 sprites)")
    sub = parser.add_subparsers(required=True, dest="cmd")

    p = sub.add_parser("generate", help="Generate sheet + slice + save pose PNGs")
    p.add_argument("--character", required=True,
                   help="Character description prompt (silhouette, gear, colors, vibe)")
    p.add_argument("--poses", default="",
                   help="Comma-separated pose keys (max 9). Default: full 9-pose catalog.")
    p.add_argument("--loras", default="",
                   help="Explicit LoRA stack: CSV of name[:strength]; overrides the style's LoRAs.")
    p.add_argument("--style", default=DEFAULT_STYLE_KEY,
                   help=f"image-pipeline style key (default: {DEFAULT_STYLE_KEY})")
    p.add_argument("--cell-size", type=int, default=64,
                   help="Output sprite cell size in pixels (default: 64)")
    p.add_argument("--aspect", default="2:3",
                   help="Output aspect ratio (default: 2:3)")
    p.add_argument("--bg", default="magenta",
                   help="Background sentinel color name or #RRGGBB (default: magenta)")
    p.add_argument("--tolerance", type=int, default=25,
                   help="Background-removal color tolerance 0-100 (default: 25)")
    p.add_argument("--retries", type=int, default=2,
                   help="Retries if <9 distinct blobs detected (default: 2)")
    p.add_argument("--output-dir", required=True)
    p.add_argument("--manifest", help="Path to assets/manifest.json to record into")
    p.add_argument("--keep-raw", dest="keep_raw", action="store_true", default=True)
    p.add_argument("--no-keep-raw", dest="keep_raw", action="store_false")
    p.add_argument("--seed", type=int, help="Override random seed")
    p.set_defaults(func=cmd_generate)

    p = sub.add_parser("list-poses", help="Print default 9-pose catalog")
    p.set_defaults(func=cmd_list_poses)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
