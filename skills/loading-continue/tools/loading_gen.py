"""loading_gen — async loading screen, resume-last Continue, and load/save slot picker.

Godot 4 scaffold for the three presentation systems that sit between the menu and
gameplay and are commonly missing:

  loader      SceneLoader autoload + loading_screen.tscn/.gd — threaded async scene
              load with a real progress bar, rotating tips, and a minimum display
              time (no one-frame flash).
  continue    ContinueService autoload — resume-last: find the newest save slot and
              jump straight back in (wires the nox_ui "Continue" button, which by
              default just starts a NEW game).
  loadscreen  load_screen.tscn/.gd — save-slot picker (thumbnail + summary +
              timestamp) that doubles as the Load and the Save picker.
  all         all of the above.

Reuse-first: backdrop art and tip strings are sourced from the library / manifest,
not invented here. Typography-deferred: scenes apply theme.tres (pass --theme), so
fonts come from the `typography` skill. Depends on the `save-system` SaveManager
autoload for slot data; integrates with the `ui-shell` NoxShell autoload.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


# ---------------------------------------------------------------------------
# Emitted GDScript / scenes
# ---------------------------------------------------------------------------

SCENE_LOADER_GD = '''extends CanvasLayer
## SceneLoader — autoload. Threaded async scene change with a loading screen.
## Autoload as "SceneLoader". Call SceneLoader.change_scene("res://.../game.tscn").
## Replaces bare get_tree().change_scene_to_file() so large scenes don't hitch and
## the player always sees progress + a tip instead of a frozen frame.

signal load_finished(path: String)

const LOADING_SCENE := "res://addons/loading/loading_screen.tscn"
const MIN_DISPLAY_SEC := 0.8   # never flash the loading screen for one frame

var _target := ""
var _loading := false
var _elapsed := 0.0
var _screen: Control = null

func change_scene(path: String) -> void:
	if _loading:
		return
	if not ResourceLoader.exists(path):
		push_error("SceneLoader: scene does not exist: %s" % path)
		return
	_target = path
	_loading = true
	_elapsed = 0.0
	get_tree().paused = false
	_show_screen()
	ResourceLoader.load_threaded_request(path)

func _show_screen() -> void:
	if ResourceLoader.exists(LOADING_SCENE):
		_screen = (load(LOADING_SCENE) as PackedScene).instantiate()
		add_child(_screen)

func _process(delta: float) -> void:
	if not _loading:
		return
	_elapsed += delta
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(_target, progress)
	var p: float = (progress[0] if progress.size() > 0 else 0.0)
	if _screen and _screen.has_method("set_progress"):
		_screen.set_progress(p)
	match status:
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("SceneLoader: failed to load %s" % _target)
			_loading = false
			_dismiss()
		ResourceLoader.THREAD_LOAD_LOADED:
			if _elapsed < MIN_DISPLAY_SEC:
				return   # hold the screen so it doesn't flash
			var packed: PackedScene = ResourceLoader.load_threaded_get(_target)
			_loading = false
			get_tree().change_scene_to_packed(packed)
			load_finished.emit(_target)
			_dismiss()

func _dismiss() -> void:
	if _screen:
		_screen.queue_free()
		_screen = null
'''

LOADING_SCREEN_GD = '''extends Control
## loading_screen — visual for SceneLoader. Progress bar + rotating tip + backdrop.
## Reuse-first: assign a real backdrop to $Backdrop and fill TIPS from the library,
## not placeholder art. Typography-deferred: theme.tres supplies the fonts.

## Fill these from your game's help/lore strings (reuse-first, localizable).
const TIPS := [
	"Tip: Press Esc to pause at any time.",
	"Tip: Autosave keeps the last few minutes safe.",
]

@onready var _bar: ProgressBar = $VBox/Bar
@onready var _tip: Label = $VBox/Tip
var _tip_timer := 0.0

func _ready() -> void:
	if TIPS.size() > 0:
		_tip.text = TIPS[randi() % TIPS.size()]
	_bar.value = 0.0

func set_progress(p: float) -> void:
	_bar.value = clampf(p, 0.0, 1.0) * 100.0

func _process(delta: float) -> void:
	# Rotate the tip every few seconds during long loads.
	_tip_timer += delta
	if _tip_timer >= 4.0 and TIPS.size() > 1:
		_tip_timer = 0.0
		_tip.text = TIPS[randi() % TIPS.size()]
'''

CONTINUE_SERVICE_GD = '''extends Node
## ContinueService — autoload. Resume-last ("Continue"): jump back into the newest
## save without the slot picker. Depends on SaveManager (save-system) for slot data
## and SceneLoader for the transition. Autoload as "ContinueService".
##
## Wire the nox_ui menu (main_menu.gd) — by default its Continue button starts a
## NEW game, which is wrong. Replace those two lines with:
##   _continue.visible = ContinueService.has_resumable()
##   func _on_continue_pressed() -> void: ContinueService.resume_last()

func has_resumable() -> bool:
	if get_node_or_null("/root/SaveManager") == null:
		return false
	for s in SaveManager.list_slots():
		if s.get("exists", false):
			return true
	return false

func latest_slot() -> int:
	var best := -1
	var best_time := -1.0
	for s in SaveManager.list_slots():
		if not s.get("exists", false):
			continue
		var t: float = float(s.get("modified_time", 0))
		if t > best_time:
			best_time = t
			best = int(s.get("slot", -1))
	return best

func resume_last() -> void:
	var slot := latest_slot()
	if slot < 0:
		push_warning("ContinueService: nothing to resume")
		return
	var data = SaveManager.load_from_slot(slot)
	if data == null:
		push_error("ContinueService: failed to load slot %d" % slot)
		return
	# SaveData carries the scene to return to (topdown/rpg presets: scene_path).
	var target: String = data.scene_path if "scene_path" in data else ""
	if target == "" or not ResourceLoader.exists(target):
		push_error("ContinueService: save has no valid scene_path")
		return
	if get_node_or_null("/root/SceneLoader") != null:
		SceneLoader.change_scene(target)
	else:
		get_tree().change_scene_to_file(target)
	# Gameplay scene reads SaveManager's loaded data on _ready to restore state.
'''

LOAD_SCREEN_GD = '''extends Control
## load_screen — save-slot picker. Serves BOTH Load (from menu) and Save (in-game)
## via `mode`. Builds one card per slot from SaveManager.list_slots(): thumbnail,
## summary, timestamp. Empty slots read "Empty" (and, in save mode, are writable).
## Depends on SaveManager (save-system); typography/theme deferred to theme.tres.

enum Mode { LOAD, SAVE }
@export var mode: Mode = Mode.LOAD

@onready var _list: VBoxContainer = $Panel/VBox/Slots

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	if get_node_or_null("/root/SaveManager") == null:
		push_error("load_screen: SaveManager autoload missing")
		return
	for s in SaveManager.list_slots():
		_list.add_child(_make_card(s))

func _make_card(s: Dictionary) -> Control:
	var slot: int = int(s.get("slot", 0))
	var exists: bool = s.get("exists", false)
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 96)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(160, 90)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tp: String = s.get("thumbnail_path", "")
	if exists and tp != "" and ResourceLoader.exists(tp):
		thumb.texture = load(tp)
	row.add_child(thumb)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = ("Slot %d" % slot) if exists else ("Slot %d — Empty" % slot)
	info.add_child(title)
	if exists:
		var sub := Label.new()
		sub.text = "%s   ·   %s" % [str(s.get("summary", "")), _fmt_time(s.get("modified_time", 0))]
		info.add_child(sub)
	row.add_child(info)

	var act := Button.new()
	if mode == Mode.LOAD:
		act.text = "Load"
		act.disabled = not exists
		act.pressed.connect(func(): _on_load(slot))
	else:
		act.text = "Overwrite" if exists else "Save"
		act.pressed.connect(func(): _on_save(slot))
	row.add_child(act)

	if exists:
		var del := Button.new()
		del.text = "Delete"
		del.pressed.connect(func(): _on_delete(slot))
		row.add_child(del)
	return row

func _fmt_time(unix) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(int(unix))
	return "%04d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]

func _on_load(slot: int) -> void:
	var data = SaveManager.load_from_slot(slot)
	if data == null:
		return
	var target: String = data.scene_path if "scene_path" in data else ""
	if target != "" and get_node_or_null("/root/SceneLoader") != null:
		SceneLoader.change_scene(target)
	elif target != "":
		get_tree().change_scene_to_file(target)

func _on_save(slot: int) -> void:
	# CUSTOMIZE_HERE: snapshot current game state into a SaveData, then:
	#   SaveManager.save_to_slot(slot, data)
	# (mirror the autosave._snapshot_state() callback from save-system)
	push_warning("load_screen: provide a SaveData snapshot in _on_save()")
	_rebuild()

func _on_delete(slot: int) -> void:
	SaveManager.delete_slot(slot)
	_rebuild()
'''


def _tscn_loading(theme: str | None) -> str:
    steps = 3 if theme else 2
    theme_line = f'\n[ext_resource type="Theme" path="{theme}" id="2_theme"]' if theme else ""
    theme_prop = '\ntheme = ExtResource("2_theme")' if theme else ""
    return f'''[gd_scene load_steps={steps} format=3]

[ext_resource type="Script" path="res://addons/loading/loading_screen.gd" id="1_ls"]{theme_line}

[node name="LoadingScreen" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1_ls"){theme_prop}

[node name="Backdrop" type="TextureRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
stretch_mode = 6

[node name="VBox" type="VBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 7
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -300.0
offset_top = -140.0
offset_right = 300.0
offset_bottom = -60.0
grow_horizontal = 2
grow_vertical = 0

[node name="Tip" type="Label" parent="VBox"]
layout_mode = 2
horizontal_alignment = 1

[node name="Bar" type="ProgressBar" parent="VBox"]
layout_mode = 2
custom_minimum_size = Vector2(0, 24)
max_value = 100.0
'''


def _tscn_load_screen(theme: str | None) -> str:
    steps = 3 if theme else 2
    theme_line = f'\n[ext_resource type="Theme" path="{theme}" id="2_theme"]' if theme else ""
    theme_prop = '\ntheme = ExtResource("2_theme")' if theme else ""
    return f'''[gd_scene load_steps={steps} format=3]

[ext_resource type="Script" path="res://addons/loading/load_screen.gd" id="1_load"]{theme_line}

[node name="LoadScreen" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1_load"){theme_prop}

[node name="Panel" type="PanelContainer" parent="."]
layout_mode = 1
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -420.0
offset_top = -300.0
offset_right = 420.0
offset_bottom = 300.0
grow_horizontal = 2
grow_vertical = 2

[node name="VBox" type="VBoxContainer" parent="Panel"]
layout_mode = 2

[node name="Title" type="Label" parent="Panel/VBox"]
layout_mode = 2
text = "Load Game"
horizontal_alignment = 1

[node name="Scroll" type="ScrollContainer" parent="Panel/VBox"]
layout_mode = 2
size_flags_vertical = 3

[node name="Slots" type="VBoxContainer" parent="Panel/VBox/Scroll"]
layout_mode = 2
size_flags_horizontal = 3
'''


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def _write(outdir: Path, name: str, content: str, wrote: list[str]) -> None:
    (outdir / name).write_text(content, encoding="utf-8")
    wrote.append(name)


def cmd_loader(args, wrote: list[str]) -> None:
    outdir = Path(args.output)
    outdir.mkdir(parents=True, exist_ok=True)
    _write(outdir, "scene_loader.gd", SCENE_LOADER_GD, wrote)
    _write(outdir, "loading_screen.gd", LOADING_SCREEN_GD, wrote)
    _write(outdir, "loading_screen.tscn", _tscn_loading(args.theme), wrote)


def cmd_continue(args, wrote: list[str]) -> None:
    outdir = Path(args.output)
    outdir.mkdir(parents=True, exist_ok=True)
    _write(outdir, "continue_service.gd", CONTINUE_SERVICE_GD, wrote)


def cmd_loadscreen(args, wrote: list[str]) -> None:
    outdir = Path(args.output)
    outdir.mkdir(parents=True, exist_ok=True)
    _write(outdir, "load_screen.gd", LOAD_SCREEN_GD, wrote)
    _write(outdir, "load_screen.tscn", _tscn_load_screen(args.theme), wrote)


def cmd_all(args, wrote: list[str]) -> None:
    cmd_loader(args, wrote)
    cmd_continue(args, wrote)
    cmd_loadscreen(args, wrote)


def main() -> None:
    ap = argparse.ArgumentParser(description="Async loading + resume-last + slot picker scaffold")
    sub = ap.add_subparsers(required=True, dest="cmd")
    for name, fn, helptext in [
        ("loader", cmd_loader, "SceneLoader autoload + loading_screen scene"),
        ("continue", cmd_continue, "ContinueService autoload (resume-last)"),
        ("loadscreen", cmd_loadscreen, "Save-slot picker (Load/Save)"),
        ("all", cmd_all, "Emit everything"),
    ]:
        p = sub.add_parser(name, help=helptext)
        p.add_argument("--output", default="addons/loading/",
                       help="Output dir (default addons/loading/)")
        p.add_argument("--theme", help="res:// path to theme.tres for the scenes")
        p.set_defaults(func=fn)

    args = ap.parse_args()
    wrote: list[str] = []
    args.func(args, wrote)
    print(json.dumps({"ok": True, "output": args.output, "wrote": wrote}, indent=2))


if __name__ == "__main__":
    main()
