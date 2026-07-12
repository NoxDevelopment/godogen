extends Node3D
## res://scripts/main.gd
## Arena shell: health/armor/ammo/score HUD, wave + kill bookkeeping into
## GameManager flags, death -> run summary, and the boot probe proving the
## loop headless: a director-spawned rusher killed through the real shotgun
## fire() path, a weapon switch + rocket whose splash (not the direct hit)
## damaged a shooter, an armor pickup that then absorbed its share of a real
## melee hit, and a health pickup whose respawn countdown fired.

var _run_over := false

@onready var _player: CharacterBody3D = $Player
@onready var _waves: Node3D = $Waves
@onready var _summary: CanvasLayer = $RunSummary
@onready var _health_label: Label = $HUD/Margin/Rows/HealthLabel
@onready var _armor_label: Label = $HUD/Margin/Rows/ArmorLabel
@onready var _ammo_label: Label = $HUD/Margin/Rows/AmmoLabel
@onready var _score_label: Label = $HUD/Margin/Rows/ScoreLabel
@onready var _hint_label: Label = $HUD/Margin/Rows/HintLabel


func _ready() -> void:
	_player.health_changed.connect(_on_health_changed)
	_player.died.connect(_on_player_died)
	_player.weapons.ammo_changed.connect(_on_ammo_changed)
	_player.weapons.weapon_switched.connect(_on_weapon_switched)
	_waves.wave_started.connect(_on_wave_started)
	_waves.enemy_killed.connect(_on_enemy_killed)
	_hint_label.text = "WASD: move   Space: jump   Shift: sprint   LMB: fire   Q/1/2: weapons"
	_on_health_changed(_player.health, _player.armor)
	_update_ammo()
	_update_score()

	_emit_boot_probe.call_deferred()


## Deterministic shotgun spread for tests (forwards to the weapon rack RNG).
func set_seed(seed_value: int) -> void:
	_player.weapons.set_seed(seed_value)


func _on_health_changed(health: int, armor: int) -> void:
	_health_label.text = "Health: %d" % health
	_armor_label.text = "Armor: %d" % armor


func _on_ammo_changed(_ammo_type: String, _amount: int) -> void:
	_update_ammo()


func _on_weapon_switched(_weapon_id: String) -> void:
	_update_ammo()


func _on_wave_started(_number: int, _enemies: int) -> void:
	_update_score()


func _on_enemy_killed(_enemy: CharacterBody3D, _kills: int) -> void:
	_update_score()


func _update_ammo() -> void:
	_ammo_label.text = "%s: %d %s" % [
		_player.weapons.current_weapon_id().capitalize(),
		_player.weapons.current_ammo(),
		_player.weapons.current_ammo_type(),
	]


func _update_score() -> void:
	_score_label.text = "Kills: %d   Wave: %d" % [_waves.kills, _waves.wave]


func _on_player_died() -> void:
	if _run_over:
		return
	_run_over = true
	var best_kills := maxi(int(GameManager.get_flag("best_kills", 0)), _waves.kills)
	GameManager.set_flag("last_run", {"kills": _waves.kills, "wave": _waves.wave})
	GameManager.set_flag("best_kills", best_kills)
	if _waves.wave > int(GameManager.get_flag("best_wave", 0)):
		GameManager.set_flag("best_wave", _waves.wave)
	get_tree().paused = true
	_summary.show_result(_waves.kills, _waves.wave, best_kills)


func _emit_boot_probe() -> void:
	for i in 4:
		await get_tree().physics_frame
	set_seed(1337)

	# 1. Shotgun hitscan kill: spawn a rusher through the director's own
	# routine 6m ahead, aim at its chest and fire the real fire() path — at
	# this range every pellet lands, one blast kills.
	var rusher: CharacterBody3D = _waves.spawn_enemy("rusher", Vector3(0.0, 0.05, 6.0))
	await get_tree().physics_frame
	_player.face_point(rusher.global_position + Vector3(0.0, 1.0, 0.0))
	_player.weapons.fire()
	var shotgun_kill := false
	for i in 20:
		if not is_instance_valid(rusher):
			shotgun_kill = true
			break
		await get_tree().physics_frame

	# 2. Rocket splash: switch weapons, freeze a spawned shooter, and aim the
	# rocket at the floor 1.6m beside it — only the splash can reach it.
	_player.weapons.switch_to(1)
	var switched: String = _player.weapons.current_weapon_id()
	var shooter: CharacterBody3D = _waves.spawn_enemy("shooter", Vector3(0.0, 0.05, 2.0))
	shooter.active = false
	await get_tree().physics_frame
	_player.face_point(shooter.global_position + Vector3(1.6, 0.0, 0.0))
	_player.weapons.fire()
	var splash := 0
	for i in 40:
		if shooter.health < shooter.max_health:
			splash = shooter.max_health - shooter.health
			break
		await get_tree().physics_frame

	# 3. Armor pickup, then a real melee hit: park on the armor spawner (its
	# walk-over distance check collects), spawn a rusher in claw range and
	# let its own attack loop land — armor must absorb its share.
	var armor_item: Node3D = $Items/ArmorSpawner
	_player.global_position = armor_item.global_position + Vector3(0.0, 0.05, 0.0)
	for i in 10:
		if _player.armor > 0:
			break
		await get_tree().physics_frame
	var armor_before: int = _player.armor
	var hp_before: int = _player.health
	var melee_rusher: CharacterBody3D = _waves.spawn_enemy(
			"rusher", _player.global_position + Vector3(1.2, 0.0, 0.0))
	for i in 20:
		if _player.health < hp_before:
			break
		await get_tree().physics_frame
	melee_rusher.active = false
	var hp_after: int = _player.health
	var armor_after: int = _player.armor

	# 4. Health pickup + respawn: compress the countdown (rate-independent)
	# and watch the spawner consume, then pop back.
	var health_item: Node3D = $Items/HealthSpawner
	health_item.respawn_time = 0.15
	_player.global_position = health_item.global_position + Vector3(0.0, 0.05, 0.0)
	var health_picked := false
	var respawn_fired := false
	for i in 40:
		if not health_picked:
			health_picked = not health_item.available
		elif health_item.available:
			respawn_fired = true
			break
		await get_tree().physics_frame

	# Hand the probe survivors to the arena — they join wave 1 as live enemies.
	if is_instance_valid(shooter):
		shooter.active = true
	if is_instance_valid(melee_rusher):
		melee_rusher.active = true

	print("DEBUG: fps-classic core loop ready — shotgun_kill=%s rocket_splash=%d weapon_switch=%s armor_pickup=%d melee_hit=hp%d->%d/armor%d->%d health_pickup=%s respawn_fired=%s kills=%d" % [
		shotgun_kill, splash, switched, armor_before, hp_before, hp_after,
		armor_before, armor_after, health_picked, respawn_fired, _waves.kills,
	])
