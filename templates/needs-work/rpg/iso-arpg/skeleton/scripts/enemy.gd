extends CharacterBody2D
## res://scripts/enemy.gd
## Chaser enemy (same archetype as the top-down-action template): follows the
## player across the NavigationRegion2D via a NavigationAgent2D, repathing on a
## short timer, deals contact damage on a cooldown, and rolls a loot drop
## through the LootSystem autoload when it dies.

signal destroyed(enemy: Node)

@export var move_speed := 150.0
@export var max_health := 6
@export var contact_damage := 1
@export var contact_range := 42.0
@export var contact_cooldown := 0.9
## How often the chase target is re-queried, in seconds.
@export var repath_interval := 0.25

var health: int
var _repath_left := 0.0
var _contact_cd_left := 0.0
var _base_color: Color

@onready var _agent: NavigationAgent2D = $NavigationAgent2D
@onready var _visual: Polygon2D = $Visual


func _ready() -> void:
	health = max_health
	_base_color = _visual.color
	# Navigation maps sync on the first physics frame; querying earlier
	# returns empty paths (and logs errors on some engine versions).
	set_physics_process(false)
	_await_navigation.call_deferred()


func _physics_process(delta: float) -> void:
	_contact_cd_left = maxf(_contact_cd_left - delta, 0.0)

	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_repath_left -= delta
	if _repath_left <= 0.0:
		_repath_left = repath_interval
		_agent.target_position = player.global_position

	if _agent.is_navigation_finished():
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * 8.0 * delta)
	else:
		var next := _agent.get_next_path_position()
		velocity = (next - global_position).normalized() * move_speed

	move_and_slide()

	if _contact_cd_left <= 0.0 \
			and global_position.distance_to(player.global_position) <= contact_range \
			and player.has_method("take_hit"):
		_contact_cd_left = contact_cooldown
		player.take_hit(contact_damage, self)


## True once the agent has a live path towards the player (probe hook).
func is_chasing() -> bool:
	return is_physics_processing() and not _agent.is_navigation_finished()


func take_hit(damage: int, _from: Node) -> void:
	health = maxi(health - damage, 0)
	_visual.color = Color(1.0, 1.0, 1.0)
	var tween := create_tween()
	tween.tween_property(_visual, "color", _base_color, 0.15)
	if health <= 0:
		LootSystem.drop_loot(global_position)
		destroyed.emit(self)
		queue_free()


func _await_navigation() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	set_physics_process(true)
