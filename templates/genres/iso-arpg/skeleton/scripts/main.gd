extends Node2D
## res://scripts/main.gd
## Arena shell: wires player health, enemy deaths, and loot pickups into the
## HUD, keeps the ability-bar cooldown readout fresh, and emits the boot probe
## proving the core loop (click-to-move + chasing enemies + rarity-rolled
## loot) is alive.

@onready var _player: CharacterBody2D = $World/Player
@onready var _health_label: Label = $HUD/Margin/Rows/HealthLabel
@onready var _abilities_label: Label = $HUD/Margin/Rows/AbilitiesLabel
@onready var _enemies_label: Label = $HUD/Margin/Rows/EnemiesLabel
@onready var _loot_label: Label = $HUD/Margin/Rows/LootLabel


func _ready() -> void:
	_player.health_changed.connect(_on_player_health_changed)
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		enemy.destroyed.connect(_on_enemy_destroyed)
	LootSystem.loot_collected.connect(_on_loot_collected)
	_refresh_enemies_label()

	_emit_boot_probe.call_deferred()


func _process(_delta: float) -> void:
	var melee := "READY" if _player.melee_cd_left <= 0.0 else "%.1fs" % _player.melee_cd_left
	var nova := "READY" if _player.nova_cd_left <= 0.0 else "%.1fs" % _player.nova_cd_left
	_abilities_label.text = "[1] Melee: %s   [2] Nova: %s" % [melee, nova]


func _on_player_health_changed(current: int, max_health: int) -> void:
	_health_label.text = "HP %d/%d" % [current, max_health]


func _on_enemy_destroyed(_enemy: Node) -> void:
	# The enemy is freed after emitting; recount on the next idle frame.
	_refresh_enemies_label.call_deferred()


func _on_loot_collected(drop: Dictionary) -> void:
	_loot_label.text = "Picked up: [%s] %s +%d %s (bag: %d)" % [
		drop.get("rarity", "?"), drop.get("name", "?"),
		drop.get("value", 0), drop.get("stat", ""), LootSystem.inventory.size(),
	]


func _refresh_enemies_label() -> void:
	_enemies_label.text = "Enemies left: %d" % get_tree().get_nodes_in_group(&"enemies").size()


func _emit_boot_probe() -> void:
	# Give agents time to sync with the navigation map (they enable physics
	# two physics frames after ready), then issue a programmatic move order —
	# exactly what a mouse click does — and verify the loop.
	for i in 8:
		await get_tree().physics_frame
	_player.command_move_to(_player.global_position + Vector2(220.0, 110.0))
	for i in 6:
		await get_tree().physics_frame
	var enemies := get_tree().get_nodes_in_group(&"enemies")
	var chasing := false
	for enemy in enemies:
		if enemy.is_chasing():
			chasing = true
			break
	var drop := LootSystem.roll_drop()
	print("DEBUG: iso-arpg core loop ready — click_move=%s enemies=%d enemy_chasing=%s loot_roll=[%s] %s +%d %s" % [
		_player.is_moving(), enemies.size(), chasing,
		drop.get("rarity", "?"), drop.get("name", "?"),
		drop.get("value", 0), drop.get("stat", ""),
	])
