extends Node2D
## res://scripts/boomerang.gd
## Boomerang item (lives as a child of the player, top_level while flying):
## thrown with the item button it flies throw_range in the facing direction,
## then homes back to the player; any "enemies" node touched during either leg
## is stunned once per flight. One boomerang in flight at a time —
## throw_from() no-ops until the previous throw is caught.

enum State { IDLE, OUT, BACK }

@export var speed := 620.0
@export var throw_range := 260.0
@export var stun_duration := 1.6
## An enemy is stunned when it comes within this many pixels of the boomerang.
@export var hit_radius := 26.0
@export var spin_speed := 18.0
## The flight ends when the return leg gets this close to the player.
@export var catch_radius := 28.0

var _state := State.IDLE
var _dir := Vector2.RIGHT
var _travelled := 0.0
var _stunned_this_flight: Array[Node] = []
var _player: Node2D


func _ready() -> void:
	top_level = true
	visible = false
	set_physics_process(false)


func is_idle() -> bool:
	return _state == State.IDLE


## Launch from `player` towards `dir`. Returns false while already in flight.
func throw_from(player: Node2D, dir: Vector2) -> bool:
	if _state != State.IDLE:
		return false
	_player = player
	_dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	global_position = player.global_position
	_travelled = 0.0
	_stunned_this_flight.clear()
	_state = State.OUT
	visible = true
	set_physics_process(true)
	return true


func _physics_process(delta: float) -> void:
	rotation += spin_speed * delta
	match _state:
		State.OUT:
			var step := _dir * speed * delta
			global_position += step
			_travelled += step.length()
			if _travelled >= throw_range:
				_state = State.BACK
		State.BACK:
			if _player == null or not is_instance_valid(_player):
				_catch()
				return
			var to_player := _player.global_position - global_position
			if to_player.length() <= catch_radius:
				_catch()
				return
			global_position += to_player.normalized() * speed * delta
	_stun_touched()


func _stun_touched() -> void:
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if not (enemy is Node2D) or not is_instance_valid(enemy):
			continue
		if _stunned_this_flight.has(enemy) or not enemy.has_method("stun"):
			continue
		if (enemy as Node2D).global_position.distance_to(global_position) <= hit_radius:
			_stunned_this_flight.append(enemy)
			enemy.stun(stun_duration)


func _catch() -> void:
	_state = State.IDLE
	visible = false
	set_physics_process(false)
