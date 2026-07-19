extends CharacterBody2D
## res://scripts/enemy_base.gd
## Shared enemy chassis for the Zelda-like: health + take_hit contract,
## boomerang stun, touch damage on a cooldown, and per-room activation — rooms
## call set_room_active() when the player enters/leaves, so only the current
## screen's enemies ever run (classic Zelda). Subclasses implement
## _move(delta, player) to set velocity; the chassis does the rest.

signal destroyed(enemy: Node, pos: Vector2)

@export var move_speed := 120.0
@export var max_health := 2
@export var contact_damage := 1
## The player takes contact damage inside this distance, in pixels.
@export var contact_range := 34.0
@export var contact_cooldown := 0.9

const STUN_COLOR := Color(0.55, 0.85, 0.9)

var health: int
var _stun_left := 0.0
var _contact_cd_left := 0.0
var _base_color: Color

@onready var _visual: Polygon2D = $Visual


func _ready() -> void:
	health = max_health
	_base_color = _visual.color
	# Rooms own activation: enemies sleep until their room becomes current
	# (main.gd activates the starting room on boot).
	set_physics_process(false)


## Called by the enemy's room when the player enters/leaves it.
func set_room_active(active: bool) -> void:
	set_physics_process(active)


func _physics_process(delta: float) -> void:
	_contact_cd_left = maxf(_contact_cd_left - delta, 0.0)

	if _stun_left > 0.0:
		_stun_left -= delta
		velocity = Vector2.ZERO
		if _stun_left <= 0.0:
			_visual.color = _base_color
		return

	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	_move(delta, player)
	move_and_slide()

	if player != null and _contact_cd_left <= 0.0 \
			and global_position.distance_to(player.global_position) <= contact_range \
			and player.has_method("take_hit"):
		_contact_cd_left = contact_cooldown
		player.take_hit(contact_damage, self)


## Subclass hook: set `velocity` for this frame. `player` may be null.
func _move(_delta: float, _player: Node2D) -> void:
	velocity = Vector2.ZERO


## Boomerang contract: freeze in place for `duration` seconds.
func stun(duration: float) -> void:
	_stun_left = maxf(_stun_left, duration)
	_visual.color = STUN_COLOR


## True while frozen by a boomerang hit (used by the boot probe).
func is_stunned() -> bool:
	return _stun_left > 0.0


func take_hit(damage: int, _from: Node) -> void:
	health = maxi(health - damage, 0)
	_visual.color = Color(1.0, 1.0, 1.0)
	var tween := create_tween()
	tween.tween_property(_visual, "color", _base_color, 0.15)
	if health <= 0:
		destroyed.emit(self, global_position)
		queue_free()
