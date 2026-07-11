extends CharacterBody2D
## res://scripts/player.gd
## Top-down action controller: 8-directional movement, mouse aim, hitscan
## (raycast) shot with a visible tracer, dash with cooldown, health with a
## brief invulnerability window after each hit.

signal health_changed(current: int, max_health: int)
signal shot_fired(from: Vector2, to: Vector2, hit: Object)
signal died

const ACTION_UP := &"move_up"
const ACTION_DOWN := &"move_down"
const ACTION_LEFT := &"move_left"
const ACTION_RIGHT := &"move_right"
const ACTION_ATTACK := &"attack"
const ACTION_DASH := &"dash"

@export var move_speed := 320.0
@export var acceleration := 2600.0
@export var friction := 2200.0
@export var max_health := 5
## Hitscan range of one shot, in pixels.
@export var shot_range := 900.0
@export var shot_damage := 1
@export var shot_cooldown := 0.18
## Physics layers a shot can hit (world + enemies).
@export_flags_2d_physics var shot_mask := 0b101
@export var dash_speed := 900.0
@export var dash_duration := 0.15
@export var dash_cooldown := 0.6
## Seconds of invulnerability after taking a hit.
@export var hurt_grace := 0.5

var health: int
var _spawn_position: Vector2
var _shot_cd_left := 0.0
var _dash_cd_left := 0.0
var _dash_left := 0.0
var _dash_dir := Vector2.ZERO
var _grace_left := 0.0
var _tracer_left := 0.0

@onready var _aim_pivot: Node2D = $AimPivot
@onready var _muzzle: Marker2D = $AimPivot/Muzzle
@onready var _tracer: Line2D = $Tracer
@onready var _body_visual: Polygon2D = $Body


func _ready() -> void:
	health = max_health
	_spawn_position = position
	_tracer.top_level = true
	_tracer.visible = false
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	_shot_cd_left = maxf(_shot_cd_left - delta, 0.0)
	_dash_cd_left = maxf(_dash_cd_left - delta, 0.0)
	_grace_left = maxf(_grace_left - delta, 0.0)
	_update_tracer(delta)

	# Mouse aim: the pivot (barrel + muzzle) tracks the cursor.
	_aim_pivot.rotation = (get_global_mouse_position() - global_position).angle()

	var axis := Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN)

	# Dash: burst along the movement direction (aim direction when standing still).
	if Input.is_action_just_pressed(ACTION_DASH) and _dash_cd_left <= 0.0:
		_dash_dir = axis.normalized() if axis != Vector2.ZERO \
				else Vector2.RIGHT.rotated(_aim_pivot.rotation)
		_dash_left = dash_duration
		_dash_cd_left = dash_cooldown

	if _dash_left > 0.0:
		_dash_left -= delta
		velocity = _dash_dir * dash_speed
	elif axis != Vector2.ZERO:
		velocity = velocity.move_toward(axis * move_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	move_and_slide()

	if Input.is_action_pressed(ACTION_ATTACK) and _shot_cd_left <= 0.0:
		_shoot()


func take_hit(damage: int, _from: Node) -> void:
	if _grace_left > 0.0 or _dash_left > 0.0:
		return
	_grace_left = hurt_grace
	health = maxi(health - damage, 0)
	health_changed.emit(health, max_health)
	_flash(Color(1.0, 0.35, 0.35))
	if health <= 0:
		_die()


## "persistent" group contract (see templates ABI): return the state to save.
func save_data() -> Dictionary:
	return {
		"position": {"x": position.x, "y": position.y},
		"health": health,
	}


func load_data(data: Dictionary) -> void:
	health = int(data.get("health", max_health))
	health_changed.emit(health, max_health)
	var pos: Dictionary = data.get("position", {})
	if pos.has("x") and pos.has("y"):
		position = Vector2(pos.x, pos.y)


func _shoot() -> void:
	_shot_cd_left = shot_cooldown
	var from := _muzzle.global_position
	var dir := Vector2.RIGHT.rotated(_aim_pivot.rotation)
	var to := from + dir * shot_range

	var query := PhysicsRayQueryParameters2D.create(from, to, shot_mask, [get_rid()])
	var result := get_world_2d().direct_space_state.intersect_ray(query)

	var hit: Object = null
	if result:
		to = result.position
		hit = result.collider
		if hit and hit.has_method("take_hit"):
			hit.take_hit(shot_damage, self)

	_tracer.points = PackedVector2Array([from, to])
	_tracer.visible = true
	_tracer_left = 0.06
	shot_fired.emit(from, to, hit)


func _update_tracer(delta: float) -> void:
	if not _tracer.visible:
		return
	_tracer_left -= delta
	if _tracer_left <= 0.0:
		_tracer.visible = false


func _flash(color: Color) -> void:
	_body_visual.color = color
	var tween := create_tween()
	tween.tween_property(_body_visual, "color", Color(0.909804, 0.768627, 0.419608), 0.25)


func _die() -> void:
	died.emit()
	# Respawn at the arena spawn point with full health.
	position = _spawn_position
	velocity = Vector2.ZERO
	health = max_health
	_grace_left = hurt_grace
	health_changed.emit(health, max_health)
