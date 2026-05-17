"""Engine Export — emit Godot 4 / Unity scaffolds that bridge a finished
asset (sprite, spritesheet, tileset, audio, video) into engine-native
resources.

Subcommands
-----------
sprite-frames    Godot SpriteFrames .tres from a spritesheet PNG.
sprite-prefab    Unity SpriteRenderer prefab JSON (portable intermediate).
tileset-tres     Godot 4 TileSet .tres from a tileset atlas PNG.
audio-scene      Godot AudioStreamPlayer scene from a WAV/OGG.
video-scene      Godot VideoStreamPlayer scene from an MP4.
list             Enumerate available exports.

Pure text emission — no ComfyUI / Tripo3D / etc.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Path resolution helpers
# ---------------------------------------------------------------------------

def _resolve_res_path(absolute: Path) -> str:
    """Walk up from `absolute` looking for project.godot; return path
    relative to that dir using forward slashes (Godot's res:// form).
    Falls back to the basename if no project.godot is found within 8 levels."""
    cur = absolute.parent
    for _ in range(8):
        if (cur / "project.godot").exists():
            try:
                return absolute.resolve().relative_to(cur.resolve()).as_posix()
            except ValueError:
                break
        if cur.parent == cur:
            break
        cur = cur.parent
    return absolute.name


def _resolve_unity_path(absolute: Path) -> str:
    """Find an `Assets/` ancestor; return Unity-style relative path."""
    cur = absolute
    parts: list[str] = []
    for _ in range(10):
        parts.insert(0, cur.name)
        if cur.parent.name == "Assets" or cur.name == "Assets":
            parts.insert(0, "Assets") if cur.name != "Assets" else None
            return "/".join(parts) if cur.name != "Assets" else "Assets/" + "/".join(parts[1:])
        if cur.parent == cur:
            break
        cur = cur.parent
    return absolute.name


# ---------------------------------------------------------------------------
# Godot: SpriteFrames .tres
# ---------------------------------------------------------------------------

_TRES_HEADER = """[gd_resource type="SpriteFrames" load_steps={load_steps} format=3 uid="uid://{uid}"]

"""

_TRES_TEXTURE_BLOCK = """[ext_resource type="Texture2D" path="res://{texture_path}" id="{ext_id}"]

"""

_TRES_ATLAS_BLOCK = """[sub_resource type="AtlasTexture" id="atlas_{idx}"]
atlas = ExtResource("{ext_id}")
region = Rect2({x}, {y}, {w}, {h})

"""

_TRES_FRAMES_BLOCK = """[resource]
animations = [{{
"frames": [{frame_dicts}],
"loop": {loop},
"name": &"{name}",
"speed": {fps}
}}]
"""


def _stable_uid(text: str) -> str:
    # Simple deterministic-ish 12-char hash for the uid="uid://..." slot.
    import hashlib
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:12]


def emit_sprite_frames(asset: Path, frame_count: int, fps: float,
                        anim_name: str, output: Path,
                        loop: bool = True,
                        frame_w: int | None = None,
                        frame_h: int | None = None) -> None:
    """Emit a Godot 4 SpriteFrames .tres from a left-to-right spritesheet.

    Width/height per frame is inferred from the image and `frame_count` if not
    explicitly given.
    """
    try:
        from PIL import Image
        img = Image.open(asset)
        img_w, img_h = img.size
    except Exception:
        # Fall back to params; agent must supply --frame-w / --frame-h.
        if frame_w is None or frame_h is None:
            raise SystemExit(
                f"could not open {asset} to infer frame dimensions; "
                f"pass --frame-w and --frame-h explicitly")
        img_w = frame_w * frame_count
        img_h = frame_h

    if frame_w is None:
        frame_w = img_w // frame_count
    if frame_h is None:
        frame_h = img_h

    res_path = _resolve_res_path(asset)
    uid = _stable_uid(str(output))

    if anim_name == "":
        anim_name = "default"
    ext_id = "tex_1"

    atlas_blocks = []
    frame_dicts = []
    for i in range(frame_count):
        x = i * frame_w
        atlas_blocks.append(_TRES_ATLAS_BLOCK.format(
            idx=i, ext_id=ext_id, x=x, y=0, w=frame_w, h=frame_h,
        ))
        frame_dicts.append(
            '{\n"duration": 1.0,\n"texture": SubResource("atlas_' + str(i) + '")\n}'
        )

    text = (
        _TRES_HEADER.format(load_steps=frame_count + 2, uid=uid)
        + _TRES_TEXTURE_BLOCK.format(texture_path=res_path, ext_id=ext_id)
        + "".join(atlas_blocks)
        + _TRES_FRAMES_BLOCK.format(
            frame_dicts=", ".join(frame_dicts),
            loop=str(loop).lower(),
            name=anim_name,
            fps=fps,
        )
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")


def append_sprite_frames(asset: Path, frame_count: int, fps: float,
                         anim_name: str, output: Path,
                         loop: bool = True) -> None:
    """Add another animation to an existing SpriteFrames .tres.

    Strategy: parse the file's `animations = [...]` array, append a new entry,
    rewrite. We also need a new ext_resource for the new spritesheet.
    """
    if not output.exists():
        raise SystemExit(f"--append requires existing file {output}; emit first")

    text = output.read_text(encoding="utf-8")

    # Find the highest existing atlas index + ext_resource id
    atlas_ids = [int(m.group(1)) for m in re.finditer(r'id="atlas_(\d+)"', text)]
    next_atlas = max(atlas_ids) + 1 if atlas_ids else 0
    ext_ids = [int(m.group(1)) for m in re.finditer(r'id="tex_(\d+)"', text)]
    next_ext = max(ext_ids) + 1 if ext_ids else 1

    # Infer frame dims
    try:
        from PIL import Image
        img = Image.open(asset)
        img_w, img_h = img.size
    except Exception:
        raise SystemExit(f"could not open {asset} for size inference")

    frame_w = img_w // frame_count
    frame_h = img_h

    res_path = _resolve_res_path(asset)
    new_ext_block = _TRES_TEXTURE_BLOCK.format(texture_path=res_path,
                                                ext_id=f"tex_{next_ext}")
    new_atlas_blocks = []
    new_frame_dicts = []
    for i in range(frame_count):
        idx = next_atlas + i
        x = i * frame_w
        new_atlas_blocks.append(_TRES_ATLAS_BLOCK.format(
            idx=idx, ext_id=f"tex_{next_ext}", x=x, y=0, w=frame_w, h=frame_h,
        ))
        new_frame_dicts.append(
            '{\n"duration": 1.0,\n"texture": SubResource("atlas_' + str(idx) + '")\n}'
        )

    new_anim = (
        '{\n"frames": [' + ", ".join(new_frame_dicts) + '],\n'
        '"loop": ' + str(loop).lower() + ',\n'
        '"name": &"' + anim_name + '",\n'
        '"speed": ' + str(fps) + '\n}'
    )

    # Insert new ext_resource right before the first [sub_resource]
    text = re.sub(r'(\[sub_resource)', new_ext_block + r'\1', text, count=1)
    # Insert new atlas blocks right before [resource]
    text = re.sub(r'(\[resource\])', "".join(new_atlas_blocks) + r'\1', text, count=1)
    # Append to animations array
    text = re.sub(r'(animations = \[)(.*?)(\]\n)',
                  lambda m: m.group(1) + m.group(2).rstrip() + ", " + new_anim + m.group(3),
                  text, count=1, flags=re.DOTALL)

    # Update load_steps (best effort)
    def _bump_load_steps(m):
        n = int(m.group(1)) + frame_count + 1
        return f"load_steps={n}"
    text = re.sub(r"load_steps=(\d+)", _bump_load_steps, text, count=1)

    output.write_text(text, encoding="utf-8")


# ---------------------------------------------------------------------------
# Unity: SpriteRenderer prefab JSON
# ---------------------------------------------------------------------------

def emit_sprite_prefab_json(asset: Path, frame_count: int, fps: float,
                             anim_name: str, output: Path) -> None:
    try:
        from PIL import Image
        img = Image.open(asset)
        img_w, img_h = img.size
    except Exception:
        img_w = 64 * frame_count
        img_h = 64
    frame_w = img_w // frame_count
    frame_h = img_h
    unity_path = _resolve_unity_path(asset)

    prefab = {
        "format": "noxdev-creative-studio.unity.prefab.v1",
        "name": output.stem,
        "components": [
            {
                "type": "Transform",
                "position": [0, 0, 0],
                "rotation": [0, 0, 0],
                "scale": [1, 1, 1],
            },
            {
                "type": "SpriteRenderer",
                "sprite_atlas_path": unity_path,
                "sortingOrder": 0,
                "color": [1, 1, 1, 1],
            },
            {
                "type": "Animator",
                "clips": [{
                    "name": anim_name or "default",
                    "fps": fps,
                    "frames": [
                        {
                            "sprite_index": i,
                            "x": i * frame_w, "y": 0,
                            "width": frame_w, "height": frame_h,
                        }
                        for i in range(frame_count)
                    ],
                    "loop": True,
                }],
            },
        ],
        "import_note": (
            "Materialize this prefab in Unity with an Editor script that reads "
            "this JSON, creates a GameObject with SpriteRenderer + Animator, "
            "slices the atlas at sprite_atlas_path according to the frame "
            "rectangles, and saves as a .prefab in your project."
        ),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(prefab, indent=2), encoding="utf-8")


# ---------------------------------------------------------------------------
# Godot: TileSet .tres
# ---------------------------------------------------------------------------

def emit_tileset_tres(asset: Path, tile_size: int, grid: str, output: Path) -> None:
    if "x" not in grid:
        raise SystemExit("--grid must be like 4x4 or 6x4")
    cols_s, rows_s = grid.split("x", 1)
    cols, rows = int(cols_s), int(rows_s)
    res_path = _resolve_res_path(asset)
    uid = _stable_uid(str(output))

    lines = [
        f'[gd_resource type="TileSet" load_steps=2 format=3 uid="uid://{uid}"]',
        "",
        f'[ext_resource type="Texture2D" path="res://{res_path}" id="tex_1"]',
        "",
        '[sub_resource type="TileSetAtlasSource" id="atlas_1"]',
        'texture = ExtResource("tex_1")',
        f"texture_region_size = Vector2i({tile_size}, {tile_size})",
    ]
    # Mark every cell as present (0/0 = no auto-collision; user adds in editor)
    for r in range(rows):
        for c in range(cols):
            lines.append(f"{c}:{r}/0 = 0")
    lines.append("")
    lines.append("[resource]")
    lines.append("sources/0 = SubResource(\"atlas_1\")")
    lines.append("")

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")


# ---------------------------------------------------------------------------
# Godot: AudioStreamPlayer / AudioStreamPlayer3D .tscn
# ---------------------------------------------------------------------------

def emit_audio_scene(asset: Path, output: Path, volume_db: float = 0.0,
                     spatial: bool = False, autoplay: bool = False) -> None:
    res_path = _resolve_res_path(asset)
    uid = _stable_uid(str(output))
    node_type = "AudioStreamPlayer3D" if spatial else "AudioStreamPlayer"

    text = (
        f'[gd_scene load_steps=2 format=3 uid="uid://{uid}"]\n\n'
        f'[ext_resource type="AudioStream" path="res://{res_path}" id="1_stream"]\n\n'
        f'[node name="{asset.stem}" type="{node_type}"]\n'
        f'stream = ExtResource("1_stream")\n'
        f"volume_db = {volume_db}\n"
        f"autoplay = {str(autoplay).lower()}\n"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")


# ---------------------------------------------------------------------------
# Godot: VideoStreamPlayer .tscn
# ---------------------------------------------------------------------------

def emit_video_scene(asset: Path, output: Path, autoplay: bool = True,
                     loop: bool = False, expand: bool = True) -> None:
    res_path = _resolve_res_path(asset)
    uid = _stable_uid(str(output))

    text = (
        f'[gd_scene load_steps=2 format=3 uid="uid://{uid}"]\n\n'
        f'[ext_resource type="VideoStream" path="res://{res_path}" id="1_video"]\n\n'
        f'[node name="VideoRoot" type="Control"]\n'
        f"layout_mode = 3\n"
        f"anchors_preset = 15\n"
        f"anchor_right = 1.0\n"
        f"anchor_bottom = 1.0\n\n"
        f'[node name="VideoPlayer" type="VideoStreamPlayer" parent="."]\n'
        f"layout_mode = 1\n"
        f"anchors_preset = 15\n"
        f"anchor_right = 1.0\n"
        f"anchor_bottom = 1.0\n"
        f"expand = {str(expand).lower()}\n"
        f"autoplay = {str(autoplay).lower()}\n"
        f"loop = {str(loop).lower()}\n"
        f'stream = ExtResource("1_video")\n'
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def cmd_sprite_frames(args) -> None:
    asset = Path(args.asset)
    if not asset.exists():
        raise SystemExit(f"asset not found: {asset}")
    output = Path(args.output)
    if args.append:
        append_sprite_frames(asset, args.frame_count, args.fps,
                             args.animation_name, output, loop=not args.no_loop)
    else:
        emit_sprite_frames(asset, args.frame_count, args.fps,
                            args.animation_name, output,
                            loop=not args.no_loop,
                            frame_w=args.frame_w, frame_h=args.frame_h)
    print(json.dumps({
        "ok": True, "format": "godot.sprite_frames",
        "wrote": str(output), "appended": args.append,
        "animation": args.animation_name, "frames": args.frame_count,
    }, indent=2))


def cmd_sprite_prefab(args) -> None:
    asset = Path(args.asset)
    if not asset.exists():
        raise SystemExit(f"asset not found: {asset}")
    output = Path(args.output)
    emit_sprite_prefab_json(asset, args.frame_count, args.fps,
                             args.animation_name, output)
    print(json.dumps({"ok": True, "format": "unity.sprite_prefab.json",
                      "wrote": str(output)}, indent=2))


def cmd_tileset_tres(args) -> None:
    asset = Path(args.asset)
    if not asset.exists():
        raise SystemExit(f"asset not found: {asset}")
    output = Path(args.output)
    emit_tileset_tres(asset, args.tile_size, args.grid, output)
    print(json.dumps({"ok": True, "format": "godot.tileset_tres",
                      "wrote": str(output)}, indent=2))


def cmd_audio_scene(args) -> None:
    asset = Path(args.asset)
    if not asset.exists():
        raise SystemExit(f"asset not found: {asset}")
    output = Path(args.output)
    emit_audio_scene(asset, output, volume_db=args.volume_db,
                     spatial=args.spatial, autoplay=args.autoplay)
    print(json.dumps({"ok": True, "format": "godot.audio_scene",
                      "wrote": str(output), "spatial": args.spatial}, indent=2))


def cmd_video_scene(args) -> None:
    asset = Path(args.asset)
    if not asset.exists():
        raise SystemExit(f"asset not found: {asset}")
    output = Path(args.output)
    emit_video_scene(asset, output, autoplay=not args.no_autoplay,
                     loop=args.loop, expand=not args.no_expand)
    print(json.dumps({"ok": True, "format": "godot.video_scene",
                      "wrote": str(output)}, indent=2))


def cmd_list(_args) -> None:
    print(json.dumps({"exports": [
        {"name": "sprite-frames", "engine": "godot",
         "out": ".tres", "input": "spritesheet PNG"},
        {"name": "sprite-prefab", "engine": "unity",
         "out": ".prefab.json", "input": "spritesheet PNG"},
        {"name": "tileset-tres", "engine": "godot",
         "out": ".tres", "input": "tileset atlas PNG"},
        {"name": "audio-scene", "engine": "godot",
         "out": ".tscn", "input": "WAV/OGG"},
        {"name": "video-scene", "engine": "godot",
         "out": ".tscn", "input": "MP4"},
    ]}, indent=2))


def main():
    parser = argparse.ArgumentParser(
        description="engine-export: emit Godot/Unity scaffolds for finished assets")
    sub = parser.add_subparsers(required=True, dest="cmd")

    p = sub.add_parser("sprite-frames", help="Godot SpriteFrames .tres from spritesheet")
    p.add_argument("--asset", required=True)
    p.add_argument("--frame-count", type=int, required=True)
    p.add_argument("--fps", type=float, default=12.0)
    p.add_argument("--animation-name", default="default")
    p.add_argument("--append", action="store_true",
                   help="Add another animation to an existing .tres")
    p.add_argument("--no-loop", action="store_true")
    p.add_argument("--frame-w", type=int, help="Override frame width (default: infer from image)")
    p.add_argument("--frame-h", type=int, help="Override frame height")
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_sprite_frames)

    p = sub.add_parser("sprite-prefab", help="Unity prefab JSON from spritesheet")
    p.add_argument("--asset", required=True)
    p.add_argument("--frame-count", type=int, required=True)
    p.add_argument("--fps", type=float, default=12.0)
    p.add_argument("--animation-name", default="default")
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_sprite_prefab)

    p = sub.add_parser("tileset-tres", help="Godot 4 TileSet .tres from tileset atlas")
    p.add_argument("--asset", required=True)
    p.add_argument("--tile-size", type=int, default=32)
    p.add_argument("--grid", required=True, help="e.g. 4x4 or 6x4")
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_tileset_tres)

    p = sub.add_parser("audio-scene", help="Godot AudioStreamPlayer scene")
    p.add_argument("--asset", required=True)
    p.add_argument("--volume-db", type=float, default=0.0)
    p.add_argument("--spatial", action="store_true",
                   help="Emit AudioStreamPlayer3D instead of AudioStreamPlayer")
    p.add_argument("--autoplay", action="store_true")
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_audio_scene)

    p = sub.add_parser("video-scene", help="Godot VideoStreamPlayer scene")
    p.add_argument("--asset", required=True)
    p.add_argument("--no-autoplay", action="store_true")
    p.add_argument("--loop", action="store_true")
    p.add_argument("--no-expand", action="store_true")
    p.add_argument("-o", "--output", required=True)
    p.set_defaults(func=cmd_video_scene)

    p = sub.add_parser("list", help="List available exports")
    p.set_defaults(func=cmd_list)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
