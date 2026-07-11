extends CharacterBody2D
## res://scripts/player.gd
## Platformer controller with coyote time, jump buffering and variable jump
## height (game-feel defaults). Metroidvania ability gates live in `abilities`;
## double jump ships as the worked example — grant it with
## `grant_ability(&"double_jump")`.

signal jumped
signal landed

const ACTION_LEFT := &"move_left"
const ACTION_RIGHT := &"move_right"
const ACTION_JUMP := &"jump"

@export var move_speed := 340.0
@export var acceleration := 2200.0
@export var air_acceleration := 1400.0
@export var jump_velocity := -640.0
## Fraction of upward velocity kept when jump is released early.
@export_range(0.0, 1.0) var jump_cut_multiplier := 0.45
@export var coyote_time := 0.09
@export var jump_buffer_time := 0.12
@export var max_fall_speed := 980.0

## Unlocked movement abilities, e.g. [&"double_jump", &"dash", &"wall_jump"].
var abilities: Array[StringName] = []

var _gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var _coyote_left := 0.0
var _buffer_left := 0.0
var _air_jumps_left := 0
var _was_on_floor := false


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()

	# Grounded state and coyote timer.
	if on_floor:
		_coyote_left = coyote_time
		_air_jumps_left = 1 if has_ability(&"double_jump") else 0
	else:
		_coyote_left = maxf(_coyote_left - delta, 0.0)

	# Jump buffering: remember presses slightly before landing.
	if Input.is_action_just_pressed(ACTION_JUMP):
		_buffer_left = jump_buffer_time
	else:
		_buffer_left = maxf(_buffer_left - delta, 0.0)

	# Gravity with terminal velocity.
	if not on_floor:
		velocity.y = minf(velocity.y + _gravity * delta, max_fall_speed)

	# Jump: buffered press consumed by coyote window first, then air jumps.
	if _buffer_left > 0.0:
		if _coyote_left > 0.0:
			_do_jump()
		elif _air_jumps_left > 0:
			_air_jumps_left -= 1
			_do_jump()

	# Variable jump height: cut ascent when jump is released early.
	if Input.is_action_just_released(ACTION_JUMP) and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier

	# Horizontal movement.
	var axis := Input.get_axis(ACTION_LEFT, ACTION_RIGHT)
	var accel := acceleration if on_floor else air_acceleration
	velocity.x = move_toward(velocity.x, axis * move_speed, accel * delta)

	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		landed.emit()
	_was_on_floor = is_on_floor()


func has_ability(ability: StringName) -> bool:
	return ability in abilities


func grant_ability(ability: StringName) -> void:
	if not has_ability(ability):
		abilities.append(ability)


## "persistent" group contract (see templates ABI): return the state to save.
func save_data() -> Dictionary:
	var ability_names: Array = []
	for ability in abilities:
		ability_names.append(String(ability))
	return {
		"position": {"x": position.x, "y": position.y},
		"abilities": ability_names,
	}


func load_data(data: Dictionary) -> void:
	var loaded: Array[StringName] = []
	for ability in data.get("abilities", []):
		loaded.append(StringName(ability))
	abilities = loaded
	var pos: Dictionary = data.get("position", {})
	if pos.has("x") and pos.has("y"):
		position = Vector2(pos.x, pos.y)


func _do_jump() -> void:
	velocity.y = jump_velocity
	_coyote_left = 0.0
	_buffer_left = 0.0
	jumped.emit()
