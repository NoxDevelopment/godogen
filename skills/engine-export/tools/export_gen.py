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
scaffold-binder  Emit the stable-ID resolver + an empty per-project manifest.
list             Enumerate available exports.

Pure text emission — no ComfyUI / Tripo3D / etc.

Stable-ID asset binding (Studio live-wiring, STANDARDS "Studio integration &
live asset wiring")
-------------------------------------------------------------------------------
Every Godot emitter accepts ``--slot-id <id>``. In **slot mode** the emitted
scene references its asset by a STABLE SLOT ID resolved at load through a small
``NoxAssetBinder`` resolver + a per-project ``assets.manifest.json``
(id -> current ``res://`` path + provenance) — **no hardcoded ``res://`` asset
path is baked into the .tscn/.tres**. Swapping/replacing an asset from the
Studio = editing one manifest entry, with zero scene edits. A sensible default
binding (the asset you passed) is written into the manifest so the project still
runs out of the box. Without ``--slot-id`` the legacy hardcoded-path emission is
kept for quick standalone use.
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
# Studio asset-binding: stable-ID indirection (the AssetBinder pattern)
#
# Instead of baking a res:// asset path into every emitted .tscn/.tres, slot
# mode makes the scene reference a stable SLOT ID and resolve the real asset at
# load through NoxAssetBinder + a per-project assets.manifest.json. This is what
# lets Jesus drop-in/replace an asset from the Studio (edit one manifest entry)
# without any scene edit. Modeled on the ff-gamebook AssetBinder contract.
# ---------------------------------------------------------------------------

BINDER_DIR = "scripts/nox_asset_binding"  # under the Godot project root
BINDER_SCRIPT = "nox_asset_binder.gd"
SLOT_SCRIPTS = {
    "animated_sprite": "slot_animated_sprite.gd",
    "audio": "slot_audio_player.gd",
    "audio_3d": "slot_audio_player_3d.gd",
    "video": "slot_video_player.gd",
    "tilemap": "slot_tilemap_layer.gd",
}

# --- the resolver (a static class; no autoload registration needed) ---------
_NOX_ASSET_BINDER_GD = r'''class_name NoxAssetBinder
extends RefCounted
## Stable-ID asset resolver (emitted by godogen engine-export).
##
## Scene scripts resolve each asset SLOT by a stable id through the per-project
## manifest (res://assets.manifest.json) instead of baking a res:// path into
## the scene. Swap/replace an asset from the Studio = edit that slot's `file`
## in the manifest; no scene edits, next boot binds the new asset. This is the
## STANDARDS "Studio integration & live asset wiring" contract.
##
##     var tex := NoxAssetBinder.get_texture("sprite/knight")
##     var sfx := NoxAssetBinder.get_stream("audio/jump")
##
## Optional: register as an autoload named "NoxAssetBinder" if you prefer an
## instance API — the static API below works with or without that.

const MANIFEST_PATH := "res://assets.manifest.json"

static var _slots: Dictionary = {}
static var _style_pack: String = ""
static var _loaded: bool = false


## (Re)read the manifest. Call again after the Studio board rewrites a slot.
static func reload() -> void:
	_slots.clear()
	_style_pack = ""
	_loaded = false
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("NoxAssetBinder: manifest missing at %s" % MANIFEST_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (parsed is Dictionary):
		push_error("NoxAssetBinder: %s is not a JSON object" % MANIFEST_PATH)
		return
	var manifest: Dictionary = parsed
	_style_pack = str(manifest.get("stylePack", ""))
	for slot: Variant in manifest.get("slots", []):
		if slot is Dictionary and slot.has("slotId"):
			_slots[str(slot["slotId"])] = slot
	_loaded = true


static func _ensure() -> void:
	if not _loaded:
		reload()


static func has_slot(slot_id: String) -> bool:
	_ensure()
	return _slots.has(slot_id)


## Raw slot entry (treat as read-only — the manifest is Studio-owned).
static func get_slot(slot_id: String) -> Dictionary:
	_ensure()
	return _slots.get(slot_id, {})


## The current res:// path bound to a slot, or "" while unfilled.
static func resolve(slot_id: String) -> String:
	var f: Variant = get_slot(slot_id).get("file")
	return f if f is String else ""


## Texture bound to a slot, or null while unfilled (callers show a placeholder).
## Falls back to loading from disk for files the Studio dropped in post-import.
static func get_texture(slot_id: String) -> Texture2D:
	var path := resolve(slot_id)
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		return res if res is Texture2D else null
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(path)) == OK:
		return ImageTexture.create_from_image(img)
	push_warning("NoxAssetBinder: slot '%s' file not found: %s" % [slot_id, path])
	return null


static func get_stream(slot_id: String) -> AudioStream:
	var path := resolve(slot_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStream


static func get_video_stream(slot_id: String) -> VideoStream:
	var path := resolve(slot_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as VideoStream


## Build a SpriteFrames at runtime from the slot's spritesheet texture. The
## frame layout (count/fps/name) lives in the scene; only the TEXTURE is bound
## through the manifest, so re-skinning is a manifest edit.
static func build_sprite_frames(slot_id: String, frame_count: int, fps: float,
		anim_name: String, loop: bool) -> SpriteFrames:
	var frames := SpriteFrames.new()
	if anim_name == "":
		anim_name = "default"
	if not frames.has_animation(anim_name):
		frames.add_animation(anim_name)
	if anim_name != "default" and frames.has_animation("default"):
		frames.remove_animation("default")
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, loop)
	var tex := get_texture(slot_id)
	if tex == null:
		return frames  # empty but valid; caller/placeholder handles unfilled
	var fw := int(tex.get_width() / max(frame_count, 1))
	var fh := tex.get_height()
	for i in range(frame_count):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * fw, 0, fw, fh)
		frames.add_frame(anim_name, at)
	return frames


## Deterministic muted placeholder tint for an unfilled slot (stable per id).
static func placeholder_color(slot_id: String) -> Color:
	var declared: Variant = get_slot(slot_id).get("placeholderColor")
	if declared is String and Color.html_is_valid(declared):
		return Color.html(declared)
	var hue := absf(fmod(float(hash(slot_id)) * 0.61803398875, 1.0))
	return Color.from_hsv(hue, 0.22, 0.32)
'''

_SLOT_ANIMATED_SPRITE_GD = r'''extends AnimatedSprite2D
## Binds its SpriteFrames from a stable asset slot at load — no baked res://
## texture path. Swap the sheet from the Studio via the manifest; the frame
## layout below stays put. (godogen engine-export)

@export var slot_id: String = ""
@export var frame_count: int = 1
@export var fps: float = 12.0
@export var animation_name: String = "default"
@export var loop: bool = true
@export var autoplay_on_ready: bool = true


func _ready() -> void:
	if slot_id.is_empty():
		return
	sprite_frames = NoxAssetBinder.build_sprite_frames(
		slot_id, frame_count, fps, animation_name, loop)
	animation = animation_name if animation_name != "" else "default"
	if autoplay_on_ready and sprite_frames != null and sprite_frames.has_animation(animation):
		play(animation)
'''

_SLOT_AUDIO_GD = r'''extends AudioStreamPlayer
## Binds its AudioStream from a stable asset slot at load — no baked res://
## stream path. (godogen engine-export)

@export var slot_id: String = ""
@export var autoplay_on_ready: bool = false


func _ready() -> void:
	if slot_id.is_empty():
		return
	stream = NoxAssetBinder.get_stream(slot_id)
	if autoplay_on_ready and stream != null:
		play()
'''

_SLOT_AUDIO_3D_GD = r'''extends AudioStreamPlayer3D
## Binds its AudioStream from a stable asset slot at load — no baked res://
## stream path. (godogen engine-export)

@export var slot_id: String = ""
@export var autoplay_on_ready: bool = false


func _ready() -> void:
	if slot_id.is_empty():
		return
	stream = NoxAssetBinder.get_stream(slot_id)
	if autoplay_on_ready and stream != null:
		play()
'''

_SLOT_VIDEO_GD = r'''extends VideoStreamPlayer
## Binds its VideoStream from a stable asset slot at load — no baked res://
## stream path. (godogen engine-export)

@export var slot_id: String = ""
@export var autoplay_on_ready: bool = true


func _ready() -> void:
	if slot_id.is_empty():
		return
	stream = NoxAssetBinder.get_video_stream(slot_id)
	if autoplay_on_ready and stream != null:
		play()
'''

_SLOT_TILEMAP_GD = r'''extends TileMapLayer
## Builds a single-atlas TileSet at load from a stable asset slot texture — no
## baked res:// atlas path. The grid geometry lives here; the ATLAS is bound
## through the manifest, so re-skinning tiles is a manifest edit. (godogen
## engine-export)

@export var slot_id: String = ""
@export var tile_size: int = 32
@export var columns: int = 1
@export var rows: int = 1
@export var separation: int = 0
@export var margin: int = 0


func _ready() -> void:
	if slot_id.is_empty():
		return
	var tex := NoxAssetBinder.get_texture(slot_id)
	if tex == null:
		return
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_size, tile_size)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(tile_size, tile_size)
	if margin > 0:
		src.margins = Vector2i(margin, margin)
	if separation > 0:
		src.separation = Vector2i(separation, separation)
	for r in range(rows):
		for c in range(columns):
			src.create_tile(Vector2i(c, r))
	ts.add_source(src, 0)
	tile_set = ts
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixels
'''

_SLOT_GD_BY_KEY = {
    "animated_sprite": _SLOT_ANIMATED_SPRITE_GD,
    "audio": _SLOT_AUDIO_GD,
    "audio_3d": _SLOT_AUDIO_3D_GD,
    "video": _SLOT_VIDEO_GD,
    "tilemap": _SLOT_TILEMAP_GD,
}


def _find_project_root(start: Path) -> Path | None:
    """Walk up from `start` looking for the dir containing project.godot."""
    cur = start if start.is_dir() else start.parent
    for _ in range(10):
        if (cur / "project.godot").exists():
            return cur
        if cur.parent == cur:
            break
        cur = cur.parent
    return None


def _binder_res_path(project_root: Path | None, output: Path, script_file: str) -> str:
    """res:// path to a scaffolded binder script (infra, not a swappable asset)."""
    return f"res://{BINDER_DIR}/{script_file}"


def scaffold_binder(project_root: Path, only: list[str] | None = None) -> list[str]:
    """Emit NoxAssetBinder + the slot node scripts under the project root.
    Idempotent: writes files that are missing or whose content differs. Returns
    the list of files written."""
    wrote: list[str] = []
    target_dir = project_root / BINDER_DIR
    target_dir.mkdir(parents=True, exist_ok=True)

    def _write(rel_name: str, content: str) -> None:
        p = target_dir / rel_name
        if (not p.exists()) or p.read_text(encoding="utf-8") != content:
            p.write_text(content, encoding="utf-8")
            wrote.append(str(p))

    _write(BINDER_SCRIPT, _NOX_ASSET_BINDER_GD)
    keys = only if only else list(_SLOT_GD_BY_KEY.keys())
    for key in keys:
        _write(SLOT_SCRIPTS[key], _SLOT_GD_BY_KEY[key])
    return wrote


# --- per-project slot manifest (assets.manifest.json) -----------------------

def _manifest_path_for(project_root: Path | None, output: Path,
                       explicit: str | None) -> Path:
    if explicit:
        return Path(explicit)
    base = project_root if project_root is not None else output.parent
    return base / "assets.manifest.json"


def _load_slot_manifest(path: Path) -> dict:
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                data.setdefault("slots", [])
                return data
        except json.JSONDecodeError:
            raise SystemExit(f"slot manifest JSON parse error: {path}")
    return {"schemaVersion": 2, "stylePack": "", "slots": []}


def _upsert_slot(manifest: dict, slot_id: str, kind: str, file_res: str,
                 policy: str, provenance: dict) -> None:
    entry = {
        "slotId": slot_id,
        "kind": kind,
        "policy": policy,
        # Default binding so the project runs out of the box; the Studio edits
        # this `file` to swap/replace the asset — no scene edit needed.
        "file": file_res,
        "provenance": {k: v for k, v in provenance.items() if v},
    }
    slots = manifest.setdefault("slots", [])
    for i, s in enumerate(slots):
        if s.get("slotId") == slot_id:
            slots[i] = entry
            return
    slots.append(entry)


def _save_slot_manifest(path: Path, manifest: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def _bind_slot(asset: Path, output: Path, slot_id: str, kind: str,
               args) -> dict:
    """Scaffold the resolver, register the slot (default binding = this asset)
    in the per-project manifest, and return info for the caller's JSON report.
    `args` supplies optional --manifest / --policy / provenance / --style-pack."""
    project_root = _find_project_root(output) or _find_project_root(asset)
    scaffold_root = project_root if project_root is not None else output.parent
    scaffolded = scaffold_binder(scaffold_root)

    manifest_path = _manifest_path_for(project_root, output,
                                       getattr(args, "manifest", None))
    manifest = _load_slot_manifest(manifest_path)
    if getattr(args, "style_pack", None):
        manifest["stylePack"] = args.style_pack

    file_res = "res://" + _resolve_res_path(asset)
    provenance = {
        "provider": getattr(args, "provider", "") or "",
        "license": getattr(args, "license", "") or "",
        "source": getattr(args, "source", "") or "",
        "style": getattr(args, "style_pack", "") or manifest.get("stylePack", ""),
    }
    _upsert_slot(manifest, slot_id, kind, file_res,
                 getattr(args, "policy", "generated") or "generated", provenance)
    _save_slot_manifest(manifest_path, manifest)
    return {
        "slot_id": slot_id,
        "manifest": str(manifest_path),
        "default_binding": file_res,
        "scaffolded": scaffolded,
    }


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

def emit_tileset_tres(asset: Path, tile_size: int, grid: str, output: Path,
                      separation: int = 0, margin: int = 0) -> None:
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
    # margins/separation MUST precede the cell markers so the atlas grid resolves
    # (a pixeltool `tileset --margin/--separation` atlas needs these to line up).
    if margin:
        lines.append(f"margins = Vector2i({margin}, {margin})")
    if separation:
        lines.append(f"separation = Vector2i({separation}, {separation})")
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


def emit_texture_import(asset: Path) -> None:
    """Write a Godot-4 `.import` sidecar for a pixel-art texture: lossless (no
    VRAM compression), NO mipmaps, alpha border fixed — the crisp-pixel fix so
    tiles don't import blurry. Godot completes uid/dest_files on first import.
    (Nearest FILTERING is a node/project setting, not an import field.)"""
    res_path = _resolve_res_path(asset)
    text = "\n".join([
        "[remap]",
        "",
        'importer="texture"',
        'type="CompressedTexture2D"',
        "",
        "[deps]",
        "",
        f'source_file="res://{res_path}"',
        "",
        "[params]",
        "",
        "compress/mode=0",
        "compress/high_quality=false",
        "mipmaps/generate=false",
        "roughness/mode=0",
        "process/fix_alpha_border=true",
        "process/premult_alpha=false",
        "detect_3d/compress_to=0",
        "",
    ])
    asset.with_suffix(asset.suffix + ".import").write_text(text, encoding="utf-8")


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
# Godot slot-bound scenes (stable-ID; no baked res:// asset path)
# ---------------------------------------------------------------------------

def emit_sprite_frames_slot_scene(asset: Path, frame_count: int, fps: float,
                                   anim_name: str, output: Path, slot_id: str,
                                   loop: bool = True, autoplay: bool = True) -> None:
    """AnimatedSprite2D .tscn that builds its SpriteFrames from a slot at load."""
    uid = _stable_uid(str(output))
    script_res = f"res://{BINDER_DIR}/{SLOT_SCRIPTS['animated_sprite']}"
    if anim_name == "":
        anim_name = "default"
    text = (
        f'[gd_scene load_steps=2 format=3 uid="uid://{uid}"]\n\n'
        f'[ext_resource type="Script" path="{script_res}" id="1_binder"]\n\n'
        f'[node name="{asset.stem}" type="AnimatedSprite2D"]\n'
        f'script = ExtResource("1_binder")\n'
        f'slot_id = "{slot_id}"\n'
        f"frame_count = {frame_count}\n"
        f"fps = {fps}\n"
        f'animation_name = "{anim_name}"\n'
        f"loop = {str(loop).lower()}\n"
        f"autoplay_on_ready = {str(autoplay).lower()}\n"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")


def emit_audio_scene_slot(asset: Path, output: Path, slot_id: str,
                          volume_db: float = 0.0, spatial: bool = False,
                          autoplay: bool = False) -> None:
    uid = _stable_uid(str(output))
    node_type = "AudioStreamPlayer3D" if spatial else "AudioStreamPlayer"
    script_res = (f"res://{BINDER_DIR}/"
                  f"{SLOT_SCRIPTS['audio_3d'] if spatial else SLOT_SCRIPTS['audio']}")
    text = (
        f'[gd_scene load_steps=2 format=3 uid="uid://{uid}"]\n\n'
        f'[ext_resource type="Script" path="{script_res}" id="1_binder"]\n\n'
        f'[node name="{asset.stem}" type="{node_type}"]\n'
        f'script = ExtResource("1_binder")\n'
        f'slot_id = "{slot_id}"\n'
        f"volume_db = {volume_db}\n"
        f"autoplay_on_ready = {str(autoplay).lower()}\n"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")


def emit_video_scene_slot(asset: Path, output: Path, slot_id: str,
                          autoplay: bool = True, expand: bool = True) -> None:
    uid = _stable_uid(str(output))
    script_res = f"res://{BINDER_DIR}/{SLOT_SCRIPTS['video']}"
    text = (
        f'[gd_scene load_steps=2 format=3 uid="uid://{uid}"]\n\n'
        f'[ext_resource type="Script" path="{script_res}" id="1_binder"]\n\n'
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
        f'script = ExtResource("1_binder")\n'
        f'slot_id = "{slot_id}"\n'
        f"autoplay_on_ready = {str(autoplay).lower()}\n"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")


def emit_tileset_slot_scene(asset: Path, tile_size: int, grid: str,
                            output: Path, slot_id: str,
                            separation: int = 0, margin: int = 0) -> None:
    """TileMapLayer .tscn that builds a single-atlas TileSet from a slot at load."""
    if "x" not in grid:
        raise SystemExit("--grid must be like 4x4 or 6x4")
    cols_s, rows_s = grid.split("x", 1)
    cols, rows = int(cols_s), int(rows_s)
    uid = _stable_uid(str(output))
    script_res = f"res://{BINDER_DIR}/{SLOT_SCRIPTS['tilemap']}"
    text = (
        f'[gd_scene load_steps=2 format=3 uid="uid://{uid}"]\n\n'
        f'[ext_resource type="Script" path="{script_res}" id="1_binder"]\n\n'
        f'[node name="{asset.stem}" type="TileMapLayer"]\n'
        f'script = ExtResource("1_binder")\n'
        f'slot_id = "{slot_id}"\n'
        f"tile_size = {tile_size}\n"
        f"columns = {cols}\n"
        f"rows = {rows}\n"
        f"separation = {separation}\n"
        f"margin = {margin}\n"
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
    if getattr(args, "slot_id", None):
        if args.append:
            raise SystemExit("--append is not supported in slot mode "
                             "(the frame layout lives in the scene, the texture "
                             "in the manifest)")
        emit_sprite_frames_slot_scene(
            asset, args.frame_count, args.fps, args.animation_name, output,
            args.slot_id, loop=not args.no_loop, autoplay=True)
        bind = _bind_slot(asset, output, args.slot_id, "spritesheet", args)
        print(json.dumps({
            "ok": True, "format": "godot.sprite_frames.slot_scene",
            "wrote": str(output), "slot_bound": True,
            "animation": args.animation_name, "frames": args.frame_count,
            **bind,
        }, indent=2))
        return
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
        "wrote": str(output), "appended": args.append, "slot_bound": False,
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
    if getattr(args, "slot_id", None):
        emit_tileset_slot_scene(asset, args.tile_size, args.grid, output,
                                args.slot_id, separation=args.separation,
                                margin=args.margin)
        wrote = [str(output)]
        if not args.no_import:
            emit_texture_import(asset)
            wrote.append(str(asset) + ".import")
        bind = _bind_slot(asset, output, args.slot_id, "tileset", args)
        print(json.dumps({"ok": True, "format": "godot.tileset.slot_scene",
                          "wrote": wrote, "slot_bound": True, **bind}, indent=2))
        return
    emit_tileset_tres(asset, args.tile_size, args.grid, output,
                      separation=args.separation, margin=args.margin)
    wrote = [str(output)]
    if not args.no_import:
        emit_texture_import(asset)
        wrote.append(str(asset) + ".import")
    print(json.dumps({"ok": True, "format": "godot.tileset_tres",
                      "wrote": wrote, "slot_bound": False}, indent=2))


def cmd_audio_scene(args) -> None:
    asset = Path(args.asset)
    if not asset.exists():
        raise SystemExit(f"asset not found: {asset}")
    output = Path(args.output)
    if getattr(args, "slot_id", None):
        emit_audio_scene_slot(asset, output, args.slot_id,
                              volume_db=args.volume_db, spatial=args.spatial,
                              autoplay=args.autoplay)
        kind = "audio_voice" if getattr(args, "voice", False) else (
            "audio_music" if getattr(args, "music", False) else "audio_sfx")
        bind = _bind_slot(asset, output, args.slot_id, kind, args)
        print(json.dumps({"ok": True, "format": "godot.audio_scene.slot",
                          "wrote": str(output), "spatial": args.spatial,
                          "slot_bound": True, **bind}, indent=2))
        return
    emit_audio_scene(asset, output, volume_db=args.volume_db,
                     spatial=args.spatial, autoplay=args.autoplay)
    print(json.dumps({"ok": True, "format": "godot.audio_scene",
                      "wrote": str(output), "spatial": args.spatial,
                      "slot_bound": False}, indent=2))


def cmd_video_scene(args) -> None:
    asset = Path(args.asset)
    if not asset.exists():
        raise SystemExit(f"asset not found: {asset}")
    output = Path(args.output)
    if getattr(args, "slot_id", None):
        emit_video_scene_slot(asset, output, args.slot_id,
                              autoplay=not args.no_autoplay,
                              expand=not args.no_expand)
        bind = _bind_slot(asset, output, args.slot_id, "other", args)
        print(json.dumps({"ok": True, "format": "godot.video_scene.slot",
                          "wrote": str(output), "slot_bound": True, **bind},
                         indent=2))
        return
    emit_video_scene(asset, output, autoplay=not args.no_autoplay,
                     loop=args.loop, expand=not args.no_expand)
    print(json.dumps({"ok": True, "format": "godot.video_scene",
                      "wrote": str(output), "slot_bound": False}, indent=2))


def cmd_scaffold_binder(args) -> None:
    """Emit the NoxAssetBinder resolver + slot node scripts and (optionally) an
    empty per-project manifest, so a project can adopt stable-ID binding even
    before any asset is exported."""
    project_root = _find_project_root(Path(args.project)) if args.project else \
        _find_project_root(Path.cwd())
    if project_root is None:
        project_root = Path(args.project) if args.project else Path.cwd()
    scaffolded = scaffold_binder(project_root)
    manifest_path = _manifest_path_for(project_root, project_root, args.manifest)
    created_manifest = False
    if not manifest_path.exists():
        manifest = {"schemaVersion": 2,
                    "stylePack": args.style_pack or "", "slots": []}
        _save_slot_manifest(manifest_path, manifest)
        created_manifest = True
    print(json.dumps({"ok": True, "format": "godot.asset_binder",
                      "project_root": str(project_root),
                      "scaffolded": scaffolded,
                      "manifest": str(manifest_path),
                      "created_manifest": created_manifest}, indent=2))


def cmd_list(_args) -> None:
    print(json.dumps({
        "exports": [
            {"name": "sprite-frames", "engine": "godot",
             "out": ".tres (or .tscn in slot mode)", "input": "spritesheet PNG",
             "slot_mode": True},
            {"name": "sprite-prefab", "engine": "unity",
             "out": ".prefab.json", "input": "spritesheet PNG",
             "slot_mode": False},
            {"name": "tileset-tres", "engine": "godot",
             "out": ".tres (or .tscn in slot mode)", "input": "tileset atlas PNG",
             "slot_mode": True},
            {"name": "audio-scene", "engine": "godot",
             "out": ".tscn", "input": "WAV/OGG", "slot_mode": True},
            {"name": "video-scene", "engine": "godot",
             "out": ".tscn", "input": "MP4", "slot_mode": True},
            {"name": "scaffold-binder", "engine": "godot",
             "out": "resolver .gd + assets.manifest.json", "input": "(none)",
             "slot_mode": True},
        ],
        "note": ("Pass --slot-id <id> to any Godot export for STABLE-ID binding "
                 "(no baked res:// asset path; resolved at load via NoxAssetBinder "
                 "+ assets.manifest.json). Required for template/product work."),
    }, indent=2))


def _add_slot_args(p) -> None:
    """Stable-ID binding options shared by every Godot emitter."""
    g = p.add_argument_group(
        "stable-ID binding (Studio live-wiring)",
        "Pass --slot-id to bind the asset by a stable id through "
        "assets.manifest.json (no baked res:// asset path). Required for "
        "template/product work.")
    g.add_argument("--slot-id", help="Stable slot id, e.g. 'sprite/knight' or "
                                     "'audio/jump'. Enables slot mode.")
    g.add_argument("--manifest", help="Per-project slot manifest path "
                                      "(default: <project>/assets.manifest.json)")
    g.add_argument("--policy", default="generated",
                   choices=["generated", "reused", "static", "placeholder"],
                   help="How this slot gets filled (provenance)")
    g.add_argument("--style-pack", help="Style pack for this slot / manifest root")
    g.add_argument("--provider", default="",
                   help="Provenance: generator/provider that produced the asset")
    g.add_argument("--license", default="", help="Provenance: SPDX-ish license tag")
    g.add_argument("--source", default="", help="Provenance: kit/pack/dataset")


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
                   help="Add another animation to an existing .tres (non-slot mode)")
    p.add_argument("--no-loop", action="store_true")
    p.add_argument("--frame-w", type=int, help="Override frame width (default: infer from image)")
    p.add_argument("--frame-h", type=int, help="Override frame height")
    p.add_argument("-o", "--output", required=True)
    _add_slot_args(p)
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
    p.add_argument("--separation", type=int, default=0, help="px gap between cells (match the atlas)")
    p.add_argument("--margin", type=int, default=0, help="px atlas border (match the atlas)")
    p.add_argument("--no-import", action="store_true", help="skip the crisp-pixel .import sidecar")
    p.add_argument("-o", "--output", required=True)
    _add_slot_args(p)
    p.set_defaults(func=cmd_tileset_tres)

    p = sub.add_parser("audio-scene", help="Godot AudioStreamPlayer scene")
    p.add_argument("--asset", required=True)
    p.add_argument("--volume-db", type=float, default=0.0)
    p.add_argument("--spatial", action="store_true",
                   help="Emit AudioStreamPlayer3D instead of AudioStreamPlayer")
    p.add_argument("--autoplay", action="store_true")
    p.add_argument("--music", action="store_true",
                   help="Tag the slot kind as audio_music (default audio_sfx)")
    p.add_argument("--voice", action="store_true",
                   help="Tag the slot kind as audio_voice (narrative VO)")
    p.add_argument("-o", "--output", required=True)
    _add_slot_args(p)
    p.set_defaults(func=cmd_audio_scene)

    p = sub.add_parser("video-scene", help="Godot VideoStreamPlayer scene")
    p.add_argument("--asset", required=True)
    p.add_argument("--no-autoplay", action="store_true")
    p.add_argument("--loop", action="store_true")
    p.add_argument("--no-expand", action="store_true")
    p.add_argument("-o", "--output", required=True)
    _add_slot_args(p)
    p.set_defaults(func=cmd_video_scene)

    p = sub.add_parser("scaffold-binder",
                       help="Emit the NoxAssetBinder resolver + empty manifest")
    p.add_argument("--project", help="Godot project root (default: cwd / walk up "
                                     "to project.godot)")
    p.add_argument("--manifest", help="Manifest path "
                                      "(default: <project>/assets.manifest.json)")
    p.add_argument("--style-pack", default="", help="Style pack for the manifest root")
    p.set_defaults(func=cmd_scaffold_binder)

    p = sub.add_parser("list", help="List available exports")
    p.set_defaults(func=cmd_list)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
