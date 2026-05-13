"""Engine-specific companion-file writers for scene-art outputs.

Each writer takes the PNG paths produced by scene_gen.py and emits the
Godot- or Unity-side resource/scene/metadata file that wires the textures
into a working game asset. All writers are pure-Python text emitters with
no external deps (no Godot/Unity runtime needed).

Godot side:
  - write_godot_parallax_tscn  → ParallaxBackground + ParallaxLayer nodes
  - write_godot_tileset_tres   → TileSet resource with TileSetAtlasSource
  - write_godot_sky_tres       → Sky resource (panorama or cube)

Unity side:
  - write_unity_parallax_json  → data layout for a user's parallax script
  - write_unity_atlas_json     → tile-atlas slice metadata for Sprite Editor
  - write_unity_skybox_readme  → naming-convention notes (Unity skybox setup
                                 is editor-driven; we just produce the right
                                 files in the right names)
"""

from __future__ import annotations

import json
from pathlib import Path


# ---------------------------------------------------------------------------
# Godot writers
# ---------------------------------------------------------------------------

def write_godot_parallax_tscn(
    layers: list[tuple[str, Path, float]],
    output_scene: Path,
    viewport_size: tuple[int, int] = (1920, 1080),
) -> Path:
    """Write a Godot 4 ParallaxBackground scene.

    `layers` is a list of (display_name, png_path, motion_scale) tuples in
    back-to-front order. motion_scale is the Godot ParallaxLayer scale
    (0 = static, 1 = locks to camera, 0.1 = far/slow, 0.9 = near/fast).
    """
    lines: list[str] = []
    lines.append(f"[gd_scene load_steps={len(layers) + 1} format=3]")
    lines.append("")
    # External texture resources
    for idx, (_, png_path, _) in enumerate(layers, start=1):
        rel = _relative_to_scene(png_path, output_scene)
        lines.append(
            f'[ext_resource type="Texture2D" path="res://{rel}" id="{idx}"]'
        )
    lines.append("")
    # Root node
    lines.append('[node name="ParallaxBackground" type="ParallaxBackground"]')
    lines.append("")
    # One ParallaxLayer + Sprite2D per layer
    cx, cy = viewport_size[0] // 2, viewport_size[1] // 2
    for idx, (name, _, scroll) in enumerate(layers, start=1):
        node = _node_name(name)
        lines.append(f'[node name="{node}" type="ParallaxLayer" parent="."]')
        lines.append(f"motion_scale = Vector2({scroll}, 1)")
        lines.append("")
        lines.append(f'[node name="Sprite2D" type="Sprite2D" parent="{node}"]')
        lines.append(f'texture = ExtResource("{idx}")')
        lines.append(f"position = Vector2({cx}, {cy})")
        lines.append("")
    output_scene.parent.mkdir(parents=True, exist_ok=True)
    output_scene.write_text("\n".join(lines), encoding="utf-8")
    return output_scene


def write_godot_tileset_tres(
    atlas_path: Path,
    output_tres: Path,
    tile_size: int,
    grid: tuple[int, int],
) -> Path:
    """Write a Godot 4 TileSet resource pointing at `atlas_path`.

    `grid` is (columns, rows) of tiles in the atlas. Every tile is enabled
    by default (you trim in Godot editor if you only want a subset).
    """
    cols, rows = grid
    lines: list[str] = []
    lines.append('[gd_resource type="TileSet" load_steps=3 format=3]')
    lines.append("")
    rel = _relative_to_scene(atlas_path, output_tres)
    lines.append(f'[ext_resource type="Texture2D" path="res://{rel}" id="1"]')
    lines.append("")
    lines.append('[sub_resource type="TileSetAtlasSource" id="1"]')
    lines.append('texture = ExtResource("1")')
    lines.append(f"texture_region_size = Vector2i({tile_size}, {tile_size})")
    for x in range(cols):
        for y in range(rows):
            lines.append(f"{x}:{y}/0 = 0")
    lines.append("")
    lines.append("[resource]")
    lines.append('sources/0 = SubResource("1")')
    lines.append("")
    output_tres.parent.mkdir(parents=True, exist_ok=True)
    output_tres.write_text("\n".join(lines), encoding="utf-8")
    return output_tres


