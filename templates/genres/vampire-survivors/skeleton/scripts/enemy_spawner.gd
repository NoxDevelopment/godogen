extends Node2D
## res://scripts/enemy_spawner.gd
## Swarm director (group "enemy_spawner"): timed spawn waves that scale in
## count/speed/health, spawned in a ring just off-screen around the player.
## Every active enemy is moved by this ONE loop (straight chase toward the
## player) and dead enemies return to a pool instead of being freed — no
## physics bodies, no navigation, no per-enemy _physics_process — so 200+
## simultaneous enemies stay cheap. Contact damage runs on a per-enemy
## cooldown from the same loop. nearest_enemy() is the weapon-targeting and
## bullet-hit query used by the player.

signal wave_started(wave: int, count: int)
signal enemy_killed(enemy: Node2D, pos: Vector2)

@export var enemy_scene: PackedScene = preload("res://scenes/enemy.tscn")
## Seconds between waves (the first wave fires on the first physics frame).
@export var wave_interval := 5.0
@export var base_count := 6
## Extra enemies per wave index.
@export var count_per_wave := 2
@export var base_speed := 70.0
## Extra px/s of chase speed per wave index.
@export var speed_per_wave := 3.0
@export var max_speed := 220.0
@export var base_health := 2
## Every this many waves, enemies gain +1 health.
@export var waves_per_health := 3
@export var contact_damage := 1
## Distance at which an enemy lands its contact hit, in pixels.
@export var contact_range := 26.0
@export var contact_cooldown := 0.8
## Ring radius around the player where waves appear (just off-screen).
@export var spawn_radius := 640.0
## Hard cap on simultaneous enemies; waves clamp to the remaining budget.
@export var max_active := 240

var wave := 0

var _wave_left := 0.0
var _active: Array[Node2D] = []
var _pool: Array[Node2D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return

	_wave_left -= delta
	if _wave_left <= 0.0:
		_wave_left = wave_interval
		spawn_wave()

	var ppos := player.global_position
	for enemy in _active:
		enemy.contact_cd_left = maxf(enemy.contact_cd_left - delta, 0.0)
		var offset := ppos - enemy.global_position
		var dist := offset.length()
		if dist > 1.0:
			enemy.global_position += offset / dist * (enemy.speed * delta)
		if dist <= contact_range and enemy.contact_cd_left <= 0.0 \
				and player.has_method("take_hit"):
			enemy.contact_cd_left = contact_cooldown
			player.take_hit(enemy.damage, enemy)


## Spawn the next scaled wave in a ring around the player. Public so the boot
## probe (and directors/bosses) can force waves. Returns the spawn count.
func spawn_wave() -> int:
	var player := get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		return 0
	var count := mini(base_count + wave * count_per_wave, max_active - _active.size())
	var speed := _wave_speed()
	var health := _wave_health()
	wave += 1
	for i in count:
		var angle := _rng.randf_range(0.0, TAU)
		var radius := spawn_radius + _rng.randf_range(-40.0, 40.0)
		spawn_enemy_at(
			player.global_position + Vector2.RIGHT.rotated(angle) * radius,
			health, speed
		)
	wave_started.emit(wave, count)
	return count


## Spawn one enemy at an exact position (probe/scripted-encounter hook).
## health/speed default to the current wave's scaling when omitted.
func spawn_enemy_at(pos: Vector2, health := -1, speed := -1.0) -> Node2D:
	var enemy: Node2D
	if _pool.is_empty():
		enemy = enemy_scene.instantiate()
		add_child(enemy)
		enemy.killed.connect(_on_enemy_killed)
	else:
		enemy = _pool.pop_back()
	var hp := health if health > 0 else _wave_health()
	var spd := speed if speed > 0.0 else _wave_speed()
	enemy.activate(pos, hp, spd, contact_damage)
	_active.append(enemy)
	return enemy


## Nearest active enemy within max_dist of `from` (weapon targeting and
## projectile hit-tests both run through this linear scan).
func nearest_enemy(from: Vector2, max_dist := INF) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist * max_dist
	for enemy in _active:
		var d := from.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best


func active_count() -> int:
	return _active.size()


## Deterministic waves/spawn rings for tests.
func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func _wave_speed() -> float:
	return minf(base_speed + wave * speed_per_wave, max_speed)


func _wave_health() -> int:
	return base_health + int(float(wave) / float(maxi(waves_per_health, 1)))


func _on_enemy_killed(enemy: Node2D) -> void:
	var pos := enemy.global_position
	_active.erase(enemy)
	enemy.deactivate()
	_pool.append(enemy)
	enemy_killed.emit(enemy, pos)
