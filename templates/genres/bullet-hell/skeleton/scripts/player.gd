extends CharacterBody2D
## res://scripts/player.gd
## Bullet-hell player ship: 8-directional movement clamped to the arena,
## bullet-hit detection through BulletUpHell's collision signal, lives with a
## post-hit invulnerability window and respawn at the starting position.
##
## BulletUpHell conventions used here:
## - the ship is in group "Player" (capital P) — the spawner auto-despawns any
##   bullet that touches a body in that group;
## - it registers itself as the "Player" special target so homing patterns can
##   reference it without a NodePath.

signal lives_changed(current: int, max_lives: int)
signal died

const ACTION_UP := &"move_up"
const ACTION_DOWN := &"move_down"
const ACTION_LEFT := &"move_left"
const ACTION_RIGHT := &"move_right"
const ACTION_FOCUS := &"dash"

@export var move_speed := 420.0
## Held "dash" slows the ship for precision dodging (shmup focus mode).
@export var focus_speed := 180.0
@export var max_lives := 3
## Seconds of invulnerability after losing a life.
@export var hurt_grace := 1.5
## Playfield the ship is clamped to (matches the arena walls).
@export var arena_bounds := Rect2(48, 48, 1056, 552)

var lives: int
var _spawn_position: Vector2
var _grace_left := 0.0

@onready var _visual: Polygon2D = $Visual

var _base_color: Color


func _ready() -> void:
	lives = max_lives
	_spawn_position = position
	_base_color = _visual.color
	Spawning.edit_special_target("Player", self)
	Spawning.bullet_collided_body.connect(_on_bullet_collided_body)
	lives_changed.emit(lives, max_lives)


func _physics_process(delta: float) -> void:
	if _grace_left > 0.0:
		_grace_left = maxf(_grace_left - delta, 0.0)
		_visual.color.a = 0.4 if int(_grace_left * 12.0) % 2 == 0 else 0.9
		if _grace_left <= 0.0:
			_visual.color.a = 1.0

	var axis := Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN)
	var speed := focus_speed if Input.is_action_pressed(ACTION_FOCUS) else move_speed
	velocity = axis * speed
	move_and_slide()
	position = position.clamp(
		arena_bounds.position, arena_bounds.position + arena_bounds.size
	)


func take_hit(damage: int, _from: Node) -> void:
	if _grace_left > 0.0:
		return
	_grace_left = hurt_grace
	lives = maxi(lives - damage, 0)
	lives_changed.emit(lives, max_lives)
	if lives <= 0:
		_die()


## "persistent" group contract (see templates ABI): return the state to save.
func save_data() -> Dictionary:
	return {
		"position": {"x": position.x, "y": position.y},
		"lives": lives,
	}


func load_data(data: Dictionary) -> void:
	lives = int(data.get("lives", max_lives))
	lives_changed.emit(lives, max_lives)
	var pos: Dictionary = data.get("position", {})
	if pos.has("x") and pos.has("y"):
		position = Vector2(pos.x, pos.y)


func _on_bullet_collided_body(body: Node, _body_shape_index: int, _bullet: Dictionary,
		_local_shape_index: int, _shared_area: Area2D) -> void:
	if body == self:
		take_hit(1, null)


func _die() -> void:
	died.emit()
	# Classic shmup respawn: back to the start position with full lives.
	position = _spawn_position
	velocity = Vector2.ZERO
	lives = max_lives
	_grace_left = hurt_grace
	lives_changed.emit(lives, max_lives)
