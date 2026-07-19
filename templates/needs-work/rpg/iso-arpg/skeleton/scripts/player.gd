extends CharacterBody2D
## res://scripts/player.gd
## Isometric ARPG controller: click-to-move via NavigationAgent2D (hold to
## re-path continuously, Diablo style), a melee swing on ability 1 and an AoE
## nova on ability 2 (with cooldown), health with a post-hit grace window and
## respawn at the spawn point.

signal health_changed(current: int, max_health: int)
signal ability_used(slot: int, cooldown_left: float)
signal died

const ACTION_MOVE := &"move_click"
const ACTION_MELEE := &"ability_melee"
const ACTION_SKILL := &"ability_skill"

@export var move_speed := 260.0
@export var max_health := 20
@export var melee_damage := 2
@export var melee_range := 90.0
@export var melee_cooldown := 0.4
@export var nova_damage := 4
@export var nova_range := 190.0
@export var nova_cooldown := 4.0
## Seconds of invulnerability after taking a hit.
@export var hurt_grace := 0.6

var health: int
var melee_cd_left := 0.0
var nova_cd_left := 0.0
var _spawn_position: Vector2
var _grace_left := 0.0

@onready var _agent: NavigationAgent2D = $NavigationAgent2D
@onready var _body_visual: Polygon2D = $Body
@onready var _nova_ring: Polygon2D = $NovaRing


func _ready() -> void:
	health = max_health
	_spawn_position = position
	_nova_ring.visible = false
	# Navigation maps sync on the first physics frame; don't query before that.
	set_physics_process(false)
	_await_navigation.call_deferred()
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	melee_cd_left = maxf(melee_cd_left - delta, 0.0)
	nova_cd_left = maxf(nova_cd_left - delta, 0.0)
	_grace_left = maxf(_grace_left - delta, 0.0)

	if Input.is_action_pressed(ACTION_MOVE):
		command_move_to(get_global_mouse_position())
	if Input.is_action_just_pressed(ACTION_MELEE):
		use_melee()
	if Input.is_action_just_pressed(ACTION_SKILL):
		use_nova()

	if _agent.is_navigation_finished():
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * 10.0 * delta)
	else:
		var next := _agent.get_next_path_position()
		velocity = (next - global_position).normalized() * move_speed
	move_and_slide()


## Path towards a world position (what a mouse click does; also the headless
## boot probe's entry point).
func command_move_to(world_position: Vector2) -> void:
	_agent.target_position = world_position


## True while the agent holds an unfinished path (probe hook).
func is_moving() -> bool:
	return is_physics_processing() and not _agent.is_navigation_finished()


func use_melee() -> bool:
	if melee_cd_left > 0.0:
		return false
	melee_cd_left = melee_cooldown
	_strike_enemies_within(melee_range, melee_damage)
	_flash(Color(1.0, 0.95, 0.6))
	ability_used.emit(1, melee_cd_left)
	return true


func use_nova() -> bool:
	if nova_cd_left > 0.0:
		return false
	nova_cd_left = nova_cooldown
	_strike_enemies_within(nova_range, nova_damage)
	_show_nova_ring()
	ability_used.emit(2, nova_cd_left)
	return true


func take_hit(damage: int, _from: Node) -> void:
	if _grace_left > 0.0:
		return
	_grace_left = hurt_grace
	health = maxi(health - damage, 0)
	health_changed.emit(health, max_health)
	_flash(Color(1.0, 0.35, 0.35))
	if health <= 0:
		_die()


## "persistent" group contract (see templates ABI).
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


func _strike_enemies_within(radius: float, damage: int) -> void:
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		var enemy_2d := enemy as Node2D
		if enemy_2d and global_position.distance_to(enemy_2d.global_position) <= radius \
				and enemy.has_method("take_hit"):
			enemy.take_hit(damage, self)


func _show_nova_ring() -> void:
	_nova_ring.visible = true
	_nova_ring.scale = Vector2(0.3, 0.3)
	_nova_ring.modulate = Color(1, 1, 1, 0.9)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_nova_ring, "scale", Vector2.ONE, 0.25)
	tween.tween_property(_nova_ring, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(func() -> void: _nova_ring.visible = false)


func _flash(color: Color) -> void:
	_body_visual.color = color
	var tween := create_tween()
	tween.tween_property(_body_visual, "color", Color(0.909804, 0.768627, 0.419608), 0.25)


func _die() -> void:
	died.emit()
	position = _spawn_position
	velocity = Vector2.ZERO
	_agent.target_position = global_position
	health = max_health
	_grace_left = hurt_grace
	health_changed.emit(health, max_health)


func _await_navigation() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_agent.target_position = global_position
	set_physics_process(true)
