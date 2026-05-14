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


def _relative(target: Path, anchor: Path) -> str:
    try:
        return target.resolve().relative_to(anchor.resolve().parent).as_posix()
    except ValueError:
        return target.name
