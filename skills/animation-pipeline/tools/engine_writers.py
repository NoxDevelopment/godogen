"""Engine-specific writers for animation outputs (sprite sheets → Godot
AnimatedSprite2D .tscn, Unity SpriteAtlas + AnimationClip JSON).
"""

from __future__ import annotations

import json
from pathlib import Path


def write_godot_animatedsprite2d_tscn(
    sheet_path: Path,
    output_scene: Path,
    frame_size: tuple[int, int],
    frame_count: int,
    fps: int,
    anim_name: str,
    loop: bool,
) -> Path:
    """Write a Godot 4 scene with one AnimatedSprite2D + SpriteFrames resource.

    The SpriteFrames resource references `sheet_path` and slices it into
    `frame_count` AtlasTexture regions of `frame_size`. The animation plays
    at `fps`, loops based on `loop`.
    """
    fw, fh = frame_size
    rel = _relative(sheet_path, output_scene)
    lines: list[str] = []
    lines.append(f"[gd_scene load_steps={frame_count + 3} format=3]")
    lines.append("")
    lines.append(
        f'[ext_resource type="Texture2D" path="res://{rel}" id="sheet"]'
    )
    lines.append("")
    # Atlas regions (one sub-resource per frame).
    for i in range(frame_count):
        x = i * fw
        lines.append(f'[sub_resource type="AtlasTexture" id="atlas_{i}"]')
        lines.append(f'atlas = ExtResource("sheet")')
        lines.append(f"region = Rect2({x}, 0, {fw}, {fh})")
        lines.append("")
    # SpriteFrames resource referencing the atlases.
    lines.append('[sub_resource type="SpriteFrames" id="frames"]')
    lines.append("animations = [{")
    lines.append(f'"frames": [')
    for i in range(frame_count):
        lines.append(f'  {{"duration": 1.0, "texture": SubResource("atlas_{i}")}},')
    lines.append("],")
    lines.append(f'"loop": {str(loop).lower()},')
    lines.append(f'"name": &"{anim_name}",')
    lines.append(f'"speed": {float(fps)}.0,')
    lines.append("}]")
    lines.append("")
    # Root node + child AnimatedSprite2D.
    lines.append('[node name="Root" type="Node2D"]')
    lines.append("")
    lines.append('[node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="."]')
    lines.append('sprite_frames = SubResource("frames")')
    lines.append(f'animation = &"{anim_name}"')
    lines.append("autoplay = " + ("true" if loop else "false"))
    lines.append("")

    output_scene.parent.mkdir(parents=True, exist_ok=True)
    output_scene.write_text("\n".join(lines), encoding="utf-8")
    return output_scene


def write_unity_animation_json(
    sheet_path: Path,
    output_json: Path,
    frame_size: tuple[int, int],
    frame_count: int,
    fps: int,
    anim_name: str,
    loop: bool,
) -> Path:
    """Write Unity import + AnimationClip metadata for a sprite-sheet
    animation. User imports the PNG with Sprite Mode = Multiple, slices
    via Grid by Cell Size (frame_size), then creates an AnimationClip per
    this JSON's frame list.
    """
    fw, fh = frame_size
    frame_duration_s = 1.0 / float(fps)
    data = {
        "anim_name": anim_name,
        "sheet": sheet_path.name,
        "sheet_path": str(sheet_path),
        "frame_size_px": [fw, fh],
        "frame_count": frame_count,
        "fps": fps,
        "loop": bool(loop),
        "unity_import": {
            "sprite_mode": "Multiple",
            "pixels_per_unit": fw,
            "filter_mode": "Point (no filter)",
            "compression": "None",
            "slice_mode": "Grid by Cell Size",
            "pixel_size": f"{fw} x {fh}",
        },
        "animation_clip": {
            "frame_rate": float(fps),
            "wrap_mode": "Loop" if loop else "Once",
            "keyframes": [
                {
                    "time_s": round(i * frame_duration_s, 4),
                    "sprite_index": i,
                }
                for i in range(frame_count)
            ],
            "length_s": round(frame_count * frame_duration_s, 4),
        },
        "usage": (
            "1. Drop sheet into Unity Assets/. 2. Texture Importer: set per "
            "unity_import block above. 3. Create AnimationClip in editor; "
            "for each keyframe, set the SpriteRenderer.sprite to the "
            "matching sliced sprite at the listed time_s."
        ),
    }
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return output_json


