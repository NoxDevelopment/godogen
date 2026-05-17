"""UI Elements — curated wrappers around image-pipeline for UI assets:
buttons (with normal/hover/pressed states), icons, healthbars, panels,
cursors, frames.

Subcommands
-----------
button     Button sprite + auto-derived hover + pressed variants.
icon       Single 64x64 (or custom) icon, transparent BG.
healthbar  Matched frame + fill pair.
panel      Square 9-slice-ready panel.
cursor     32x32 mouse cursor.
frame      Decorative rectangular frame.

Shells out to image-pipeline asset_gen.py for the actual rendering;
post-processes brightness/saturation for button states.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image, ImageEnhance
except ImportError:
    print("ERROR: ui-elements requires Pillow (pip install pillow)", file=sys.stderr)
    sys.exit(2)


THIS_DIR = Path(__file__).resolve().parent
SKILLS_ROOT = THIS_DIR.parent.parent
IMAGE_CLI = SKILLS_ROOT / "image-pipeline" / "tools" / "asset_gen.py"


# ---------------------------------------------------------------------------
# Prompt builders
# ---------------------------------------------------------------------------

BUTTON_SHAPE_PROMPTS = {
    "rounded": "button with smoothly rounded corners (~20% corner radius)",
    "sharp":   "rectangular button with sharp 90-degree corners",
    "pill":    "pill-shaped button with fully rounded short ends",
    "beveled": "rectangular button with chamfered 45-degree bevels at each corner",
    "glass":   "glossy translucent glass button with subtle inner highlight",
}

CURSOR_KIND_PROMPTS = {
    "arrow":     "classic mouse cursor arrow pointing up-left, sharp tip",
    "hand":      "pointing hand cursor, index finger extended forward",
    "crosshair": "precise crosshair targeting cursor, plus-sign shape with hollow center",
    "move":      "four-way directional arrow cursor (up/down/left/right)",
    "text":      "I-beam text cursor",
}

CURSOR_HOTSPOTS = {
    "arrow":     [1, 1],
    "hand":      [10, 4],
    "crosshair": [16, 16],
    "move":      [16, 16],
    "text":      [16, 16],
}


def _run_image_pipeline(prompt: str, output: Path, style: str,
                         size: int, aspect: str, asset_type: str = "ui",
                         seed: int | None = None) -> tuple[int, str]:
    """Call image-pipeline asset_gen.py image. Returns (returncode, stderr)."""
    # Map pixel size to image-pipeline's --size enum (closest match)
    pipeline_size = "512"
    if size > 1500:
        pipeline_size = "2K"
    elif size > 700:
        pipeline_size = "1K"
    elif size > 350:
        pipeline_size = "512"
    args = [
        sys.executable, str(IMAGE_CLI), "image",
        "--type", asset_type,
        "--prompt", prompt,
        "--style", style,
        "--size", pipeline_size,
        "--aspect-ratio", aspect,
        "-o", str(output),
    ]
    if seed is not None:
        args += ["--seed", str(seed)]
    proc = subprocess.run(args, capture_output=True, text=True)
    return proc.returncode, proc.stderr


def _post_resize(p: Path, w: int, h: int) -> None:
    img = Image.open(p).convert("RGBA")
    if img.size != (w, h):
        img = img.resize((w, h), Image.NEAREST)
        img.save(p)


def _aspect_string(w: int, h: int) -> str:
    """Closest image-pipeline aspect choice for w:h."""
    options = {"1:1": 1.0, "16:9": 16/9, "9:16": 9/16, "3:2": 1.5,
               "2:3": 2/3, "4:3": 4/3, "3:4": 3/4, "4:5": 0.8, "5:4": 1.25,
               "21:9": 21/9}
    target = w / h
    best = min(options.items(), key=lambda kv: abs(kv[1] - target))
    return best[0]


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_button(args) -> None:
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    label_clause = "" if args.no_label else f' with the text "{args.label}" clearly readable centered on the button'
    shape_clause = BUTTON_SHAPE_PROMPTS.get(args.shape, args.shape)
    color_clause = f" in {args.color}" if args.color else ""
    prompt = (
        f"A clean game UI {shape_clause}{color_clause}{label_clause}, "
        f"centered on a fully transparent background, no scenery, no border, "
        f"isolated UI sprite, sharp edges."
    )

    aspect = _aspect_string(args.width, args.height)
    safe = "".join(c if c.isalnum() else "_" for c in (args.label or "btn").lower())[:32].strip("_")
    normal_path = out_dir / f"button_{safe}_normal.png"

    rc, err = _run_image_pipeline(prompt, normal_path, style=args.style,
                                    size=max(args.width, args.height),
                                    aspect=aspect, seed=args.seed)
    if rc != 0:
        raise SystemExit(f"image-pipeline failed: {err.strip()[-300:]}")
    if not normal_path.exists():
        raise SystemExit("image-pipeline returned no file")
    _post_resize(normal_path, args.width, args.height)

    # Derive hover + pressed by adjusting brightness/saturation/contrast
    base = Image.open(normal_path).convert("RGBA")
    hover = ImageEnhance.Brightness(base).enhance(1.18)
    hover = ImageEnhance.Color(hover).enhance(1.10)
    hover_path = out_dir / f"button_{safe}_hover.png"
    hover.save(hover_path)

    pressed = ImageEnhance.Brightness(base).enhance(0.88)
    pressed = ImageEnhance.Color(pressed).enhance(0.92)
    # 1-px vertical shift on pressed
    shifted = Image.new("RGBA", pressed.size, (0, 0, 0, 0))
    shifted.paste(pressed, (0, 1), pressed)
    pressed_path = out_dir / f"button_{safe}_pressed.png"
    shifted.save(pressed_path)

    print(json.dumps({
        "ok": True, "outputs": [str(normal_path), str(hover_path), str(pressed_path)],
        "label": args.label, "shape": args.shape,
        "size": [args.width, args.height], "style": args.style,
    }, indent=2))


def cmd_icon(args) -> None:
    out = Path(args.output)
    prompt = (
        f"A single game UI icon depicting {args.concept}, "
        f"centered on a fully transparent background, tightly cropped, "
        f"crisp silhouette, no scenery, no text, no border."
    )
    rc, err = _run_image_pipeline(prompt, out, style=args.style,
                                    size=args.size, aspect="1:1",
                                    asset_type="icon", seed=args.seed)
    if rc != 0:
        raise SystemExit(f"image-pipeline failed: {err.strip()[-300:]}")
    if not out.exists():
        raise SystemExit("image-pipeline returned no file")
    _post_resize(out, args.size, args.size)
    print(json.dumps({"ok": True, "wrote": str(out),
                      "concept": args.concept, "size": args.size}, indent=2))


def cmd_healthbar(args) -> None:
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    aspect = _aspect_string(args.width, args.height)

    frame_prompt = (
        f"A horizontal game UI healthbar frame in {args.style} style, "
        f"empty hollow center (transparent fill area), decorative border only, "
        f"centered on a fully transparent background, isolated UI sprite."
    )
    frame_path = out_dir / "healthbar_frame.png"
    rc, err = _run_image_pipeline(frame_prompt, frame_path, style=args.style,
                                    size=max(args.width, args.height),
                                    aspect=aspect, seed=args.seed)
    if rc != 0:
        raise SystemExit(f"frame gen failed: {err.strip()[-300:]}")
    _post_resize(frame_path, args.width, args.height)

    fill_prompt = (
        f"A solid horizontal red-to-green health bar gradient fill, "
        f"flat color (no border, no frame, no decoration), "
        f"fills its entire rectangle edge-to-edge, "
        f"matching the {args.style} aesthetic, on a transparent background."
    )
    fill_path = out_dir / "healthbar_fill.png"
    rc, err = _run_image_pipeline(fill_prompt, fill_path, style=args.style,
                                    size=max(args.width, args.height),
                                    aspect=aspect,
                                    seed=(args.seed + 1) if args.seed is not None else None)
    if rc != 0:
        raise SystemExit(f"fill gen failed: {err.strip()[-300:]}")
    _post_resize(fill_path, args.width, args.height)

    print(json.dumps({
        "ok": True, "outputs": [str(frame_path), str(fill_path)],
        "size": [args.width, args.height], "style": args.style,
    }, indent=2))


def cmd_panel(args) -> None:
    out = Path(args.output)
    prompt = (
        f"A square UI panel background in {args.style} style, "
        f"thin clean border, subtle gradient or texture interior, "
        f"centered on a fully transparent background, "
        f"designed for 9-slice scaling (uniform border, plain center)."
    )
    rc, err = _run_image_pipeline(prompt, out, style=args.style,
                                    size=args.size, aspect="1:1",
                                    asset_type="ui", seed=args.seed)
    if rc != 0:
        raise SystemExit(f"image-pipeline failed: {err.strip()[-300:]}")
    _post_resize(out, args.size, args.size)
    margin = args.size // 4
    print(json.dumps({
        "ok": True, "wrote": str(out), "size": args.size,
        "godot_nine_patch": {
            "patch_margin_left": margin, "patch_margin_right": margin,
            "patch_margin_top": margin, "patch_margin_bottom": margin,
        },
    }, indent=2))


def cmd_cursor(args) -> None:
    if args.kind not in CURSOR_KIND_PROMPTS:
        raise SystemExit(f"unknown cursor kind '{args.kind}'. Options: {list(CURSOR_KIND_PROMPTS)}")
    out = Path(args.output)
    prompt = (
        f"A {CURSOR_KIND_PROMPTS[args.kind]} in {args.style} style, "
        f"centered on a fully transparent background, isolated UI sprite, "
        f"crisp edges, 32x32 pixel resolution."
    )
    rc, err = _run_image_pipeline(prompt, out, style=args.style,
                                    size=512, aspect="1:1",
                                    asset_type="icon", seed=args.seed)
    if rc != 0:
        raise SystemExit(f"image-pipeline failed: {err.strip()[-300:]}")
    _post_resize(out, 32, 32)
    print(json.dumps({
        "ok": True, "wrote": str(out), "kind": args.kind,
        "size": 32, "hotspot": CURSOR_HOTSPOTS[args.kind],
    }, indent=2))


def cmd_frame(args) -> None:
    out = Path(args.output)
    aspect = _aspect_string(args.width, args.height)
    prompt = (
        f"A decorative rectangular UI frame border in {args.style} style, "
        f"hollow transparent center (so it can frame other content), "
        f"only the decorative border art visible, "
        f"centered on a fully transparent background, isolated UI sprite."
    )
    rc, err = _run_image_pipeline(prompt, out, style=args.style,
                                    size=max(args.width, args.height),
                                    aspect=aspect, asset_type="ui",
                                    seed=args.seed)
    if rc != 0:
        raise SystemExit(f"image-pipeline failed: {err.strip()[-300:]}")
    _post_resize(out, args.width, args.height)
    print(json.dumps({"ok": True, "wrote": str(out),
                      "size": [args.width, args.height]}, indent=2))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="ui-elements: curated UI sprite generators (buttons/icons/healthbars/panels/cursors/frames)")
    sub = parser.add_subparsers(required=True, dest="cmd")

    p = sub.add_parser("button", help="Button + auto hover + pressed variants")
    p.add_argument("--label", default="Click", help='Button label text (or pass --no-label)')
    p.add_argument("--no-label", action="store_true")
    p.add_argument("--shape", default="rounded", choices=list(BUTTON_SHAPE_PROMPTS))
    p.add_argument("--color", default="", help='Tint hint, e.g. "#3a7dff" or "warm orange"')
    p.add_argument("--style", default="default-pixel")
    p.add_argument("--width", type=int, default=192)
    p.add_argument("--height", type=int, default=48)
    p.add_argument("--seed", type=int)
    p.add_argument("--output-dir", required=True)
    p.set_defaults(func=cmd_button)

    p = sub.add_parser("icon", help="Single icon (transparent BG)")
    p.add_argument("--concept", required=True)
    p.add_argument("--style", default="default-pixel")
    p.add_argument("--size", type=int, default=64)
    p.add_argument("--seed", type=int)
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_icon)

    p = sub.add_parser("healthbar", help="Matched frame + fill pair")
    p.add_argument("--style", default="default-pixel")
    p.add_argument("--width", type=int, default=256)
    p.add_argument("--height", type=int, default=32)
    p.add_argument("--seed", type=int)
    p.add_argument("--output-dir", required=True)
    p.set_defaults(func=cmd_healthbar)

    p = sub.add_parser("panel", help="Square 9-slice-ready panel")
    p.add_argument("--style", default="default-pixel")
    p.add_argument("--size", type=int, default=128)
    p.add_argument("--seed", type=int)
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_panel)

    p = sub.add_parser("cursor", help="32x32 mouse cursor")
    p.add_argument("--kind", default="arrow", choices=list(CURSOR_KIND_PROMPTS))
    p.add_argument("--style", default="default-pixel")
    p.add_argument("--seed", type=int)
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_cursor)

    p = sub.add_parser("frame", help="Decorative rectangular frame (hollow center)")
    p.add_argument("--style", default="default-pixel")
    p.add_argument("--width", type=int, default=320)
    p.add_argument("--height", type=int, default=240)
    p.add_argument("--seed", type=int)
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_frame)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
