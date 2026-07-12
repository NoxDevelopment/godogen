extends Node2D
## res://scripts/main.gd
## Run shell: survival timer + kill counter HUD, level-up flow (level-ups
## queue so multi-level XP bursts offer one 3-choice pick at a time), death ->
## run summary with best-kills/best-time flags on GameManager, and the boot
## probe proving the loop headless: wave spawned, the auto-weapon killed an
## enemy, its XP gem was magnet-collected, and a level-up upgrade applied.

var elapsed := 0.0
var kills := 0

var _run_active := true
var _pending_choices := 0

@onready var _player: CharacterBody2D = $Player
@onready var _spawner: Node2D = $EnemySpawner
@onready var _gems: Node2D = $Gems
@onready var _level_up: CanvasLayer = $LevelUp
@onready var _summary: CanvasLayer = $RunSummary
@onready var _time_label: Label = $HUD/Margin/Rows/TimeLabel
@onready var _kills_label: Label = $HUD/Margin/Rows/KillsLabel
@onready var _health_label: Label = $HUD/Margin/Rows/HealthLabel
@onready var _level_label: Label = $HUD/Margin/Rows/LevelLabel
@onready var _hint_label: Label = $HUD/Margin/Rows/HintLabel


func _ready() -> void:
	_player.health_changed.connect(_on_player_health_changed)
	_player.xp_changed.connect(_on_player_xp_changed)
	_player.leveled_up.connect(_on_player_leveled_up)
	_player.died.connect(_on_player_died)
	_spawner.enemy_killed.connect(_on_enemy_killed)
	_level_up.upgrade_chosen.connect(_on_upgrade_chosen)
	_hint_label.text = "WASD: move — the weapon fires itself"
	_refresh_kills_label()

	_emit_boot_probe.call_deferred()


func _process(delta: float) -> void:
	if not _run_active:
		return
	elapsed += delta
	_time_label.text = "Time %02d:%02d" % [floori(elapsed / 60.0), int(elapsed) % 60]


func _on_player_health_changed(current: int, max_health: int) -> void:
	_health_label.text = "HP %d/%d" % [current, max_health]


func _on_player_xp_changed(xp: int, xp_to_next: int) -> void:
	_level_label.text = "Level %d   XP %d/%d" % [_player.level, xp, xp_to_next]


func _on_player_leveled_up(_level: int) -> void:
	_pending_choices += 1
	_maybe_offer_upgrades()


func _on_upgrade_chosen(_upgrade: Upgrade) -> void:
	_on_player_xp_changed(_player.xp, _player.xp_to_next_level())
	_maybe_offer_upgrades()


func _on_enemy_killed(_enemy: Node2D, pos: Vector2) -> void:
	kills += 1
	_refresh_kills_label()
	_gems.spawn_gem(pos)


func _on_player_died() -> void:
	_run_active = false
	var best_kills := maxi(int(GameManager.get_flag("best_kills", 0)), kills)
	GameManager.set_flag("last_run", {
		"time": elapsed, "kills": kills, "level": _player.level,
	})
	GameManager.set_flag("best_kills", best_kills)
	if elapsed > float(GameManager.get_flag("best_time", 0.0)):
		GameManager.set_flag("best_time", elapsed)
	get_tree().paused = true
	_summary.show_summary(elapsed, kills, _player.level, best_kills)


func _maybe_offer_upgrades() -> void:
	if _pending_choices <= 0 or not _run_active or _level_up.visible:
		return
	_pending_choices -= 1
	_level_up.open(_player)


func _refresh_kills_label() -> void:
	_kills_label.text = "Kills: %d" % kills


func _emit_boot_probe() -> void:
	# Let the spawner's first wave land (it fires on the first physics frame).
	for i in 4:
		await get_tree().physics_frame
	var wave_size: int = _spawner.active_count()

	# Auto-kill: spawn one enemy close by and drive the auto-weapon directly —
	# fire_at_nearest() is the exact routine the fire timer calls, so this
	# proves targeting -> projectile flight -> take_hit -> pool return without
	# waiting out real-time cooldowns.
	var target: Node2D = _spawner.spawn_enemy_at(_player.global_position + Vector2(90.0, 0.0))
	var auto_kill := false
	for i in 90:
		if not target.active:
			auto_kill = true
			break
		if i % 10 == 0:
			_player.fire_at_nearest()
		await get_tree().physics_frame

	# The kill dropped an XP gem inside the magnet radius; wait for the
	# magnet flight + pickup to feed player XP.
	var xp_collected := false
	for i in 60:
		if _player.xp > 0 or _player.level > 1:
			xp_collected = true
			break
		await get_tree().physics_frame

	# Level-up: force the XP threshold, then take the first offered upgrade
	# through the real 3-choice UI (which pauses and unpauses the tree).
	var level_before: int = _player.level
	var stats_before := {}
	for stat in ["damage", "fire_rate", "move_speed", "magnet_radius", "max_health"]:
		stats_before[stat] = _player.get_stat(stat)
	_player.gain_xp(_player.xp_to_next_level())
	await get_tree().process_frame
	var chosen: Upgrade = _level_up.choose(0)
	var applied: bool = chosen != null \
			and _player.level == level_before + 1 \
			and _player.get_stat(chosen.stat) != stats_before[chosen.stat]
	print("DEBUG: vampire-survivors core loop ready — wave_size=%d auto_kill=%s kills=%d xp_collected=%s level_up=[%s] applied=%s" % [
		wave_size, auto_kill, kills, xp_collected,
		chosen.id if chosen != null else "none", applied,
	])