def write_godot_sky_tres(
    output_tres: Path,
    panorama_path: Path | None = None,
    cube_faces: dict[str, Path] | None = None,
) -> Path:
    """Write a Godot Sky resource. Either pass `panorama_path` (single
    equirectangular 2:1 PNG → PanoramaSkyMaterial) OR `cube_faces` (dict
    with keys px/nx/py/ny/pz/nz → 6-sided cube material).
    """
    lines: list[str] = []
    if panorama_path is not None:
        lines.append('[gd_resource type="Sky" load_steps=3 format=3]')
        lines.append("")
        rel = _relative_to_scene(panorama_path, output_tres)
        lines.append(f'[ext_resource type="Texture2D" path="res://{rel}" id="1"]')
        lines.append("")
        lines.append('[sub_resource type="PanoramaSkyMaterial" id="1"]')
        lines.append('panorama = ExtResource("1")')
        lines.append("")
        lines.append("[resource]")
        lines.append('sky_material = SubResource("1")')
    elif cube_faces is not None:
        # Godot doesn't have a stock 6-sided sky material — you wire each
        # face into a Cubemap resource. Emit a Cubemap stub plus the Sky
        # resource that points at it.
        face_order = ["px", "nx", "py", "ny", "pz", "nz"]
        missing = [f for f in face_order if f not in cube_faces]
        if missing:
            raise ValueError(f"cube_faces missing: {missing}")
        lines.append(
            f'[gd_resource type="Sky" load_steps={len(face_order) + 2} format=3]'
        )
        lines.append("")
        for idx, face in enumerate(face_order, start=1):
            rel = _relative_to_scene(cube_faces[face], output_tres)
            lines.append(
                f'[ext_resource type="Texture2D" path="res://{rel}" id="{idx}"]'
            )
        lines.append("")
        lines.append('[sub_resource type="Cubemap" id="cubemap"]')
        for idx, face in enumerate(face_order, start=1):
            lines.append(f'side_{face} = ExtResource("{idx}")')
        lines.append("")
        # Sky material — Godot's stock PhysicalSkyMaterial doesn't take a
        # cubemap; users usually plug the Cubemap into a custom ShaderMaterial.
        # We emit the Cubemap; the user attaches it via a ShaderMaterial in
        # the editor (documented in SKILL.md).
        lines.append("[resource]")
        lines.append("# Wire SubResource('cubemap') into a ShaderMaterial that")
        lines.append("# samples it (see SKILL.md). Stock Godot 4 has no")
        lines.append("# 6-cube sky material; this Cubemap is the bridge.")
        lines.append("")
    else:
        raise ValueError("write_godot_sky_tres: pass panorama_path OR cube_faces")
    output_tres.parent.mkdir(parents=True, exist_ok=True)
    output_tres.write_text("\n".join(lines), encoding="utf-8")
    return output_tres


# ---------------------------------------------------------------------------
# Unity writers — JSON / README sidecars (Unity .meta YAML is too version-
# fragile to auto-generate reliably; we hand the user clean inputs instead).
# ---------------------------------------------------------------------------

def write_unity_parallax_json(
    layers: list[tuple[str, Path, float]],
    output_json: Path,
) -> Path:
    """Write a layout JSON for a user-side Unity parallax script.

    Unity has no stock ParallaxBackground equivalent; teams usually attach
    a small MonoBehaviour to each layer transform that scrolls it based on
    Camera.main.position. We just hand them the layer list + scroll speeds.
    """
    data = {
        "layers": [
            {
                "name": name,
                "texture": str(png.name),
                "texture_path": str(png),
                "scroll_speed": float(scroll),
            }
            for (name, png, scroll) in layers
        ],
        "note": (
            "Attach a parallax-scroll MonoBehaviour to each layer's "
            "GameObject. Use scroll_speed as the multiplier on Camera.main "
            "position delta. 0 = static sky, 1 = locks to camera."
        ),
    }
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return output_json


