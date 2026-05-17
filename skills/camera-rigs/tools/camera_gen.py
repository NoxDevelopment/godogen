"""Camera Rigs — Godot 4 camera rig + screen-shake + bounds-clamp scaffolds.

Subcommands
-----------
rig      Emit a named camera rig (.tscn + .gd):
           platformer | topdown | sidescroller | third-person |
           first-person | topdown-3d | cinematic
shake    Emit a screen-shake mixin (2D or 3D).
bounds   Emit a bounds-clamp helper (2D or 3D).
list     List available rigs.

Pure text — no ComfyUI / Tripo3D / etc.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Camera rig .gd templates
# ---------------------------------------------------------------------------

PLATFORMER_GD = '''## Platformer Camera2D with horizontal deadzone, vertical look-ahead.
## Smoothing is frame-rate-independent (exponential damping). Parent under
## the player Node2D, or set `target` to the player's NodePath.
extends Camera2D

@export var target: NodePath
@export var follow_speed: float = 8.0          # exp-damping rate; higher = snappier
@export var enabled: bool = true
@export var deadzone_width: float = 32.0       # pixels of horizontal slack
@export var look_ahead_y: float = 48.0         # pixels camera leads on jump/fall
@export var look_ahead_y_speed: float = 4.0
@export var max_velocity_for_lookahead: float = 600.0
@export var physics_target: bool = false       # set true if target is a physics body

var _target_node: Node2D
var _look_ahead_offset: float = 0.0


func _ready() -> void:
    if target.is_empty():
        push_warning("PlatformerCamera: target NodePath not set; using parent if possible.")
        var p := get_parent()
        if p is Node2D:
            _target_node = p
    else:
        _target_node = get_node_or_null(target)
    process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS if physics_target \\
                       else Camera2D.CAMERA2D_PROCESS_IDLE


func _process(delta: float) -> void:
    if not physics_target:
        _update(delta)


func _physics_process(delta: float) -> void:
    if physics_target:
        _update(delta)


func _update(delta: float) -> void:
    if not enabled or _target_node == null:
        return
    var t := _target_node.global_position
    # Horizontal deadzone: only move when target leaves a band centered on camera.
    var dx := t.x - global_position.x
    if absf(dx) > deadzone_width:
        var target_x := t.x - signf(dx) * deadzone_width
        global_position.x = _damp(global_position.x, target_x, follow_speed, delta)
    # Vertical look-ahead based on target velocity (if available).
    var vy: float = 0.0
    if _target_node.has_method("get_velocity"):
        vy = _target_node.get_velocity().y
    elif "velocity" in _target_node:
        vy = _target_node.velocity.y
    var want_lookahead := clampf(vy / max_velocity_for_lookahead, -1.0, 1.0) * look_ahead_y
    _look_ahead_offset = _damp(_look_ahead_offset, want_lookahead, look_ahead_y_speed, delta)
    global_position.y = _damp(global_position.y, t.y + _look_ahead_offset, follow_speed, delta)


static func _damp(current: float, target_v: float, rate: float, delta: float) -> float:
    # Exponential damping: frame-rate independent equivalent of lerp(a, b, rate*delta)
    return target_v + (current - target_v) * pow(0.5, rate * delta)
'''


TOPDOWN_GD = '''## Top-down Camera2D with symmetric deadzone and optional cursor-aim offset.
extends Camera2D

@export var target: NodePath
@export var follow_speed: float = 8.0
@export var enabled: bool = true
@export var deadzone_radius: float = 24.0
@export var aim_toward_cursor: bool = {aim_default}
@export var aim_offset_distance: float = 96.0
@export var aim_offset_speed: float = 6.0
@export var physics_target: bool = false

var _target_node: Node2D
var _aim_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
    if target.is_empty():
        var p := get_parent()
        if p is Node2D:
            _target_node = p
    else:
        _target_node = get_node_or_null(target)
    process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS if physics_target \\
                       else Camera2D.CAMERA2D_PROCESS_IDLE


func _process(delta: float) -> void:
    if not physics_target:
        _update(delta)

func _physics_process(delta: float) -> void:
    if physics_target:
        _update(delta)


func _update(delta: float) -> void:
    if not enabled or _target_node == null:
        return
    var t := _target_node.global_position
    var diff := t - global_position
    if diff.length() > deadzone_radius:
        var pull := diff.normalized() * (diff.length() - deadzone_radius)
        var want := global_position + pull
        global_position = _damp_v(global_position, want, follow_speed, delta)
    # Aim toward cursor — shifts the camera toward where the mouse points.
    if aim_toward_cursor:
        var mouse_world := get_global_mouse_position()
        var to_mouse := (mouse_world - t).limit_length(aim_offset_distance)
        _aim_offset = _damp_v(_aim_offset, to_mouse, aim_offset_speed, delta)
        offset = _aim_offset
    else:
        offset = Vector2.ZERO


static func _damp_v(current: Vector2, target_v: Vector2, rate: float, delta: float) -> Vector2:
    return target_v + (current - target_v) * pow(0.5, rate * delta)
'''


SIDESCROLLER_GD = '''## Sidescroller Camera2D: tight horizontal lock, fixed vertical position
## (Metroid / Castlevania feel). Vertical changes only between rooms.
extends Camera2D

@export var target: NodePath
@export var follow_speed: float = 10.0
@export var enabled: bool = true
@export var horizontal_deadzone: float = 16.0
@export var fixed_y: float = 0.0  # set to the vertical level for current room

var _target_node: Node2D


func _ready() -> void:
    if target.is_empty():
        var p := get_parent()
        if p is Node2D:
            _target_node = p
    else:
        _target_node = get_node_or_null(target)


func _process(delta: float) -> void:
    if not enabled or _target_node == null:
        return
    var tx := _target_node.global_position.x
    var dx := tx - global_position.x
    if absf(dx) > horizontal_deadzone:
        var want_x := tx - signf(dx) * horizontal_deadzone
        global_position.x = want_x + (global_position.x - want_x) * pow(0.5, follow_speed * delta)
    global_position.y = fixed_y
'''


THIRD_PERSON_TSCN = '''[gd_scene load_steps=2 format=3 uid="uid://b_third_person_camera"]

[ext_resource type="Script" path="res://{gd_res_path}" id="1_script"]

[node name="ThirdPersonCameraRig" type="Node3D"]
script = ExtResource("1_script")

[node name="YawPivot" type="Node3D" parent="."]

[node name="PitchPivot" type="Node3D" parent="YawPivot"]

[node name="SpringArm3D" type="SpringArm3D" parent="YawPivot/PitchPivot"]
spring_length = 4.5
margin = 0.05

[node name="Camera3D" type="Camera3D" parent="YawPivot/PitchPivot/SpringArm3D"]
current = true
fov = 65.0
'''

THIRD_PERSON_GD = '''## Third-person Camera3D rig: yaw pivot -> pitch pivot -> SpringArm3D -> Camera3D.
## SpringArm handles wall collision so the camera pulls in when geometry intrudes.
extends Node3D

@export var target: NodePath
@export var follow_speed: float = 10.0
@export var enabled: bool = true
@export var mouse_sensitivity: float = 0.0025
@export var gamepad_sensitivity: float = 2.5    # rad/sec at full stick
@export var pitch_min: float = -1.2             # ~ -70 degrees
@export var pitch_max: float = 1.0              # ~ +57 degrees
@export var spring_length_min: float = 1.5
@export var spring_length_max: float = 8.0
@export var zoom_sensitivity: float = 0.5

var _target_node: Node3D
var _yaw: Node3D
var _pitch: Node3D
var _arm: SpringArm3D
var _yaw_angle: float = 0.0
var _pitch_angle: float = -0.3


func _ready() -> void:
    _yaw = $YawPivot
    _pitch = $YawPivot/PitchPivot
    _arm = $YawPivot/PitchPivot/SpringArm3D
    if target.is_empty():
        var p := get_parent()
        if p is Node3D:
            _target_node = p
    else:
        _target_node = get_node_or_null(target)


func _unhandled_input(event: InputEvent) -> void:
    if not enabled:
        return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        _yaw_angle -= event.relative.x * mouse_sensitivity
        _pitch_angle = clampf(_pitch_angle - event.relative.y * mouse_sensitivity,
                              pitch_min, pitch_max)
    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            _arm.spring_length = clampf(_arm.spring_length - zoom_sensitivity,
                                         spring_length_min, spring_length_max)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            _arm.spring_length = clampf(_arm.spring_length + zoom_sensitivity,
                                         spring_length_min, spring_length_max)


func _process(delta: float) -> void:
    if not enabled or _target_node == null:
        return
    # Right-stick look (additive to mouse).
    if InputMap.has_action("look_left") and InputMap.has_action("look_right"):
        var stick_x := Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
        var stick_y := Input.get_action_strength("look_down") - Input.get_action_strength("look_up")
        _yaw_angle -= stick_x * gamepad_sensitivity * delta
        _pitch_angle = clampf(_pitch_angle - stick_y * gamepad_sensitivity * delta,
                              pitch_min, pitch_max)
    _yaw.rotation.y = _yaw_angle
    _pitch.rotation.x = _pitch_angle
    # Follow target with exp-damping.
    var t_pos := _target_node.global_position
    global_position = t_pos + (global_position - t_pos) * pow(0.5, follow_speed * delta)
'''


FIRST_PERSON_TSCN = '''[gd_scene load_steps=2 format=3 uid="uid://b_first_person_camera"]

[ext_resource type="Script" path="res://{gd_res_path}" id="1_script"]

[node name="FirstPersonCamera" type="Camera3D"]
current = true
fov = 75.0
script = ExtResource("1_script")
'''

FIRST_PERSON_GD = '''## First-person Camera3D with mouse-look (pitch-clamped), optional headbob,
## and optional ADS zoom triggered by an "aim" InputMap action.
extends Camera3D

@export var mouse_sensitivity: float = 0.0025
@export var pitch_min: float = -1.54   # -88 degrees
@export var pitch_max: float = 1.54    # +88 degrees
@export var headbob_amplitude: float = 0.04
@export var headbob_frequency: float = 8.0
@export var zoom_aim: bool = {zoom_aim_default}
@export var zoom_fov: float = 45.0
@export var zoom_speed: float = 10.0
@export var capture_mouse_on_ready: bool = true

var _yaw: float = 0.0
var _pitch: float = 0.0
var _bob_phase: float = 0.0
var _base_fov: float
var _target_fov: float


func _ready() -> void:
    _base_fov = fov
    _target_fov = fov
    if capture_mouse_on_ready:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        _yaw -= event.relative.x * mouse_sensitivity
        _pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, pitch_min, pitch_max)


func _process(delta: float) -> void:
    rotation = Vector3(_pitch, _yaw, 0.0)
    # ADS / aim zoom
    if zoom_aim and InputMap.has_action("aim"):
        _target_fov = zoom_fov if Input.is_action_pressed("aim") else _base_fov
        fov += (_target_fov - fov) * (1.0 - pow(0.5, zoom_speed * delta))
    # Headbob (only when parent moves horizontally — checks parent velocity if available).
    var p := get_parent()
    var moving := false
    if p != null:
        if p.has_method("get_velocity"):
            var v: Vector3 = p.get_velocity()
            moving = Vector2(v.x, v.z).length() > 0.5
        elif "velocity" in p:
            var v2: Vector3 = p.velocity
            moving = Vector2(v2.x, v2.z).length() > 0.5
    if moving:
        _bob_phase += delta * headbob_frequency
        h_offset = sin(_bob_phase) * headbob_amplitude * 0.5
        v_offset = absf(cos(_bob_phase)) * headbob_amplitude
    else:
        _bob_phase = 0.0
        h_offset = lerpf(h_offset, 0.0, 1.0 - pow(0.5, 12.0 * delta))
        v_offset = lerpf(v_offset, 0.0, 1.0 - pow(0.5, 12.0 * delta))
'''


TOPDOWN_3D_TSCN = '''[gd_scene load_steps=2 format=3 uid="uid://b_topdown3d_camera"]

[ext_resource type="Script" path="res://{gd_res_path}" id="1_script"]

[node name="TopDown3DCamera" type="Camera3D"]
current = true
fov = 55.0
projection = 1
size = 15.0
transform = Transform3D(1, 0, 0, 0, 0.5, 0.866, 0, -0.866, 0.5, 0, 12, 8)
script = ExtResource("1_script")
'''

TOPDOWN_3D_GD = '''## Top-down 3D Camera (orthogonal projection, ~60° tilt — isometric-ish look).
## Smoothly follows a target on its XZ plane while holding the tilt + height.
extends Camera3D

@export var target: NodePath
@export var follow_speed: float = 8.0
@export var enabled: bool = true
@export var height: float = 12.0
@export var distance: float = 8.0
@export var pitch_degrees: float = -60.0

var _target_node: Node3D


func _ready() -> void:
    if target.is_empty():
        var p := get_parent()
        if p is Node3D and p != self:
            _target_node = p
    else:
        _target_node = get_node_or_null(target)
    rotation_degrees = Vector3(pitch_degrees, 0, 0)


func _process(delta: float) -> void:
    if not enabled or _target_node == null:
        return
    var t := _target_node.global_position
    var want := Vector3(t.x, t.y + height, t.z + distance)
    global_position = want + (global_position - want) * pow(0.5, follow_speed * delta)
'''


CINEMATIC_2D_GD = '''## Cinematic Camera2D: tween-driven dolly between named markers in a Dictionary.
## Markers are Node2D children; play(name, seconds) tweens to that marker.
extends Camera2D

@export var markers_parent: NodePath
@export var default_easing: int = Tween.EASE_IN_OUT
@export var default_trans: int = Tween.TRANS_SINE

var _markers: Dictionary = {}
var _tween: Tween

signal cinematic_finished(marker_name: String)


func _ready() -> void:
    if not markers_parent.is_empty():
        var p := get_node_or_null(markers_parent)
        if p != null:
            for child in p.get_children():
                if child is Node2D:
                    _markers[child.name] = child


func play(marker_name: String, duration: float = 1.0) -> void:
    if not _markers.has(marker_name):
        push_error("CinematicCamera2D: no marker named '%s'" % marker_name)
        return
    var target_pos: Vector2 = _markers[marker_name].global_position
    if _tween != null and _tween.is_running():
        _tween.kill()
    _tween = create_tween().set_ease(default_easing).set_trans(default_trans)
    _tween.tween_property(self, "global_position", target_pos, duration)
    _tween.finished.connect(func(): cinematic_finished.emit(marker_name))
'''


CINEMATIC_3D_GD = '''## Cinematic Camera3D: tween-driven dolly between named markers (Node3D children).
extends Camera3D

@export var markers_parent: NodePath
@export var default_easing: int = Tween.EASE_IN_OUT
@export var default_trans: int = Tween.TRANS_SINE

var _markers: Dictionary = {}
var _tween: Tween

signal cinematic_finished(marker_name: String)


func _ready() -> void:
    if not markers_parent.is_empty():
        var p := get_node_or_null(markers_parent)
        if p != null:
            for child in p.get_children():
                if child is Node3D:
                    _markers[child.name] = child


func play(marker_name: String, duration: float = 1.0) -> void:
    if not _markers.has(marker_name):
        push_error("CinematicCamera3D: no marker named '%s'" % marker_name)
        return
    var marker: Node3D = _markers[marker_name]
    if _tween != null and _tween.is_running():
        _tween.kill()
    _tween = create_tween().set_ease(default_easing).set_trans(default_trans).set_parallel(true)
    _tween.tween_property(self, "global_position", marker.global_position, duration)
    _tween.tween_property(self, "rotation", marker.rotation, duration)
    _tween.chain().tween_callback(func(): cinematic_finished.emit(marker_name))
'''


# --- Plain .tscn templates for the 2D rigs (Camera2D in a .tscn that
#     references the .gd we just emitted). ---

CAMERA2D_TSCN = '''[gd_scene load_steps=2 format=3 uid="uid://b_camera2d_{kind}"]

[ext_resource type="Script" path="res://{gd_res_path}" id="1_script"]

[node name="{node_name}" type="Camera2D"]
script = ExtResource("1_script")
'''


# ---------------------------------------------------------------------------
# Shake mixin templates
# ---------------------------------------------------------------------------

SHAKE_2D_GD = '''## Screen-shake mixin for Camera2D. Attach to your camera node.
## Multiple shake() calls stack via max-envelope (not sum), preventing runaway.
extends Camera2D

@export var decay_exp: float = 2.0
@export var noise_seed: int = 12345

var _shake_envelopes: Array = []  # each: {intensity, duration, elapsed, frequency, seed_off}
var _noise: FastNoiseLite


func _ready() -> void:
    _noise = FastNoiseLite.new()
    _noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    _noise.seed = noise_seed
    _noise.frequency = 1.0


func shake(intensity: float, duration: float, frequency: float = 30.0) -> void:
    _shake_envelopes.append({
        "intensity": intensity, "duration": maxf(duration, 0.01),
        "elapsed": 0.0, "frequency": frequency,
        "seed_off": Vector2(randf() * 1000.0, randf() * 1000.0),
    })


func _process(delta: float) -> void:
    if _shake_envelopes.is_empty():
        if offset != Vector2.ZERO:
            offset = Vector2.ZERO
        return
    var max_amp: float = 0.0
    var combined := Vector2.ZERO
    var i := _shake_envelopes.size() - 1
    while i >= 0:
        var e: Dictionary = _shake_envelopes[i]
        e["elapsed"] += delta
        var t: float = e["elapsed"] / e["duration"]
        if t >= 1.0:
            _shake_envelopes.remove_at(i)
        else:
            var amp: float = e["intensity"] * pow(1.0 - t, decay_exp)
            if amp > max_amp:
                var seed_off: Vector2 = e["seed_off"]
                var nx := _noise.get_noise_2d(e["elapsed"] * e["frequency"] + seed_off.x, 0.0)
                var ny := _noise.get_noise_2d(0.0, e["elapsed"] * e["frequency"] + seed_off.y)
                combined = Vector2(nx, ny) * amp
                max_amp = amp
        i -= 1
    offset = combined
'''


SHAKE_3D_GD = '''## Screen-shake mixin for Camera3D. Attach to your camera node.
## Multiple shake() calls stack via max-envelope.
extends Camera3D

@export var decay_exp: float = 2.0
@export var noise_seed: int = 12345

var _shake_envelopes: Array = []
var _noise: FastNoiseLite
var _base_local: Vector3


func _ready() -> void:
    _noise = FastNoiseLite.new()
    _noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    _noise.seed = noise_seed
    _noise.frequency = 1.0
    _base_local = position


func shake(intensity: float, duration: float, frequency: float = 30.0) -> void:
    _shake_envelopes.append({
        "intensity": intensity, "duration": maxf(duration, 0.01),
        "elapsed": 0.0, "frequency": frequency,
        "seed_off": Vector3(randf() * 1000.0, randf() * 1000.0, randf() * 1000.0),
    })


func _process(delta: float) -> void:
    if _shake_envelopes.is_empty():
        if position != _base_local:
            position = _base_local
        return
    var max_amp: float = 0.0
    var combined := Vector3.ZERO
    var i := _shake_envelopes.size() - 1
    while i >= 0:
        var e: Dictionary = _shake_envelopes[i]
        e["elapsed"] += delta
        var t: float = e["elapsed"] / e["duration"]
        if t >= 1.0:
            _shake_envelopes.remove_at(i)
        else:
            var amp: float = e["intensity"] * pow(1.0 - t, decay_exp)
            if amp > max_amp:
                var seed_off: Vector3 = e["seed_off"]
                var nx := _noise.get_noise_2d(e["elapsed"] * e["frequency"] + seed_off.x, 0.0)
                var ny := _noise.get_noise_2d(0.0, e["elapsed"] * e["frequency"] + seed_off.y)
                var nz := _noise.get_noise_2d(seed_off.z, e["elapsed"] * e["frequency"])
                combined = Vector3(nx, ny, nz) * amp
                max_amp = amp
        i -= 1
    position = _base_local + combined
'''


# ---------------------------------------------------------------------------
# Bounds-clamp templates
# ---------------------------------------------------------------------------

BOUNDS_2D_GD = '''## Bounds clamp for Camera2D. Godot's built-in Camera2D.limit_left/right/top/
## bottom does the heavy lifting; this helper sets them from a Rect2 resource
## (e.g. loaded from a per-room CameraBounds.tres).
extends Node

@export var camera_path: NodePath
@export var bounds: Rect2 = Rect2(0, 0, 1920, 1080)


func _ready() -> void:
    apply_bounds(bounds)


func apply_bounds(rect: Rect2) -> void:
    bounds = rect
    var cam := get_node_or_null(camera_path) as Camera2D
    if cam == null:
        push_warning("Bounds2D: camera_path not pointing at a Camera2D.")
        return
    cam.limit_left = int(rect.position.x)
    cam.limit_top = int(rect.position.y)
    cam.limit_right = int(rect.position.x + rect.size.x)
    cam.limit_bottom = int(rect.position.y + rect.size.y)
'''


BOUNDS_3D_GD = '''## Bounds clamp for Camera3D. Run as a sibling of the camera and pin its
## global_position to an AABB every _process(). Use AABB.size = Vector3.ZERO
## (default) to disable.
extends Node

@export var camera_path: NodePath
@export var bounds: AABB = AABB(Vector3.ZERO, Vector3.ZERO)


func _process(_delta: float) -> void:
    if bounds.size == Vector3.ZERO:
        return
    var cam := get_node_or_null(camera_path) as Camera3D
    if cam == null:
        return
    var p := cam.global_position
    var lo := bounds.position
    var hi := bounds.position + bounds.size
    cam.global_position = Vector3(
        clampf(p.x, lo.x, hi.x),
        clampf(p.y, lo.y, hi.y),
        clampf(p.z, lo.z, hi.z),
    )
'''


# ---------------------------------------------------------------------------
# Rig catalog
# ---------------------------------------------------------------------------

# Each entry: (gd_source, tscn_source_or_None, gd_filename, tscn_filename, node_name)
RIGS: dict = {
    "platformer": (PLATFORMER_GD, CAMERA2D_TSCN, "platformer_camera.gd",
                   "platformer_camera.tscn", "PlatformerCamera"),
    "topdown": (TOPDOWN_GD, CAMERA2D_TSCN, "topdown_camera.gd",
                "topdown_camera.tscn", "TopDownCamera"),
    "sidescroller": (SIDESCROLLER_GD, CAMERA2D_TSCN, "sidescroller_camera.gd",
                     "sidescroller_camera.tscn", "SidescrollerCamera"),
    "third-person": (THIRD_PERSON_GD, THIRD_PERSON_TSCN, "third_person_camera.gd",
                     "third_person_camera.tscn", None),
    "first-person": (FIRST_PERSON_GD, FIRST_PERSON_TSCN, "first_person_camera.gd",
                     "first_person_camera.tscn", None),
    "topdown-3d": (TOPDOWN_3D_GD, TOPDOWN_3D_TSCN, "topdown_3d_camera.gd",
                   "topdown_3d_camera.tscn", None),
    "cinematic": (None, None, None, None, None),  # handled specially
}


# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------

def _resolve_res_path(absolute_gd_path: Path) -> str:
    cur = absolute_gd_path.parent
    for _ in range(8):
        if (cur / "project.godot").exists():
            return absolute_gd_path.relative_to(cur).as_posix()
        if cur.parent == cur:
            break
        cur = cur.parent
    return absolute_gd_path.name


def _resolve_output_dir(arg: str) -> Path:
    if arg.startswith("res://"):
        return Path(arg[len("res://"):])
    return Path(arg)


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

def cmd_rig(args) -> None:
    kind = args.kind
    out_dir = _resolve_output_dir(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    if kind == "cinematic":
        dim = args.dim
        if dim not in ("2d", "3d"):
            raise SystemExit("--dim must be '2d' or '3d' for cinematic")
        gd_src = CINEMATIC_2D_GD if dim == "2d" else CINEMATIC_3D_GD
        gd_filename = f"cinematic_camera_{dim}.gd"
        gd_path = out_dir / gd_filename
        gd_path.write_text(gd_src, encoding="utf-8")
        if dim == "2d":
            tscn_path = out_dir / "cinematic_camera_2d.tscn"
            tscn_src = CAMERA2D_TSCN.format(
                kind="cinematic",
                gd_res_path=_resolve_res_path(gd_path),
                node_name="CinematicCamera2D",
            )
        else:
            tscn_path = out_dir / "cinematic_camera_3d.tscn"
            tscn_src = (f'[gd_scene load_steps=2 format=3 '
                        f'uid="uid://b_cinematic_camera_3d"]\n\n'
                        f'[ext_resource type="Script" '
                        f'path="res://{_resolve_res_path(gd_path)}" id="1_script"]\n\n'
                        f'[node name="CinematicCamera3D" type="Camera3D"]\n'
                        f'current = true\n'
                        f'script = ExtResource("1_script")\n')
        tscn_path.write_text(tscn_src, encoding="utf-8")
        print(json.dumps({"ok": True, "kind": "cinematic", "dim": dim,
                          "gd": str(gd_path), "tscn": str(tscn_path)}, indent=2))
        return

    if kind not in RIGS:
        raise SystemExit(f"Unknown rig {kind!r}. Available: {', '.join(RIGS)}")
    gd_src, tscn_template, gd_filename, tscn_filename, node_name = RIGS[kind]
    gd_path = out_dir / gd_filename
    tscn_path = out_dir / tscn_filename

    # Format-string substitutions per kind
    if kind == "topdown":
        gd_src = gd_src.format(aim_default=("true" if args.aim else "false"))
    elif kind == "first-person":
        gd_src = gd_src.format(zoom_aim_default=("true" if args.zoom_aim else "false"))

    gd_path.write_text(gd_src, encoding="utf-8")
    res_path = _resolve_res_path(gd_path)
    if tscn_template is CAMERA2D_TSCN:
        tscn_src = tscn_template.format(
            kind=kind.replace("-", "_"),
            gd_res_path=res_path, node_name=node_name,
        )
    else:
        tscn_src = tscn_template.format(gd_res_path=res_path)
    tscn_path.write_text(tscn_src, encoding="utf-8")

    print(json.dumps({"ok": True, "kind": kind,
                      "gd": str(gd_path), "tscn": str(tscn_path)}, indent=2))


def cmd_shake(args) -> None:
    if args.dim not in ("2d", "3d"):
        raise SystemExit("--dim must be '2d' or '3d'")
    out_dir = _resolve_output_dir(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)
    src = SHAKE_2D_GD if args.dim == "2d" else SHAKE_3D_GD
    path = out_dir / (f"screen_shake_{args.dim}.gd")
    path.write_text(src, encoding="utf-8")
    print(json.dumps({"ok": True, "dim": args.dim, "wrote": str(path),
                      "usage": "Replace your camera node's script with this, OR copy "
                               "the shake() method onto your existing camera script."},
                     indent=2))


def cmd_bounds(args) -> None:
    if args.dim not in ("2d", "3d"):
        raise SystemExit("--dim must be '2d' or '3d'")
    out_dir = _resolve_output_dir(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)
    src = BOUNDS_2D_GD if args.dim == "2d" else BOUNDS_3D_GD
    path = out_dir / (f"camera_bounds_{args.dim}.gd")
    path.write_text(src, encoding="utf-8")
    print(json.dumps({"ok": True, "dim": args.dim, "wrote": str(path)}, indent=2))


def cmd_list(_args) -> None:
    rows = ["Available rigs:"]
    for name in RIGS:
        rows.append(f"  {name}")
    rows += ["", "Shake mixins:  --dim 2d|3d", "Bounds clamps: --dim 2d|3d"]
    print("\n".join(rows))


def main():
    parser = argparse.ArgumentParser(description="camera-rigs: Godot 4 camera scaffolds")
    sub = parser.add_subparsers(required=True, dest="cmd")

    p = sub.add_parser("rig", help="Emit a camera rig (.tscn + .gd)")
    p.add_argument("--kind", required=True, choices=list(RIGS))
    p.add_argument("--output", required=True, help="Output directory")
    p.add_argument("--aim", action="store_true",
                   help="topdown: enable aim-toward-cursor by default")
    p.add_argument("--zoom-aim", action="store_true",
                   help="first-person: enable ADS zoom via 'aim' action")
    p.add_argument("--dim", choices=["2d", "3d"],
                   help="cinematic only: 2d or 3d")
    p.set_defaults(func=cmd_rig)

    p = sub.add_parser("shake", help="Emit screen-shake mixin")
    p.add_argument("--dim", required=True, choices=["2d", "3d"])
    p.add_argument("--output", required=True)
    p.set_defaults(func=cmd_shake)

    p = sub.add_parser("bounds", help="Emit bounds-clamp helper")
    p.add_argument("--dim", required=True, choices=["2d", "3d"])
    p.add_argument("--output", required=True)
    p.set_defaults(func=cmd_bounds)

    p = sub.add_parser("list", help="List available rigs")
    p.set_defaults(func=cmd_list)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
