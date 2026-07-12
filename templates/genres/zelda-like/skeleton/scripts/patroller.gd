extends "res://scripts/enemy_base.gd"
## res://scripts/patroller.gd
## Patroller archetype: ping-pongs along patrol_axis, patrol_extent pixels each
## way from its start position, flipping at the ends or when it bumps a wall.
## Touch damage, sword-killable and boomerang-stunnable via the shared chassis.

@export var patrol_axis := Vector2.RIGHT
## Pixels travelled each way from the start position.
@export var patrol_extent := 180.0

var _origin := Vector2.ZERO
var _patrol_dir := 1.0


func _ready() -> void:
	super()
	_origin = global_position


func _move(_delta: float, _player: Node2D) -> void:
	var target := _origin + patrol_axis.normalized() * patrol_extent * _patrol_dir
	if global_position.distance_to(target) <= 8.0 or get_slide_collision_count() > 0:
		_patrol_dir = -_patrol_dir
		target = _origin + patrol_axis.normalized() * patrol_extent * _patrol_dir
	velocity = (target - global_position).normalized() * move_speed
