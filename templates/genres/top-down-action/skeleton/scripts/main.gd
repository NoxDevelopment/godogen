extends Node2D
## res://scripts/main.gd
## Arena shell: wires the player's health signal and the targets' destroyed
## signals into the HUD, and emits the boot probe line that proves the core
## loop (player + shootable targets + chasing enemy) is alive.

@onready var _player: CharacterBody2D = $Player
@onready var _enemy: CharacterBody2D = $Enemy
@onready var _health_label: Label = $HUD/Margin/Rows/HealthLabel
@onready var _targets_label: Label = $HUD/Margin/Rows/TargetsLabel


func _ready() -> void:
	_player.health_changed.connect(_on_player_health_changed)
	_enemy.destroyed.connect(func(_enemy_node: Node) -> void: _refresh_targets_label())
	for target in get_tree().get_nodes_in_group(&"targets"):
		target.destroyed.connect(_on_target_destroyed)
	_refresh_targets_label()

	_emit_boot_probe.call_deferred()


func _on_player_health_changed(current: int, max_health: int) -> void:
	_health_label.text = "HP %d/%d" % [current, max_health]


func _on_target_destroyed(_target: Node) -> void:
	# The target is freed after emitting; recount on the next idle frame.
	_refresh_targets_label.call_deferred()


func _refresh_targets_label() -> void:
	_targets_label.text = "Targets left: %d" % get_tree().get_nodes_in_group(&"targets").size()


func _emit_boot_probe() -> void:
	# Give the enemy time to sync with the navigation map and take its first
	# path (it enables physics two physics frames after ready).
	for i in 8:
		await get_tree().physics_frame
	if not is_instance_valid(_enemy):
		return
	print("DEBUG: top-down-action core loop ready — player=%s targets=%d enemy_chasing=%s" % [
		is_instance_valid(_player) and _player.is_in_group(&"player"),
		get_tree().get_nodes_in_group(&"targets").size(),
		_enemy.is_chasing(),
	])
