extends Node2D
## res://scripts/main.gd
## Arena shell: points BulletUpHell's shared bullet area at the player's
## physics layer, wires the HUD, and emits the boot probe proving the core
## loop (spawner firing, live bullets in the pool, player ship) is running.

@onready var _player: CharacterBody2D = $Player
@onready var _spawn_point: Node2D = $Spawner/SpawnPoint
@onready var _lives_label: Label = $HUD/Margin/Rows/LivesLabel
@onready var _bullets_label: Label = $HUD/Margin/Rows/BulletsLabel


func _ready() -> void:
	# The shared area's collision_mask decides what bullets can hit. Layer 2
	# is the player ship (walls stay out of it — bullets die via their
	# death_outside_box instead of on the arena boundary).
	Spawning.get_shared_area("0").collision_mask = 0b010

	_player.lives_changed.connect(_on_player_lives_changed)
	_emit_boot_probe.call_deferred()


func _process(_delta: float) -> void:
	_bullets_label.text = "Bullets: %d" % Spawning.poolBullets.size()


func _on_player_lives_changed(current: int, max_lives: int) -> void:
	_lives_label.text = "Lives %d/%d" % [current, max_lives]


func _emit_boot_probe() -> void:
	# Let the spawn point fire its first volley (it spawns on the first
	# physics frame; bullets shoot immediately with cooldown_shoot = 0).
	for i in 45:
		await get_tree().physics_frame
	print("DEBUG: bullet-hell core loop ready — spawner=%s player=%s active_bullets=%d" % [
		is_instance_valid(_spawn_point) and _spawn_point.auto_pattern_id != "",
		is_instance_valid(_player) and _player.is_in_group(&"player"),
		Spawning.poolBullets.size(),
	])
