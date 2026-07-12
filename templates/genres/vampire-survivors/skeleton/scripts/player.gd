extends CharacterBody2D
## res://scripts/player.gd
## Auto-attacking survivor: WASD movement, a weapon that fires on a timer at
## the nearest active enemy in range (pooled first-party projectiles — no
## physics bodies), XP/level track, magnet radius consumed by the gem manager,
## health with post-hit grace. Every stat here is a level-up target — the
## 3-choice UI applies data-driven Upgrade resources via apply_upgrade().

signal health_changed(current: int, max_health: int)
signal xp_changed(xp: int, xp_to_next: int)
signal leveled_up(level: int)
signal weapon_fired(from: Vector2, target: Node2D)
signal died

const ACTION_UP := &"move_up"
const ACTION_DOWN := &"move_down"
const ACTION_LEFT := &"move_left"
const ACTION_RIGHT := &"move_right"

@export var move_speed := 260.0
@export var acceleration := 2400.0
@export var friction := 2000.0
@export var max_health := 5
## Damage of one projectile.
@export var damage := 1
## Seconds between auto-shots (level-ups shrink it multiplicatively).
@export var fire_interval := 0.8
## Auto-targeting range of the weapon, in pixels.
@export var weapon_range := 420.0
@export var bullet_speed := 900.0
## A projectile hits when an enemy is within this many pixels of it.
@export var bullet_hit_radius := 14.0
## XP gems fly to the player once inside this radius (see gem_manager.gd).
@export var magnet_radius := 120.0
## Seconds of invulnerability after taking a hit.
@export var hurt_grace := 0.6

var health: int
var level := 1
var xp := 0
var _dead := false
var _fire_cd := 0.0
var _grace_left := 0.0
var _bullets_active: Array[Dictionary] = []
var _bullet_pool: Array[Polygon2D] = []

@onready var _body_visual: Polygon2D = $Body


func _ready() -> void:
	health = max_health
	health_changed.emit(health, max_health)
	xp_changed.emit(xp, xp_to_next_level())


func _physics_process(delta: float) -> void:
	_grace_left = maxf(_grace_left - delta, 0.0)

	var axis := Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN)
	if axis != Vector2.ZERO:
		velocity = velocity.move_toward(axis * move_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()

	# The auto-weapon: retry quickly while no target is in range, full
	# cooldown after an actual shot.
	_fire_cd -= delta
	if _fire_cd <= 0.0 and not _dead:
		_fire_cd = fire_interval if fire_at_nearest() else 0.1

	_update_bullets(delta)


## Fire one projectile at the nearest active enemy in weapon_range. This is
## the routine the fire timer drives; it is public so bots and the boot probe
## can exercise targeting -> projectile -> take_hit directly (the cooldown
## lives in _physics_process). Returns true if a shot was fired.
func fire_at_nearest() -> bool:
	var spawner := get_tree().get_first_node_in_group(&"enemy_spawner")
	if spawner == null:
		return false
	var target: Node2D = spawner.nearest_enemy(global_position, weapon_range)
	if target == null:
		return false
	var dir := (target.global_position - global_position).normalized()
	var node := _acquire_bullet()
	node.global_position = global_position
	node.rotation = dir.angle()
	_bullets_active.append({"node": node, "dir": dir, "life": 1.2})
	weapon_fired.emit(global_position, target)
	return true


func gain_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next_level():
		xp -= xp_to_next_level()
		level += 1
		leveled_up.emit(level)
	xp_changed.emit(xp, xp_to_next_level())


func xp_to_next_level() -> int:
	return 3 + level * 2


## Level-up entry point — `stat` comes from an Upgrade resource (upgrade.gd).
func apply_upgrade(stat: String, amount: float) -> void:
	match stat:
		"damage":
			damage += int(amount)
		"fire_rate":
			fire_interval = maxf(fire_interval * (1.0 - amount), 0.12)
		"move_speed":
			move_speed += amount
		"magnet_radius":
			magnet_radius += amount
		"max_health":
			max_health += int(amount)
			health = mini(health + int(amount), max_health)
			health_changed.emit(health, max_health)


func get_stat(stat: String) -> float:
	match stat:
		"damage":
			return float(damage)
		"fire_rate":
			return fire_interval
		"move_speed":
			return move_speed
		"magnet_radius":
			return magnet_radius
		"max_health":
			return float(max_health)
	return 0.0


func take_hit(hit_damage: int, _from: Node) -> void:
	if _dead or _grace_left > 0.0:
		return
	_grace_left = hurt_grace
	health = maxi(health - hit_damage, 0)
	health_changed.emit(health, max_health)
	_flash(Color(1.0, 0.35, 0.35))
	if health <= 0:
		_die()


## "persistent" group contract (see templates ABI): return the state to save.
func save_data() -> Dictionary:
	return {
		"position": {"x": position.x, "y": position.y},
		"health": health,
		"level": level,
		"xp": xp,
		"stats": {
			"damage": damage,
			"fire_interval": fire_interval,
			"move_speed": move_speed,
			"magnet_radius": magnet_radius,
			"max_health": max_health,
		},
	}


func load_data(data: Dictionary) -> void:
	var stats: Dictionary = data.get("stats", {})
	damage = int(stats.get("damage", damage))
	fire_interval = float(stats.get("fire_interval", fire_interval))
	move_speed = float(stats.get("move_speed", move_speed))
	magnet_radius = float(stats.get("magnet_radius", magnet_radius))
	max_health = int(stats.get("max_health", max_health))
	level = int(data.get("level", level))
	xp = int(data.get("xp", xp))
	health = int(data.get("health", max_health))
	health_changed.emit(health, max_health)
	xp_changed.emit(xp, xp_to_next_level())
	var pos: Dictionary = data.get("position", {})
	if pos.has("x") and pos.has("y"):
		position = Vector2(pos.x, pos.y)


func _update_bullets(delta: float) -> void:
	if _bullets_active.is_empty():
		return
	var spawner := get_tree().get_first_node_in_group(&"enemy_spawner")
	var i := _bullets_active.size() - 1
	while i >= 0:
		var bullet: Dictionary = _bullets_active[i]
		var node: Polygon2D = bullet.node
		node.global_position += bullet.dir * bullet_speed * delta
		bullet.life -= delta
		var done: bool = bullet.life <= 0.0
		if not done and spawner != null:
			var hit: Node2D = spawner.nearest_enemy(node.global_position, bullet_hit_radius)
			if hit != null:
				hit.take_hit(damage, self)
				done = true
		if done:
			node.visible = false
			_bullet_pool.append(node)
			_bullets_active.remove_at(i)
		i -= 1


func _acquire_bullet() -> Polygon2D:
	if not _bullet_pool.is_empty():
		var recycled: Polygon2D = _bullet_pool.pop_back()
		recycled.visible = true
		return recycled
	var node := Polygon2D.new()
	node.polygon = PackedVector2Array([-4, -2, 4, -2, 4, 2, -4, 2])
	node.color = Color(1.0, 0.94902, 0.72549)
	node.top_level = true
	node.z_index = 8
	add_child(node)
	return node


func _flash(color: Color) -> void:
	_body_visual.color = color
	var tween := create_tween()
	tween.tween_property(_body_visual, "color", Color(0.909804, 0.768627, 0.419608), 0.25)


func _die() -> void:
	_dead = true
	velocity = Vector2.ZERO
	died.emit()