def build_sheet_json(
    image_name: str,
    frame_size: tuple[int, int],
    frame_count: int,
    columns: int,
    fps: int,
    anim_name: str,
    loop: bool,
) -> dict:
    """The ENGINE-AGNOSTIC sprite-sheet descriptor — Aseprite/TexturePacker 'hash'
    format, the de-facto interchange consumed by Phaser 3, PixiJS, Cocos, web
    tools, and most importers. Frames are laid out row-major in a `columns`-wide
    grid; duration is per-frame in ms. Pure (no IO) so it's unit-testable.
    """
    fw, fh = frame_size
    cols = max(1, columns)
    rows = (frame_count + cols - 1) // cols
    duration_ms = round(1000.0 / float(fps)) if fps > 0 else 100
    frames: dict[str, dict] = {}
    for i in range(frame_count):
        col, row = i % cols, i // cols
        frames[f"{anim_name} {i}.png"] = {
            "frame": {"x": col * fw, "y": row * fh, "w": fw, "h": fh},
            "rotated": False,
            "trimmed": False,
            "spriteSourceSize": {"x": 0, "y": 0, "w": fw, "h": fh},
            "sourceSize": {"w": fw, "h": fh},
            "duration": duration_ms,
        }
    return {
        "frames": frames,
        "meta": {
            "app": "https://noxdev.studio",
            "version": "1.0",
            "image": image_name,
            "format": "RGBA8888",
            "size": {"w": cols * fw, "h": rows * fh},
            "scale": "1",
            "frameTags": [
                {
                    "name": anim_name,
                    "from": 0,
                    "to": max(0, frame_count - 1),
                    "direction": "forward" if loop else "forward",
                }
            ],
            "fps": fps,
            "loop": bool(loop),
        },
    }


def write_generic_sheet_json(
    sheet_path: Path,
    output_json: Path,
    frame_size: tuple[int, int],
    frame_count: int,
    columns: int,
    fps: int,
    anim_name: str,
    loop: bool,
) -> Path:
    """Write the engine-agnostic Aseprite/TexturePacker-hash sheet JSON next to
    the PNG sheet (the universal importer format — Phaser/Pixi/web/etc.)."""
    data = build_sheet_json(
        sheet_path.name, frame_size, frame_count, columns, fps, anim_name, loop
    )
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return output_json


def write_sprite_mp4(
    frame_paths: list[Path],
    output_mp4: Path,
    fps: int,
    upscale: int = 4,
) -> Path | None:
    """Best-effort MP4 of an animation cycle (for previews / marketing) via
    ffmpeg. Pixel-art-safe: nearest-neighbour upscale, yuv420p, even dims.
    Returns the path, or None if ffmpeg isn't available (GIF stays the portable
    fallback). Frames are fed by an explicit concat list so any naming works.
    """
    import shutil
    import subprocess
    import tempfile

    if shutil.which("ffmpeg") is None or not frame_paths:
        return None
    output_mp4.parent.mkdir(parents=True, exist_ok=True)
    hold = 1.0 / float(fps if fps > 0 else 8)
    # ffconcat demuxer: each frame held for `hold` seconds (last needs a repeat).
    lines = ["ffconcat version 1.0"]
    for p in frame_paths:
        lines.append(f"file '{p.as_posix()}'")
        lines.append(f"duration {hold:.4f}")
    lines.append(f"file '{frame_paths[-1].as_posix()}'")
    with tempfile.NamedTemporaryFile("w", suffix=".ffconcat", delete=False, encoding="utf-8") as fh:
        fh.write("\n".join(lines))
        concat_path = fh.name
    vf = f"scale=iw*{upscale}:ih*{upscale}:flags=neighbor,pad=ceil(iw/2)*2:ceil(ih/2)*2"
    try:
        subprocess.run(
            [
                "ffmpeg", "-y", "-safe", "0", "-f", "concat", "-i", concat_path,
                "-vf", vf, "-r", str(fps), "-pix_fmt", "yuv420p",
                "-movflags", "+faststart", str(output_mp4),
            ],
            check=True, capture_output=True,
        )
    except (subprocess.CalledProcessError, OSError):
        return None
    finally:
        try:
            Path(concat_path).unlink()
        except OSError:
            pass
    return output_mp4 if output_mp4.exists() else None


def _relative(target: Path, anchor: Path) -> str:
    try:
        return target.resolve().relative_to(anchor.resolve().parent).as_posix()
    except ValueError:
        return target.name
