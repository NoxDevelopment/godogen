"""Input Handling — Godot 4 InputMap action emission + rebinding UI scaffold.

Subcommands
-----------
actions    Emit a project.godot [input] block from a named action template
           (platformer, topdown, fps, rts, puzzle, fighting, racing).
           Optionally also patch project.godot in place and write a
           constants .gd module for type-safe action references.
rebind     Write a self-contained rebinding-screen .tscn + .gd + autoload
           that persists overrides to user://input_map.cfg.
template   Print one action template as JSON (preview without writing).
lint       Audit a project.godot input block for foot-guns (no gamepad
           binding, zero deadzone on axes, duplicate physical keys,
           overwritten ui_* actions, undeclared actions referenced from
           GDScript).
list       Enumerate available templates.

Pure text — no ComfyUI / Tripo3D / etc.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Godot input-event literal constructors
# ---------------------------------------------------------------------------

# Godot 4 InputEventKey physical_keycode values. We use physical_keycode (not
# keycode) so bindings are layout-independent — W on AZERTY still moves
# forward on a "WASD" binding.
KEY = {
    # Letters
    "A": 65, "B": 66, "C": 67, "D": 68, "E": 69, "F": 70, "G": 71, "H": 72,
    "I": 73, "J": 74, "K": 75, "L": 76, "M": 77, "N": 78, "O": 79, "P": 80,
    "Q": 81, "R": 82, "S": 83, "T": 84, "U": 85, "V": 86, "W": 87, "X": 88,
    "Y": 89, "Z": 90,
    # Digits
    "0": 48, "1": 49, "2": 50, "3": 51, "4": 52,
    "5": 53, "6": 54, "7": 55, "8": 56, "9": 57,
    # Named
    "Space": 32, "Enter": 4194309, "Escape": 4194305, "Tab": 4194306,
    "Backspace": 4194308, "Shift": 4194326, "Ctrl": 4194328, "Alt": 4194329,
    "Left": 4194319, "Right": 4194321, "Up": 4194320, "Down": 4194322,
    "F1": 4194332, "F2": 4194333, "F3": 4194334, "F4": 4194335,
    "F5": 4194336, "F6": 4194337, "F7": 4194338, "F8": 4194339,
}

# Godot 4 InputEventJoypadButton button indexes (XInput-style — Godot
# normalizes Xbox/PS/Switch into this layout).
JOY_BUTTON = {
    "A": 0, "B": 1, "X": 2, "Y": 3,          # face buttons
    "LB": 9, "RB": 10,                        # shoulder buttons
    "Back": 4, "Start": 6, "Guide": 5,
    "LStick": 7, "RStick": 8,
    "DPadUp": 11, "DPadDown": 12, "DPadLeft": 13, "DPadRight": 14,
}

# Godot 4 InputEventJoypadMotion axis indexes (XInput-style).
JOY_AXIS = {
    "LStickX": 0, "LStickY": 1,
    "RStickX": 2, "RStickY": 3,
    "LT": 4, "RT": 5,
}

# Mouse buttons (InputEventMouseButton.button_index).
MOUSE = {
    "Left": 1, "Right": 2, "Middle": 3,
    "WheelUp": 4, "WheelDown": 5,
}


def _ev_key(name: str) -> str:
    """Build an InputEventKey resource literal (physical-keycode form)."""
    if name not in KEY:
        raise ValueError(f"Unknown key: {name!r}. Add it to KEY map.")
    return (f"Object(InputEventKey,\"resource_local_to_scene\":false,"
            f"\"resource_name\":\"\",\"device\":-1,\"window_id\":0,"
            f"\"alt_pressed\":false,\"shift_pressed\":false,"
            f"\"ctrl_pressed\":false,\"meta_pressed\":false,"
            f"\"pressed\":false,\"keycode\":0,"
            f"\"physical_keycode\":{KEY[name]},"
            f"\"key_label\":0,\"unicode\":0,\"echo\":false,\"script\":null)")


def _ev_joybtn(name: str) -> str:
    if name not in JOY_BUTTON:
        raise ValueError(f"Unknown joypad button: {name!r}")
    return (f"Object(InputEventJoypadButton,\"resource_local_to_scene\":false,"
            f"\"resource_name\":\"\",\"device\":-1,"
            f"\"button_index\":{JOY_BUTTON[name]},\"pressure\":0.0,"
            f"\"pressed\":false,\"script\":null)")


def _ev_joyaxis(name: str, direction: int) -> str:
    """direction: +1 for positive axis, -1 for negative."""
    if name not in JOY_AXIS:
        raise ValueError(f"Unknown joypad axis: {name!r}")
    return (f"Object(InputEventJoypadMotion,\"resource_local_to_scene\":false,"
            f"\"resource_name\":\"\",\"device\":-1,"
            f"\"axis\":{JOY_AXIS[name]},\"axis_value\":{float(direction):.1f},"
            f"\"script\":null)")


def _ev_mouse(name: str) -> str:
    if name not in MOUSE:
        raise ValueError(f"Unknown mouse button: {name!r}")
    return (f"Object(InputEventMouseButton,\"resource_local_to_scene\":false,"
            f"\"resource_name\":\"\",\"device\":-1,\"window_id\":0,"
            f"\"button_mask\":0,\"position\":Vector2(0, 0),"
            f"\"global_position\":Vector2(0, 0),\"factor\":1.0,"
            f"\"button_index\":{MOUSE[name]},\"canceled\":false,"
            f"\"pressed\":false,\"double_click\":false,\"script\":null)")


# ---------------------------------------------------------------------------
# Action templates
# ---------------------------------------------------------------------------

# Each action is: (name, deadzone, description, [event_specs])
# event_specs are tuples: ("key", "W") | ("joybtn", "A") |
#                         ("joyaxis", "LStickX", +1) | ("mouse", "Left")

def _common_pause():
    return ("pause", 0.5, "Open pause menu",
            [("key", "Escape"), ("joybtn", "Start")])


TEMPLATES: dict[str, list[tuple]] = {
    "platformer": [
        ("move_left", 0.2, "Move character left",
         [("key", "A"), ("key", "Left"), ("joyaxis", "LStickX", -1), ("joybtn", "DPadLeft")]),
        ("move_right", 0.2, "Move character right",
         [("key", "D"), ("key", "Right"), ("joyaxis", "LStickX", +1), ("joybtn", "DPadRight")]),
        ("jump", 0.5, "Jump",
         [("key", "Space"), ("joybtn", "A")]),
        ("crouch", 0.5, "Crouch / drop through one-way platforms",
         [("key", "S"), ("key", "Down"), ("joyaxis", "LStickY", +1), ("joybtn", "DPadDown")]),
        ("attack", 0.5, "Primary attack",
         [("key", "J"), ("mouse", "Left"), ("joybtn", "X")]),
        ("interact", 0.5, "Interact with object / talk to NPC",
         [("key", "E"), ("joybtn", "Y")]),
        _common_pause(),
    ],
    "topdown": [
        ("move_up", 0.2, "Move up",
         [("key", "W"), ("key", "Up"), ("joyaxis", "LStickY", -1), ("joybtn", "DPadUp")]),
        ("move_down", 0.2, "Move down",
         [("key", "S"), ("key", "Down"), ("joyaxis", "LStickY", +1), ("joybtn", "DPadDown")]),
        ("move_left", 0.2, "Move left",
         [("key", "A"), ("key", "Left"), ("joyaxis", "LStickX", -1), ("joybtn", "DPadLeft")]),
        ("move_right", 0.2, "Move right",
         [("key", "D"), ("key", "Right"), ("joyaxis", "LStickX", +1), ("joybtn", "DPadRight")]),
        ("attack", 0.5, "Attack (aim with mouse / right stick)",
         [("mouse", "Left"), ("joybtn", "X")]),
        ("dash", 0.5, "Dash / roll",
         [("key", "Space"), ("joybtn", "A")]),
        ("interact", 0.5, "Interact",
         [("key", "E"), ("joybtn", "Y")]),
        ("inventory", 0.5, "Toggle inventory",
         [("key", "I"), ("joybtn", "Back")]),
        _common_pause(),
    ],
    "fps": [
        ("move_forward", 0.2, "Move forward",
         [("key", "W"), ("joyaxis", "LStickY", -1)]),
        ("move_back", 0.2, "Move backward",
         [("key", "S"), ("joyaxis", "LStickY", +1)]),
        ("move_left", 0.2, "Strafe left",
         [("key", "A"), ("joyaxis", "LStickX", -1)]),
        ("move_right", 0.2, "Strafe right",
         [("key", "D"), ("joyaxis", "LStickX", +1)]),
        ("jump", 0.5, "Jump",
         [("key", "Space"), ("joybtn", "A")]),
        ("crouch", 0.5, "Crouch (hold)",
         [("key", "Ctrl"), ("joybtn", "RStick")]),
        ("sprint", 0.5, "Sprint (hold)",
         [("key", "Shift"), ("joybtn", "LStick")]),
        ("fire", 0.5, "Fire primary weapon",
         [("mouse", "Left"), ("joyaxis", "RT", +1)]),
        ("aim", 0.5, "Aim down sights (hold)",
         [("mouse", "Right"), ("joyaxis", "LT", +1)]),
        ("reload", 0.5, "Reload",
         [("key", "R"), ("joybtn", "X")]),
        ("interact", 0.5, "Interact / pick up",
         [("key", "E"), ("joybtn", "Y")]),
        _common_pause(),
    ],
    "rts": [
        ("select", 0.5, "Select unit / box-select on drag",
         [("mouse", "Left"), ("joybtn", "A")]),
        ("multi_select", 0.5, "Add to selection (hold)",
         [("key", "Shift"), ("joybtn", "LB")]),
        ("command", 0.5, "Issue order at cursor",
         [("mouse", "Right"), ("joybtn", "X")]),
        ("cancel", 0.5, "Cancel current order / deselect",
         [("key", "Escape"), ("joybtn", "B")]),
        ("camera_up", 0.2, "Pan camera up",
         [("key", "W"), ("joyaxis", "RStickY", -1)]),
        ("camera_down", 0.2, "Pan camera down",
         [("key", "S"), ("joyaxis", "RStickY", +1)]),
        ("camera_left", 0.2, "Pan camera left",
         [("key", "A"), ("joyaxis", "RStickX", -1)]),
        ("camera_right", 0.2, "Pan camera right",
         [("key", "D"), ("joyaxis", "RStickX", +1)]),
        _common_pause(),
    ],
    "puzzle": [
        ("select", 0.5, "Select / confirm",
         [("mouse", "Left"), ("key", "Enter"), ("joybtn", "A")]),
        ("cancel", 0.5, "Cancel / back",
         [("key", "Escape"), ("joybtn", "B")]),
        ("undo", 0.5, "Undo last move",
         [("key", "Z"), ("joybtn", "X")]),
        ("redo", 0.5, "Redo",
         [("key", "Y"), ("joybtn", "Y")]),
        ("hint", 0.5, "Request a hint",
         [("key", "H"), ("joybtn", "LB")]),
        ("restart", 0.5, "Restart puzzle",
         [("key", "R"), ("joybtn", "Back")]),
        _common_pause(),
    ],
    "fighting": [
        ("move_left", 0.2, "Walk left / back-block",
         [("key", "A"), ("key", "Left"), ("joyaxis", "LStickX", -1), ("joybtn", "DPadLeft")]),
        ("move_right", 0.2, "Walk right",
         [("key", "D"), ("key", "Right"), ("joyaxis", "LStickX", +1), ("joybtn", "DPadRight")]),
        ("crouch", 0.5, "Crouch",
         [("key", "S"), ("key", "Down"), ("joyaxis", "LStickY", +1), ("joybtn", "DPadDown")]),
        ("jump", 0.5, "Jump",
         [("key", "W"), ("key", "Up"), ("joyaxis", "LStickY", -1), ("joybtn", "DPadUp")]),
        ("light_punch", 0.5, "Light punch",
         [("key", "U"), ("joybtn", "X")]),
        ("heavy_punch", 0.5, "Heavy punch",
         [("key", "I"), ("joybtn", "Y")]),
        ("light_kick", 0.5, "Light kick",
         [("key", "J"), ("joybtn", "A")]),
        ("heavy_kick", 0.5, "Heavy kick",
         [("key", "K"), ("joybtn", "B")]),
        ("block", 0.5, "Block (hold)",
         [("key", "L"), ("joybtn", "RB")]),
        _common_pause(),
    ],
    "racing": [
        ("accelerate", 0.5, "Accelerate",
         [("key", "W"), ("key", "Up"), ("joyaxis", "RT", +1), ("joybtn", "A")]),
        ("brake", 0.5, "Brake / reverse",
         [("key", "S"), ("key", "Down"), ("joyaxis", "LT", +1), ("joybtn", "B")]),
        ("steer_left", 0.2, "Steer left",
         [("key", "A"), ("key", "Left"), ("joyaxis", "LStickX", -1)]),
        ("steer_right", 0.2, "Steer right",
         [("key", "D"), ("key", "Right"), ("joyaxis", "LStickX", +1)]),
        ("handbrake", 0.5, "Handbrake / drift",
         [("key", "Space"), ("joybtn", "X")]),
        ("look_back", 0.5, "Look behind (hold)",
         [("key", "C"), ("joybtn", "RB")]),
        _common_pause(),
    ],
    "none": [],
}


# ---------------------------------------------------------------------------
# project.godot [input] emission + patching
# ---------------------------------------------------------------------------

def _build_input_block(template_name: str) -> str:
    if template_name not in TEMPLATES:
        raise SystemExit(f"Unknown template {template_name!r}. "
                         f"Available: {', '.join(TEMPLATES)}")
    actions = TEMPLATES[template_name]
    lines: list[str] = []
    if actions:
        lines.append("[input]")
        lines.append("")
    for name, deadzone, _desc, events in actions:
        event_literals = []
        for spec in events:
            kind = spec[0]
            if kind == "key":
                event_literals.append(_ev_key(spec[1]))
            elif kind == "joybtn":
                event_literals.append(_ev_joybtn(spec[1]))
            elif kind == "joyaxis":
                event_literals.append(_ev_joyaxis(spec[1], spec[2]))
            elif kind == "mouse":
                event_literals.append(_ev_mouse(spec[1]))
            else:
                raise ValueError(f"Unknown event kind {kind!r}")
        events_arr = "[" + ", ".join(event_literals) + "]"
        lines.append(f'{name}={{')
        lines.append(f'"deadzone": {deadzone},')
        lines.append(f'"events": {events_arr}')
        lines.append('}')
    return "\n".join(lines) + ("\n" if lines else "")


_INPUT_SECTION_RE = re.compile(
    r"(?ms)^\[input\]\s*\n(?:.*?)(?=^\[[^\]]+\]\s*\n|\Z)"
)


def _patch_project_godot(path: Path, new_block: str) -> None:
    """Replace [input] in project.godot in place (writing .bak first)."""
    if not path.exists():
        raise SystemExit(f"project.godot not found: {path}")
    original = path.read_text(encoding="utf-8")
    backup = path.with_suffix(path.suffix + ".bak")
    backup.write_text(original, encoding="utf-8")

    if _INPUT_SECTION_RE.search(original):
        patched = _INPUT_SECTION_RE.sub(
            (new_block.rstrip() + "\n\n") if new_block.strip() else "",
            original, count=1,
        )
    else:
        # Append; ensure trailing newline first
        if not original.endswith("\n"):
            original += "\n"
        patched = original + "\n" + new_block
    path.write_text(patched, encoding="utf-8")


def _emit_constants_module(template_name: str, output: Path) -> None:
    """Write a `class_name Actions extends RefCounted` GDScript module."""
    actions = TEMPLATES[template_name]
    lines = [
        "## Auto-generated by input-handling skill. Edit the template, not this file.",
        "## Compare actions with `Input.is_action_pressed(Actions.MOVE_LEFT)` —",
        "## the &\"…\" StringName literal compares without allocating.",
        "class_name Actions",
        "extends RefCounted",
        "",
    ]
    for name, _dz, desc, _evs in actions:
        const = name.upper()
        lines.append(f"## {desc}")
        lines.append(f"const {const} := &\"{name}\"")
        lines.append("")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")


# ---------------------------------------------------------------------------
# Rebinding UI scaffold
# ---------------------------------------------------------------------------

REBIND_TSCN = '''[gd_scene load_steps=2 format=3 uid="uid://b_rebind_screen"]

[ext_resource type="Script" path="res://{rebind_gd_res_path}" id="1_script"]

[node name="RebindScreen" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_script")

[node name="Background" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
color = Color(0, 0, 0, 0.85)

[node name="Margin" type="MarginContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
theme_override_constants/margin_left = 64
theme_override_constants/margin_top = 64
theme_override_constants/margin_right = 64
theme_override_constants/margin_bottom = 64

[node name="Layout" type="VBoxContainer" parent="Margin"]
layout_mode = 2
theme_override_constants/separation = 16

[node name="Title" type="Label" parent="Margin/Layout"]
layout_mode = 2
text = "REBIND CONTROLS"
horizontal_alignment = 1

[node name="Hint" type="Label" parent="Margin/Layout"]
layout_mode = 2
text = "Click a binding then press the new key, mouse button, or gamepad button. Esc cancels."
horizontal_alignment = 1
autowrap_mode = 2

[node name="Scroll" type="ScrollContainer" parent="Margin/Layout"]
layout_mode = 2
size_flags_vertical = 3

[node name="ActionList" type="VBoxContainer" parent="Margin/Layout/Scroll"]
unique_name_in_owner = true
layout_mode = 2
size_flags_horizontal = 3
theme_override_constants/separation = 4

[node name="Buttons" type="HBoxContainer" parent="Margin/Layout"]
layout_mode = 2
alignment = 1
theme_override_constants/separation = 24

[node name="RestoreButton" type="Button" parent="Margin/Layout/Buttons"]
unique_name_in_owner = true
layout_mode = 2
text = "Restore Defaults"

[node name="SaveButton" type="Button" parent="Margin/Layout/Buttons"]
unique_name_in_owner = true
layout_mode = 2
text = "Save & Close"
'''

REBIND_GD = '''## Auto-generated by input-handling skill. Drop into a scene; the .tscn
## sibling will populate %ActionList with one row per InputMap action.
##
## Persistence is handled by `InputPersistence` (autoload). This screen just
## edits in-memory bindings and signals the autoload to save / restore.
extends Control

const INCLUDE_UI_ACTIONS := {include_ui_literal}
const PERSIST_PATH := "user://input_map.cfg"

var _capturing_action: StringName = &""
var _capture_button: Button = null
var _default_bindings: Dictionary = {{}}    # action -> [InputEvent, ...]

@onready var _list: VBoxContainer = %ActionList
@onready var _save: Button = %SaveButton
@onready var _restore: Button = %RestoreButton


func _ready() -> void:
    _snapshot_defaults()
    _build_rows()
    _save.pressed.connect(_on_save_pressed)
    _restore.pressed.connect(_on_restore_pressed)
    set_process_unhandled_input(true)


func _snapshot_defaults() -> void:
    # Capture project-default bindings so we can restore them later.
    for action in InputMap.get_actions():
        if action.begins_with("ui_") and not INCLUDE_UI_ACTIONS:
            continue
        _default_bindings[action] = InputMap.action_get_events(action).duplicate()


func _build_rows() -> void:
    for child in _list.get_children():
        child.queue_free()
    for action in InputMap.get_actions():
        action = StringName(action)
        if action.begins_with("ui_") and not INCLUDE_UI_ACTIONS:
            continue
        var row := HBoxContainer.new()
        row.size_flags_horizontal = SIZE_EXPAND_FILL
        row.add_theme_constant_override("separation", 12)
        var label := Label.new()
        label.text = str(action)
        label.size_flags_horizontal = SIZE_EXPAND_FILL
        row.add_child(label)
        var bind_button := Button.new()
        bind_button.custom_minimum_size = Vector2(280, 0)
        bind_button.text = _format_binding(action)
        bind_button.pressed.connect(_on_capture_started.bind(action, bind_button))
        row.add_child(bind_button)
        var reset_button := Button.new()
        reset_button.text = "Reset"
        reset_button.pressed.connect(_on_row_reset.bind(action, bind_button))
        row.add_child(reset_button)
        _list.add_child(row)


func _format_binding(action: StringName) -> String:
    var events := InputMap.action_get_events(action)
    if events.is_empty():
        return "(unbound)"
    var labels: Array[String] = []
    for e in events:
        labels.append(_event_label(e))
    return ", ".join(labels)


func _event_label(e: InputEvent) -> String:
    if e is InputEventKey:
        return OS.get_keycode_string(e.physical_keycode if e.physical_keycode != 0 else e.keycode)
    elif e is InputEventMouseButton:
        return "Mouse" + str(e.button_index)
    elif e is InputEventJoypadButton:
        return "Btn" + str(e.button_index)
    elif e is InputEventJoypadMotion:
        var dir := "+" if e.axis_value > 0.0 else "-"
        return "Axis" + str(e.axis) + dir
    return str(e)


# --- Capture ----------------------------------------------------------------

func _on_capture_started(action: StringName, button: Button) -> void:
    if _capturing_action != &"":
        # Cancel previous capture
        _capture_button.text = _format_binding(_capturing_action)
    _capturing_action = action
    _capture_button = button
    button.text = "<press input>"


func _unhandled_input(event: InputEvent) -> void:
    if _capturing_action == &"":
        return
    # Esc cancels capture (UNLESS the action being rebound IS escape-only).
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        if InputMap.action_get_events(_capturing_action).size() == 0 \\
                or _capturing_action != &"pause":
            _capture_button.text = _format_binding(_capturing_action)
            _capturing_action = &""
            _capture_button = null
            get_viewport().set_input_as_handled()
            return
    # Accept first key/button/mouse press; ignore mouse motion + joypad motion <0.5
    var accepted := false
    if event is InputEventKey and event.pressed and not event.echo:
        accepted = true
    elif event is InputEventMouseButton and event.pressed:
        accepted = true
    elif event is InputEventJoypadButton and event.pressed:
        accepted = true
    elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
        accepted = true
    if not accepted:
        return
    # Conflict check
    for other_action in InputMap.get_actions():
        if other_action == _capturing_action:
            continue
        for e in InputMap.action_get_events(other_action):
            if _events_match(e, event):
                push_warning("Input %s already bound to '%s' — overwriting." % [
                    _event_label(event), other_action])
                InputMap.action_erase_event(other_action, e)
    # Replace this action's bindings with the new one.
    InputMap.action_erase_events(_capturing_action)
    InputMap.action_add_event(_capturing_action, event)
    _capture_button.text = _format_binding(_capturing_action)
    _capturing_action = &""
    _capture_button = null
    get_viewport().set_input_as_handled()
    _build_rows()  # refresh other rows in case a conflict erased their binding


func _events_match(a: InputEvent, b: InputEvent) -> bool:
    if a.get_class() != b.get_class():
        return false
    if a is InputEventKey and b is InputEventKey:
        return a.physical_keycode == b.physical_keycode and a.keycode == b.keycode
    if a is InputEventMouseButton and b is InputEventMouseButton:
        return a.button_index == b.button_index
    if a is InputEventJoypadButton and b is InputEventJoypadButton:
        return a.button_index == b.button_index
    if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
        return a.axis == b.axis and signf(a.axis_value) == signf(b.axis_value)
    return false


# --- Persistence ------------------------------------------------------------

func _on_save_pressed() -> void:
    var cfg := ConfigFile.new()
    for action in InputMap.get_actions():
        if action.begins_with("ui_") and not INCLUDE_UI_ACTIONS:
            continue
        var entries: Array = []
        for e in InputMap.action_get_events(action):
            entries.append(_serialize_event(e))
        cfg.set_value("bindings", action, entries)
    cfg.save(PERSIST_PATH)
    queue_free()


func _on_restore_pressed() -> void:
    for action in _default_bindings:
        InputMap.action_erase_events(action)
        for e in _default_bindings[action]:
            InputMap.action_add_event(action, e)
    # Wipe the persisted file so launches go back to project defaults.
    if FileAccess.file_exists(PERSIST_PATH):
        DirAccess.remove_absolute(PERSIST_PATH)
    _build_rows()


func _on_row_reset(action: StringName, button: Button) -> void:
    InputMap.action_erase_events(action)
    for e in _default_bindings.get(action, []):
        InputMap.action_add_event(action, e)
    button.text = _format_binding(action)


func _serialize_event(e: InputEvent) -> Dictionary:
    if e is InputEventKey:
        return {{ "type": "key",
                  "physical_keycode": e.physical_keycode,
                  "keycode": e.keycode }}
    elif e is InputEventMouseButton:
        return {{ "type": "mouse", "button_index": e.button_index }}
    elif e is InputEventJoypadButton:
        return {{ "type": "joybtn", "button_index": e.button_index }}
    elif e is InputEventJoypadMotion:
        return {{ "type": "joyaxis", "axis": e.axis,
                  "axis_value": e.axis_value }}
    return {{}}
'''

PERSISTENCE_GD = '''## Auto-generated by input-handling skill. Add to Project Settings ->
## Autoload as `InputPersistence` (singleton). Loads user://input_map.cfg
## at boot and re-applies overrides on top of the project-default InputMap.
extends Node

const PERSIST_PATH := "user://input_map.cfg"


func _ready() -> void:
    if not FileAccess.file_exists(PERSIST_PATH):
        return
    var cfg := ConfigFile.new()
    var err := cfg.load(PERSIST_PATH)
    if err != OK:
        push_warning("InputPersistence: failed to load %s (err %d)" % [PERSIST_PATH, err])
        return
    if not cfg.has_section("bindings"):
        return
    for action in cfg.get_section_keys("bindings"):
        if not InputMap.has_action(action):
            continue
        InputMap.action_erase_events(action)
        var entries: Array = cfg.get_value("bindings", action, [])
        for entry in entries:
            var ev := _deserialize(entry)
            if ev != null:
                InputMap.action_add_event(action, ev)


func _deserialize(d: Dictionary) -> InputEvent:
    match d.get("type", ""):
        "key":
            var k := InputEventKey.new()
            k.physical_keycode = int(d.get("physical_keycode", 0))
            k.keycode = int(d.get("keycode", 0))
            return k
        "mouse":
            var m := InputEventMouseButton.new()
            m.button_index = int(d.get("button_index", 0))
            return m
        "joybtn":
            var j := InputEventJoypadButton.new()
            j.button_index = int(d.get("button_index", 0))
            return j
        "joyaxis":
            var a := InputEventJoypadMotion.new()
            a.axis = int(d.get("axis", 0))
            a.axis_value = float(d.get("axis_value", 0.0))
            return a
    return null
'''


def _write_rebind_scaffold(out_dir: Path, include_ui: bool) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    gd_path = out_dir / "rebind_screen.gd"
    tscn_path = out_dir / "rebind_screen.tscn"
    persist_path = out_dir / "input_persistence.gd"

    # The .tscn references the .gd via res:// path. We try to infer it relative
    # to the (assumed) project root by walking up until a project.godot is found.
    res_path = _resolve_res_path(gd_path)

    tscn_path.write_text(REBIND_TSCN.format(rebind_gd_res_path=res_path), encoding="utf-8")
    gd_path.write_text(REBIND_GD.format(include_ui_literal=("true" if include_ui else "false")),
                       encoding="utf-8")
    persist_path.write_text(PERSISTENCE_GD, encoding="utf-8")

    return {
        "tscn": str(tscn_path),
        "screen_script": str(gd_path),
        "persistence_autoload_script": str(persist_path),
        "res_path_used": res_path,
        "next_steps": [
            f"Add `{persist_path.name}` as an Autoload (Project Settings -> Autoload) "
            f"named `InputPersistence`. Must run before any scene that polls input.",
            f"Open `{tscn_path.name}` in Godot once to verify the script reference resolves "
            f"to `res://{res_path}` (the inferred path).",
            "Wire your options menu's Rebind button to instance this scene as a child of "
            "the current scene tree root (or push it via a SceneTree.change_scene_to_packed).",
        ],
    }


def _resolve_res_path(absolute_gd_path: Path) -> str:
    """Walk up from absolute_gd_path; return path relative to the dir
    containing project.godot, with forward slashes (Godot's res:// form)."""
    cur = absolute_gd_path.parent
    for _ in range(8):
        if (cur / "project.godot").exists():
            rel = absolute_gd_path.relative_to(cur)
            return rel.as_posix()
        if cur.parent == cur:
            break
        cur = cur.parent
    # Couldn't find a project root — return just the filename. Editor will warn.
    return absolute_gd_path.name


# ---------------------------------------------------------------------------
# Linter
# ---------------------------------------------------------------------------

_ACTION_BLOCK_RE = re.compile(
    r"(?ms)^(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{(?P<body>.*?)\}\s*$"
)

_DEADZONE_RE = re.compile(r'"deadzone"\s*:\s*([\d.]+)')
_HAS_JOY_RE = re.compile(r'InputEventJoypadButton|InputEventJoypadMotion')
_HAS_JOY_AXIS_RE = re.compile(r'InputEventJoypadMotion')
_KEY_PHYSICAL_RE = re.compile(r'"physical_keycode"\s*:\s*(\d+)')
_KEY_CODE_RE = re.compile(r'"keycode"\s*:\s*(\d+)')

_GD_ACTION_REF_RE = re.compile(
    r'Input\.is_action_(?:pressed|just_pressed|just_released)\s*\(\s*[&]?"([^"]+)"'
)


def _lint_project(path: Path, project_root: Path) -> tuple[list, list]:
    errors: list[str] = []
    warnings: list[str] = []
    text = path.read_text(encoding="utf-8")

    section_match = _INPUT_SECTION_RE.search(text)
    if not section_match:
        return ["[input] section missing from project.godot"], []
    block = section_match.group(0)

    actions: dict[str, dict] = {}
    for m in _ACTION_BLOCK_RE.finditer(block):
        body = m.group("body")
        actions[m.group("name")] = {
            "deadzone": float((_DEADZONE_RE.search(body) or ["0", "0"])[1] if _DEADZONE_RE.search(body) else 0.0),
            "has_joy": bool(_HAS_JOY_RE.search(body)),
            "has_joy_axis": bool(_HAS_JOY_AXIS_RE.search(body)),
            "physical_keys": [int(x) for x in _KEY_PHYSICAL_RE.findall(body) if int(x) != 0],
            "raw": body,
        }

    # 1. Built-in ui_* actions that have been overridden.
    builtin_ui = {"ui_accept", "ui_cancel", "ui_left", "ui_right",
                  "ui_up", "ui_down", "ui_focus_next", "ui_focus_prev",
                  "ui_select", "ui_text_submit"}
    for ui_action in builtin_ui & actions.keys():
        warnings.append(
            f"'{ui_action}' is a built-in Godot UI action and is overridden in your input map. "
            f"This will replace Godot's default focus-navigation binding. Usually a mistake — "
            f"if you want gameplay-specific binds for the same direction, add a parallel "
            f"action like 'menu_{ui_action[3:]}' instead.")

    # 2. No-gamepad actions
    for name, info in actions.items():
        if not info["has_joy"] and not name.startswith("ui_"):
            warnings.append(
                f"'{name}' has no gamepad binding. Fine for keyboard-only games; "
                f"otherwise add at least one InputEventJoypadButton or InputEventJoypadMotion.")

    # 3. Zero deadzone on axis-bound actions
    for name, info in actions.items():
        if info["has_joy_axis"] and info["deadzone"] < 0.15:
            warnings.append(
                f"'{name}' binds a joystick axis but has deadzone={info['deadzone']:.2f}. "
                f"Controller drift will trigger ghost inputs — recommend deadzone >= 0.2.")

    # 4. Duplicate physical keys
    key_owners: dict[int, list[str]] = {}
    for name, info in actions.items():
        for kc in info["physical_keys"]:
            key_owners.setdefault(kc, []).append(name)
    for kc, owners in key_owners.items():
        if len(owners) > 1:
            errors.append(
                f"Physical keycode {kc} is bound by multiple actions: {owners}. "
                f"One keypress will fire all of them.")

    # 5. Undeclared actions referenced from .gd files
    declared = set(actions.keys()) | builtin_ui
    referenced: set[str] = set()
    for gd in project_root.rglob("*.gd"):
        try:
            gd_text = gd.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for ref in _GD_ACTION_REF_RE.findall(gd_text):
            referenced.add(ref)
    for ref in sorted(referenced - declared):
        errors.append(
            f"Action '{ref}' is referenced by Input.is_action_* but not declared in [input]. "
            f"Calls will silently return false.")

    return errors, warnings


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def cmd_actions(args) -> None:
    block = _build_input_block(args.template)
    wrote_any = False
    if args.project_godot:
        path = Path(args.project_godot)
        _patch_project_godot(path, block)
        print(f"[input-handling] patched {path} (backup -> {path}.bak)", file=sys.stderr)
        wrote_any = True
    if args.constants:
        out = Path(args.constants)
        _emit_constants_module(args.template, out)
        print(f"[input-handling] wrote constants module -> {out}", file=sys.stderr)
        wrote_any = True
    if not wrote_any:
        # Preview to stdout
        sys.stdout.write(block)


def cmd_rebind(args) -> None:
    out = Path(args.output)
    info = _write_rebind_scaffold(out, include_ui=args.include_ui)
    print(json.dumps({"ok": True, **info}, indent=2))


def cmd_template(args) -> None:
    if args.name not in TEMPLATES:
        raise SystemExit(f"Unknown template {args.name!r}. Available: {', '.join(TEMPLATES)}")
    rows = []
    for name, dz, desc, events in TEMPLATES[args.name]:
        rows.append({
            "action": name, "deadzone": dz, "description": desc,
            "bindings": [list(e) for e in events],
        })
    print(json.dumps({"template": args.name, "actions": rows}, indent=2))


def cmd_lint(args) -> None:
    path = Path(args.project_godot)
    if not path.exists():
        raise SystemExit(f"project.godot not found: {path}")
    project_root = path.parent
    errors, warnings = _lint_project(path, project_root)
    report = {"errors": errors, "warnings": warnings,
              "error_count": len(errors), "warning_count": len(warnings)}
    print(json.dumps(report, indent=2))
    if errors:
        sys.exit(1)


def cmd_list(args) -> None:
    rows = ["Available action templates:"]
    for name, actions in TEMPLATES.items():
        rows.append(f"  {name:11s} ({len(actions):2d} actions)")
    print("\n".join(rows))


def main():
    parser = argparse.ArgumentParser(
        description="input-handling: Godot 4 InputMap + rebinding UI generator")
    sub = parser.add_subparsers(required=True, dest="cmd")

    p = sub.add_parser("actions", help="Emit [input] block, optionally patch project.godot")
    p.add_argument("--template", required=True, choices=list(TEMPLATES))
    p.add_argument("--project-godot", help="Patch this project.godot in place")
    p.add_argument("--constants", help="Write a class_name Actions .gd module here")
    p.set_defaults(func=cmd_actions)

    p = sub.add_parser("rebind", help="Emit rebinding screen scaffold (.tscn + .gd + autoload)")
    p.add_argument("--output", required=True, help="Output directory for the scaffold")
    p.add_argument("--include-ui", action="store_true",
                   help="Include ui_* actions in the rebind list (off by default)")
    p.set_defaults(func=cmd_rebind)

    p = sub.add_parser("template", help="Print one template as JSON")
    p.add_argument("name", choices=list(TEMPLATES))
    p.set_defaults(func=cmd_template)

    p = sub.add_parser("lint", help="Audit project.godot for input-map foot-guns")
    p.add_argument("--project-godot", required=True)
    p.set_defaults(func=cmd_lint)

    p = sub.add_parser("list", help="List action templates")
    p.set_defaults(func=cmd_list)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
