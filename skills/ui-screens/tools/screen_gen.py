"""UI Screens — Godot 4 Control-tree .tscn + Unity Canvas-prefab JSON
scaffolds for the five common game screens: title, menu, hud, inventory,
dialog.

Each subcommand emits a fully-wired scene scaffold (Control root with
sensibly-placed children) plus an optional generated backdrop PNG via
image-pipeline's asset_gen.py. UI element textures (buttons, icons,
portraits) are out of scope — generate those separately with image-pipeline
and drop them into the placeholder TextureRect / Button paths in the .tscn.

Subcommands
-----------
title       Main menu / title screen: logo + Start / Options / Quit
menu        Pause menu: dim overlay + panel + Resume / Save / Options / Quit
hud         In-game HUD overlay: health bar, ammo, minimap, action prompt
inventory   Grid inventory + stats side panel (configurable --grid)
dialog      NPC dialog box: portrait + text + advance arrow
list        Enumerate available screens with their child node summaries
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
# Backdrop generation (optional, via image-pipeline)
# ---------------------------------------------------------------------------

def _generate_backdrop(
    prompt: str,
    output_path: Path,
    size: str = "1K",
    aspect: str = "16:9",
    style: str = "",
    preset: str = "",
) -> bool:
    """Invoke image-pipeline asset_gen.py to render a backdrop image.

    Returns True on success, False if the subprocess fails (caller decides
    whether to fall back to a placeholder color).
    """
    cli = IMAGE_PIPELINE_TOOLS / "asset_gen.py"
    cmd = [
        sys.executable, str(cli), "image",
        "--type", "reference",
        "--prompt", prompt,
        "--size", size, "--aspect-ratio", aspect,
        "-o", str(output_path),
        "--no-face-detailer",
    ]
    if style:
        cmd += ["--style", style]
    if preset:
        cmd += ["--preset", preset]
    print(f"[screen_gen] generating backdrop -> {output_path}", file=sys.stderr)
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        print(f"[screen_gen] backdrop generation failed: {proc.stderr.strip()[:200]}", file=sys.stderr)
        return False
    return output_path.exists()


# ---------------------------------------------------------------------------
# Godot .tscn templates
# ---------------------------------------------------------------------------

def _ext_resource(rel: str, idx: int) -> str:
    return f'[ext_resource type="Texture2D" path="res://{rel}" id="{idx}"]'


def _tscn_title(
    output_scene: Path,
    title_text: str,
    backdrop_rel: str | None,
    buttons: list[str],
    viewport: tuple[int, int],
) -> Path:
    """Title screen: backdrop + game title label + N buttons stacked center."""
    w, h = viewport
    lines: list[str] = []
    ext_steps = 1 + (1 if backdrop_rel else 0)
    lines.append(f"[gd_scene load_steps={ext_steps + 1} format=3]")
    lines.append("")
    if backdrop_rel:
        lines.append(_ext_resource(backdrop_rel, 1))
        lines.append("")
    lines.append('[node name="TitleScreen" type="Control"]')
    lines.append("anchor_right = 1.0")
    lines.append("anchor_bottom = 1.0")
    lines.append("offset_right = 0.0")
    lines.append("offset_bottom = 0.0")
    lines.append("")
    if backdrop_rel:
        lines.append('[node name="Backdrop" type="TextureRect" parent="."]')
        lines.append("anchor_right = 1.0")
        lines.append("anchor_bottom = 1.0")
        lines.append('texture = ExtResource("1")')
        lines.append('expand_mode = 1')  # Ignore image size
        lines.append('stretch_mode = 6')  # Keep aspect, covered
        lines.append("")
    else:
        lines.append('[node name="Backdrop" type="ColorRect" parent="."]')
        lines.append("anchor_right = 1.0")
        lines.append("anchor_bottom = 1.0")
        lines.append("color = Color(0.05, 0.05, 0.1, 1.0)")
        lines.append("")
    # Title label at top-center
    lines.append('[node name="Title" type="Label" parent="."]')
    lines.append("anchor_left = 0.5; anchor_right = 0.5; anchor_top = 0.15")
    lines.append(f"offset_left = -{w // 4}; offset_right = {w // 4}; offset_top = 0; offset_bottom = 120")
    lines.append(f'text = "{title_text}"')
    lines.append('horizontal_alignment = 1')
    lines.append('vertical_alignment = 1')
    lines.append('theme_override_font_sizes/font_size = 72')
    lines.append("")
    # Button container
    lines.append('[node name="Buttons" type="VBoxContainer" parent="."]')
    lines.append("anchor_left = 0.5; anchor_right = 0.5; anchor_top = 0.5")
    lines.append(f"offset_left = -160; offset_right = 160; offset_top = 0; offset_bottom = {len(buttons) * 60 + 40}")
    lines.append('theme_override_constants/separation = 16')
    lines.append("")
    for i, label in enumerate(buttons):
        node = f"Btn{i}_{_sanitize(label)}"
        lines.append(f'[node name="{node}" type="Button" parent="Buttons"]')
        lines.append(f'custom_minimum_size = Vector2(0, 48)')
        lines.append(f'text = "{label}"')
        lines.append("")
    output_scene.parent.mkdir(parents=True, exist_ok=True)
    output_scene.write_text("\n".join(lines), encoding="utf-8")
    return output_scene


def _tscn_menu(
    output_scene: Path,
    title_text: str,
    buttons: list[str],
    viewport: tuple[int, int],
) -> Path:
    """Pause menu: dim overlay + centered panel + stacked buttons."""
    lines: list[str] = []
    lines.append("[gd_scene load_steps=1 format=3]")
    lines.append("")
    lines.append('[node name="PauseMenu" type="Control"]')
    lines.append("anchor_right = 1.0; anchor_bottom = 1.0")
    lines.append("process_mode = 1")  # PROCESS_MODE_ALWAYS — runs while paused
    lines.append("")
    # Dim overlay
    lines.append('[node name="DimOverlay" type="ColorRect" parent="."]')
    lines.append("anchor_right = 1.0; anchor_bottom = 1.0")
    lines.append("color = Color(0, 0, 0, 0.6)")
    lines.append("")
    # Panel
    lines.append('[node name="Panel" type="PanelContainer" parent="."]')
    lines.append("anchor_left = 0.5; anchor_right = 0.5; anchor_top = 0.5; anchor_bottom = 0.5")
    panel_h = len(buttons) * 60 + 140
    lines.append(f"offset_left = -200; offset_right = 200; offset_top = -{panel_h // 2}; offset_bottom = {panel_h // 2}")
    lines.append("")
    lines.append('[node name="VBox" type="VBoxContainer" parent="Panel"]')
    lines.append('theme_override_constants/separation = 12')
    lines.append("")
    lines.append('[node name="Title" type="Label" parent="Panel/VBox"]')
    lines.append(f'text = "{title_text}"')
    lines.append('horizontal_alignment = 1')
    lines.append('theme_override_font_sizes/font_size = 32')
    lines.append("")
    for i, label in enumerate(buttons):
        node = f"Btn{i}_{_sanitize(label)}"
        lines.append(f'[node name="{node}" type="Button" parent="Panel/VBox"]')
        lines.append('custom_minimum_size = Vector2(0, 44)')
        lines.append(f'text = "{label}"')
        lines.append("")
    output_scene.parent.mkdir(parents=True, exist_ok=True)
    output_scene.write_text("\n".join(lines), encoding="utf-8")
    return output_scene


def _tscn_hud(
    output_scene: Path,
    viewport: tuple[int, int],
) -> Path:
    """In-game HUD: health bar TL, ammo+icon TR, minimap below ammo,
    action prompt bottom-center. No backdrop (transparent over gameplay).
    """
    lines: list[str] = []
    lines.append("[gd_scene load_steps=1 format=3]")
    lines.append("")
    lines.append('[node name="HUD" type="Control"]')
    lines.append("anchor_right = 1.0; anchor_bottom = 1.0")
    lines.append("mouse_filter = 2")  # MOUSE_FILTER_IGNORE — clicks pass through
    lines.append("")
    # Health bar TL
    lines.append('[node name="HealthBar" type="ProgressBar" parent="."]')
    lines.append("offset_left = 24; offset_top = 24; offset_right = 264; offset_bottom = 56")
    lines.append("min_value = 0; max_value = 100; value = 100")
    lines.append("")
    lines.append('[node name="HealthLabel" type="Label" parent="HealthBar"]')
    lines.append('text = "HP"')
    lines.append("anchor_right = 1.0; anchor_bottom = 1.0")
    lines.append("horizontal_alignment = 1; vertical_alignment = 1")
    lines.append("")
    # Ammo TR
    lines.append('[node name="AmmoLabel" type="Label" parent="."]')
    lines.append("anchor_left = 1.0; anchor_right = 1.0")
    lines.append("offset_left = -200; offset_right = -24; offset_top = 24; offset_bottom = 56")
    lines.append('text = "AMMO: 30 / 90"')
    lines.append('horizontal_alignment = 2')
    lines.append('theme_override_font_sizes/font_size = 24')
    lines.append("")
    # Minimap TR (below ammo)
    lines.append('[node name="MinimapFrame" type="PanelContainer" parent="."]')
    lines.append("anchor_left = 1.0; anchor_right = 1.0")
    lines.append("offset_left = -184; offset_right = -24; offset_top = 72; offset_bottom = 232")
    lines.append("")
    lines.append('[node name="Minimap" type="TextureRect" parent="MinimapFrame"]')
    lines.append('expand_mode = 1')
    lines.append("")
    # Action prompt bottom-center
    lines.append('[node name="ActionPrompt" type="Label" parent="."]')
    lines.append("anchor_left = 0.5; anchor_right = 0.5; anchor_top = 1.0; anchor_bottom = 1.0")
    lines.append("offset_left = -200; offset_right = 200; offset_top = -120; offset_bottom = -80")
    lines.append('text = "[E] Interact"')
    lines.append('horizontal_alignment = 1; vertical_alignment = 1')
    lines.append('theme_override_font_sizes/font_size = 20')
    lines.append("")
    output_scene.parent.mkdir(parents=True, exist_ok=True)
    output_scene.write_text("\n".join(lines), encoding="utf-8")
    return output_scene


def _tscn_inventory(
    output_scene: Path,
    grid: tuple[int, int],
    viewport: tuple[int, int],
) -> Path:
    """Inventory: panel + GridContainer of slots + stats side panel."""
    cols, rows = grid
    slot_size = 64
    lines: list[str] = []
    lines.append("[gd_scene load_steps=1 format=3]")
    lines.append("")
    lines.append('[node name="Inventory" type="Control"]')
    lines.append("anchor_right = 1.0; anchor_bottom = 1.0")
    lines.append("")
    lines.append('[node name="DimOverlay" type="ColorRect" parent="."]')
    lines.append("anchor_right = 1.0; anchor_bottom = 1.0")
    lines.append("color = Color(0, 0, 0, 0.5)")
    lines.append("")
    grid_w = cols * (slot_size + 8) + 32
    grid_h = rows * (slot_size + 8) + 80
    lines.append('[node name="MainPanel" type="PanelContainer" parent="."]')
    lines.append("anchor_left = 0.5; anchor_right = 0.5; anchor_top = 0.5; anchor_bottom = 0.5")
    panel_w = grid_w + 240
    panel_h = max(grid_h, 360)
    lines.append(f"offset_left = -{panel_w // 2}; offset_right = {panel_w // 2}")
    lines.append(f"offset_top = -{panel_h // 2}; offset_bottom = {panel_h // 2}")
    lines.append("")
    lines.append('[node name="HBox" type="HBoxContainer" parent="MainPanel"]')
    lines.append('theme_override_constants/separation = 16')
    lines.append("")
    # Grid (left)
    lines.append('[node name="GridSection" type="VBoxContainer" parent="MainPanel/HBox"]')
    lines.append("")
    lines.append('[node name="GridTitle" type="Label" parent="MainPanel/HBox/GridSection"]')
    lines.append('text = "Inventory"')
    lines.append('theme_override_font_sizes/font_size = 24')
    lines.append("")
    lines.append('[node name="Grid" type="GridContainer" parent="MainPanel/HBox/GridSection"]')
    lines.append(f'columns = {cols}')
    lines.append('theme_override_constants/h_separation = 8')
    lines.append('theme_override_constants/v_separation = 8')
    lines.append("")
    for y in range(rows):
        for x in range(cols):
            idx = y * cols + x
            lines.append(f'[node name="Slot_{idx:02d}" type="PanelContainer" parent="MainPanel/HBox/GridSection/Grid"]')
            lines.append(f'custom_minimum_size = Vector2({slot_size}, {slot_size})')
            lines.append("")
            lines.append(f'[node name="Icon" type="TextureRect" parent="MainPanel/HBox/GridSection/Grid/Slot_{idx:02d}"]')
            lines.append('expand_mode = 1')
            lines.append('stretch_mode = 5')
            lines.append("")
    # Stats (right)
    lines.append('[node name="StatsSection" type="VBoxContainer" parent="MainPanel/HBox"]')
    lines.append('custom_minimum_size = Vector2(200, 0)')
    lines.append("")
    lines.append('[node name="StatsTitle" type="Label" parent="MainPanel/HBox/StatsSection"]')
    lines.append('text = "Stats"')
    lines.append('theme_override_font_sizes/font_size = 20')
    lines.append("")
    lines.append('[node name="StatsList" type="Label" parent="MainPanel/HBox/StatsSection"]')
    lines.append('text = "HP: 100/100\\nMP: 50/50\\nATK: 12\\nDEF: 8"')
    lines.append("")
    output_scene.parent.mkdir(parents=True, exist_ok=True)
    output_scene.write_text("\n".join(lines), encoding="utf-8")
    return output_scene


def _tscn_dialog(
    output_scene: Path,
    viewport: tuple[int, int],
) -> Path:
    """NPC dialog box: bottom 1/3 of screen, portrait inset TL, advance
    arrow icon BR.
    """
    w, h = viewport
    lines: list[str] = []
    lines.append("[gd_scene load_steps=1 format=3]")
    lines.append("")
    lines.append('[node name="DialogBox" type="Control"]')
    lines.append("anchor_right = 1.0; anchor_bottom = 1.0")
    lines.append("mouse_filter = 2")
    lines.append("")
    lines.append('[node name="Box" type="PanelContainer" parent="."]')
    lines.append("anchor_left = 0.04; anchor_right = 0.96; anchor_top = 0.70; anchor_bottom = 0.96")
    lines.append("")
    lines.append('[node name="Margin" type="MarginContainer" parent="Box"]')
    lines.append("theme_override_constants/margin_left = 16; theme_override_constants/margin_right = 16")
    lines.append("theme_override_constants/margin_top = 12; theme_override_constants/margin_bottom = 12")
    lines.append("")
    lines.append('[node name="HBox" type="HBoxContainer" parent="Box/Margin"]')
    lines.append('theme_override_constants/separation = 16')
    lines.append("")
    lines.append('[node name="Portrait" type="TextureRect" parent="Box/Margin/HBox"]')
    lines.append('custom_minimum_size = Vector2(96, 96)')
    lines.append('expand_mode = 1; stretch_mode = 5')
    lines.append("")
    lines.append('[node name="TextSection" type="VBoxContainer" parent="Box/Margin/HBox"]')
    lines.append('size_flags_horizontal = 3')  # SIZE_EXPAND_FILL
    lines.append("")
    lines.append('[node name="SpeakerName" type="Label" parent="Box/Margin/HBox/TextSection"]')
    lines.append('text = "Speaker"')
    lines.append('theme_override_font_sizes/font_size = 22')
    lines.append("")
    lines.append('[node name="DialogText" type="RichTextLabel" parent="Box/Margin/HBox/TextSection"]')
    lines.append('bbcode_enabled = true')
    lines.append('fit_content = true')
    lines.append('text = "Dialog text appears here. Use BBCode for [b]emphasis[/b] and [color=yellow]item highlights[/color]."')
    lines.append("")
    lines.append('[node name="AdvanceArrow" type="Label" parent="Box/Margin/HBox/TextSection"]')
    lines.append('text = "[Space]"')
    lines.append('horizontal_alignment = 2')  # right
    lines.append('theme_override_font_sizes/font_size = 14')
    lines.append("")
    output_scene.parent.mkdir(parents=True, exist_ok=True)
    output_scene.write_text("\n".join(lines), encoding="utf-8")
    return output_scene


# ---------------------------------------------------------------------------
# Unity JSON sidecars (Canvas layout description)
# ---------------------------------------------------------------------------

def _unity_layout(
    screen_type: str,
    children: list[dict],
    output_json: Path,
    notes: str = "",
) -> Path:
    """Emit a JSON description of the Canvas hierarchy + child positions.
    User reconstructs in Unity UI Builder / UI Toolkit; full .prefab YAML
    auto-generation is too Unity-version-fragile.
    """
    data = {
        "screen_type": screen_type,
        "canvas_render_mode": "ScreenSpaceOverlay",
        "reference_resolution": [1920, 1080],
        "children": children,
        "notes": notes or (
            "Create a UI Canvas (Screen Space - Overlay), add child GameObjects "
            "matching the children list. Each entry's anchor / offset describes "
            "RectTransform settings."
        ),
    }
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return output_json


def _sanitize(s: str) -> str:
    return "".join(c if c.isalnum() else "_" for c in s).strip("_") or "Item"


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_title(args):
    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)
    scene = out_dir / "title.tscn"
    backdrop_rel = None
    if args.generate_backdrop:
        bd_path = out_dir / "backdrop.png"
        bd_prompt = args.backdrop_prompt or f"{args.title} cinematic title backdrop, dramatic atmosphere"
        if _generate_backdrop(bd_prompt, bd_path, size=args.backdrop_size, aspect="16:9",
                              style=args.style, preset=args.preset):
            backdrop_rel = bd_path.name

    buttons = args.buttons.split(",")
    _tscn_title(scene, args.title, backdrop_rel, buttons, viewport=(1920, 1080))
    engine_outputs = {"godot_tscn": str(scene)}
    if args.engine in ("unity", "both"):
        children = [
            {"name": "Backdrop", "type": "RawImage", "anchor": "stretch", "texture": backdrop_rel},
            {"name": "Title", "type": "TMP_Text", "anchor": "top-center", "text": args.title, "font_size": 72},
            {"name": "Buttons", "type": "VerticalLayoutGroup", "anchor": "center",
             "children": [{"name": _sanitize(b), "type": "Button", "text": b} for b in buttons]},
        ]
        uj = _unity_layout("title", children, out_dir / "title.unity.json")
        engine_outputs["unity_json"] = str(uj)
    print(json.dumps({"ok": True, "subcommand": "title",
                      "scene": str(scene), "backdrop": str(out_dir / "backdrop.png") if backdrop_rel else None,
                      "buttons": buttons, "engine_outputs": engine_outputs}, indent=2))


def cmd_menu(args):
    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)
    scene = out_dir / "menu.tscn"
    buttons = args.buttons.split(",")
    _tscn_menu(scene, args.title, buttons, viewport=(1920, 1080))
    engine_outputs = {"godot_tscn": str(scene)}
    if args.engine in ("unity", "both"):
        children = [
            {"name": "DimOverlay", "type": "Image", "anchor": "stretch", "color": [0, 0, 0, 0.6]},
            {"name": "Panel", "type": "Image", "anchor": "center",
             "children": [
                 {"name": "Title", "type": "TMP_Text", "text": args.title, "font_size": 32},
                 *[{"name": _sanitize(b), "type": "Button", "text": b} for b in buttons],
             ]},
        ]
        uj = _unity_layout("menu", children, out_dir / "menu.unity.json")
        engine_outputs["unity_json"] = str(uj)
    print(json.dumps({"ok": True, "subcommand": "menu", "scene": str(scene),
                      "buttons": buttons, "engine_outputs": engine_outputs}, indent=2))


def cmd_hud(args):
    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)
    scene = out_dir / "hud.tscn"
    _tscn_hud(scene, viewport=(1920, 1080))
    engine_outputs = {"godot_tscn": str(scene)}
    if args.engine in ("unity", "both"):
        children = [
            {"name": "HealthBar", "type": "Slider", "anchor": "top-left", "offset": [24, 24], "size": [240, 32]},
            {"name": "AmmoLabel", "type": "TMP_Text", "anchor": "top-right", "offset": [-200, 24], "text": "AMMO: 30 / 90"},
            {"name": "MinimapFrame", "type": "Image", "anchor": "top-right", "offset": [-184, 72], "size": [160, 160]},
            {"name": "ActionPrompt", "type": "TMP_Text", "anchor": "bottom-center", "offset": [0, -100], "text": "[E] Interact"},
        ]
        uj = _unity_layout("hud", children, out_dir / "hud.unity.json")
        engine_outputs["unity_json"] = str(uj)
    print(json.dumps({"ok": True, "subcommand": "hud", "scene": str(scene),
                      "engine_outputs": engine_outputs}, indent=2))


def cmd_inventory(args):
    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)
    scene = out_dir / "inventory.tscn"
    grid = _parse_grid(args.grid)
    cols, rows = grid
    _tscn_inventory(scene, grid, viewport=(1920, 1080))
    engine_outputs = {"godot_tscn": str(scene)}
    if args.engine in ("unity", "both"):
        slots = [{"name": f"Slot_{i:02d}", "type": "Button", "icon": None} for i in range(cols * rows)]
        children = [
            {"name": "DimOverlay", "type": "Image", "anchor": "stretch", "color": [0, 0, 0, 0.5]},
            {"name": "Grid", "type": "GridLayoutGroup", "columns": cols, "rows": rows,
             "cell_size": [64, 64], "children": slots},
            {"name": "Stats", "type": "TMP_Text", "text": "HP: 100/100\nMP: 50/50\nATK: 12\nDEF: 8"},
        ]
        uj = _unity_layout("inventory", children, out_dir / "inventory.unity.json")
        engine_outputs["unity_json"] = str(uj)
    print(json.dumps({"ok": True, "subcommand": "inventory", "scene": str(scene),
                      "grid": [cols, rows], "slot_count": cols * rows,
                      "engine_outputs": engine_outputs}, indent=2))


def cmd_dialog(args):
    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)
    scene = out_dir / "dialog.tscn"
    _tscn_dialog(scene, viewport=(1920, 1080))
    engine_outputs = {"godot_tscn": str(scene)}
    if args.engine in ("unity", "both"):
        children = [
            {"name": "Box", "type": "Image", "anchor": "bottom-stretch", "offset": [76, -270, -76, -38]},
            {"name": "Portrait", "type": "Image", "anchor": "left", "size": [96, 96]},
            {"name": "SpeakerName", "type": "TMP_Text", "text": "Speaker", "font_size": 22},
            {"name": "DialogText", "type": "TMP_Text", "rich_text": True,
             "text": "Dialog text appears here. Use <b>BBCode-style</b> rich text for emphasis."},
            {"name": "AdvanceArrow", "type": "TMP_Text", "text": "[Space]", "anchor": "right"},
        ]
        uj = _unity_layout("dialog", children, out_dir / "dialog.unity.json")
        engine_outputs["unity_json"] = str(uj)
    print(json.dumps({"ok": True, "subcommand": "dialog", "scene": str(scene),
                      "engine_outputs": engine_outputs}, indent=2))


def cmd_list(args):
    rows = [
        ("title",     "Main menu: backdrop + game title label + N buttons stacked"),
        ("menu",      "Pause menu: dim overlay + panel + title + N buttons (Resume / Options / Quit)"),
        ("hud",       "In-game overlay: HealthBar TL, AmmoLabel TR, Minimap below ammo, ActionPrompt BC"),
        ("inventory", "Grid: panel + GridContainer slots + stats side panel"),
        ("dialog",    "NPC dialog: bottom panel + portrait + speaker name + rich-text body + advance hint"),
    ]
    for name, desc in rows:
        print(f"  {name:10s} {desc}")


def _parse_grid(s: str) -> tuple[int, int]:
    try:
        a, b = s.lower().split("x")
        return int(a), int(b)
    except Exception:
        raise SystemExit(f"--grid must be like '6x4', got {s!r}")


def main():
    parser = argparse.ArgumentParser(description="ui-screens: Godot Control + Unity Canvas scaffolds")
    sub = parser.add_subparsers(required=True, dest="cmd")

    p = sub.add_parser("title", help="Title / main menu screen")
    p.add_argument("--title", required=True, help="Game title text shown on the screen")
    p.add_argument("--buttons", default="Start,Options,Quit",
                   help="Comma-separated button labels (default: Start,Options,Quit)")
    p.add_argument("-o", "--output", required=True, help="Output DIRECTORY")
    p.add_argument("--generate-backdrop", action="store_true",
                   help="Render a backdrop PNG via image-pipeline asset_gen.py")
    p.add_argument("--backdrop-prompt", default="", help="Custom backdrop prompt (default: derived from --title)")
    p.add_argument("--backdrop-size", default="1K", choices=["512", "1K", "2K", "4K"])
    p.add_argument("--style", default="", help="ZIT style key (passed to backdrop generation)")
    p.add_argument("--preset", default="", help="Pixel-art preset (passed to backdrop generation)")
    p.add_argument("--engine", default="both", choices=["godot", "unity", "both", "none"])
    p.set_defaults(func=cmd_title)

    p = sub.add_parser("menu", help="Pause menu (dim overlay + panel)")
    p.add_argument("--title", default="Paused", help="Panel title text")
    p.add_argument("--buttons", default="Resume,Options,Save,Quit to Title")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--engine", default="both", choices=["godot", "unity", "both", "none"])
    p.set_defaults(func=cmd_menu)

    p = sub.add_parser("hud", help="In-game HUD overlay (health/ammo/minimap/prompt)")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--engine", default="both", choices=["godot", "unity", "both", "none"])
    p.set_defaults(func=cmd_hud)

    p = sub.add_parser("inventory", help="Grid inventory + stats panel")
    p.add_argument("--grid", default="6x4", help="Cols x rows (e.g. 6x4 = 24 slots)")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--engine", default="both", choices=["godot", "unity", "both", "none"])
    p.set_defaults(func=cmd_inventory)

    p = sub.add_parser("dialog", help="NPC dialog box (portrait + text + advance)")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--engine", default="both", choices=["godot", "unity", "both", "none"])
    p.set_defaults(func=cmd_dialog)

    p = sub.add_parser("list", help="List available screens")
    p.set_defaults(func=cmd_list)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