def write_unity_atlas_json(
    atlas_path: Path,
    output_json: Path,
    tile_size: int,
    grid: tuple[int, int],
) -> Path:
    """Write atlas slice metadata for Unity's Sprite Editor 'Grid by Cell
    Size' import. User opens the PNG in Unity, sets Sprite Mode = Multiple,
    Pixels Per Unit = tile_size, and slices using these dimensions.
    """
    cols, rows = grid
    data = {
        "atlas": str(atlas_path.name),
        "atlas_path": str(atlas_path),
        "tile_size_px": int(tile_size),
        "grid": {"columns": int(cols), "rows": int(rows)},
        "total_tiles": int(cols * rows),
        "unity_import": {
            "sprite_mode": "Multiple",
            "pixels_per_unit": int(tile_size),
            "filter_mode": "Point (no filter)",
            "compression": "None",
            "slice_mode": "Grid by Cell Size",
            "pixel_size": f"{tile_size} x {tile_size}",
        },
    }
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return output_json


def write_unity_skybox_readme(
    output_dir: Path,
    panorama_path: Path | None = None,
    cube_faces: dict[str, Path] | None = None,
) -> Path:
    """Drop a README.md next to the skybox PNG(s) telling the user how to
    wire them into Unity.
    """
    lines: list[str] = ["# Unity skybox setup", ""]
    if panorama_path is not None:
        lines += [
            f"Panorama texture: `{panorama_path.name}`",
            "",
            "1. Drop the PNG into `Assets/Skyboxes/`.",
            "2. Set Texture Shape = Cube, Mapping = Latitude-Longitude Layout (Cylindrical).",
            "3. Create Material with Shader = Skybox/Panoramic. Drag the texture in.",
            "4. Window > Rendering > Lighting > Environment > Skybox Material = your new material.",
            "",
        ]
    elif cube_faces is not None:
        order = ["px", "nx", "py", "ny", "pz", "nz"]
        lines += [
            "Cube faces:",
            "",
            *[f"- `{face}.png` (Unity slot: {_unity_face_slot(face)})" for face in order if face in cube_faces],
            "",
            "1. Drop all six PNGs into `Assets/Skyboxes/`.",
            "2. Create Material with Shader = Skybox/6 Sided.",
            "3. Assign each PNG to its slot per the list above.",
            "4. Window > Rendering > Lighting > Environment > Skybox Material = your new material.",
            "",
        ]
    out = output_dir / "README.md"
    output_dir.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines), encoding="utf-8")
    return out


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _relative_to_scene(png_path: Path, scene_path: Path) -> str:
    """Compute the path string used inside the .tscn / .tres ext_resource.

    Both Godot and Unity treat asset paths as project-relative; since we
    don't know the project root from here, we emit a path relative to the
    scene file's directory. The user copies the whole output dir into
    `res://` (Godot) or `Assets/` (Unity) and the paths stay valid.
    """
    try:
        return png_path.resolve().relative_to(scene_path.resolve().parent).as_posix()
    except ValueError:
        # png_path isn't under scene's parent — fall back to filename only.
        return png_path.name


def _node_name(display: str) -> str:
    """Sanitize layer name for use as a Godot node name."""
    return "".join(c if c.isalnum() else "_" for c in display).strip("_") or "Layer"


def _unity_face_slot(face: str) -> str:
    return {
        "px": "+X (Right)",
        "nx": "-X (Left)",
        "py": "+Y (Up)",
        "ny": "-Y (Down)",
        "pz": "+Z (Front)",
        "nz": "-Z (Back)",
    }.get(face, face)
