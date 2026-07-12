extends Node2D
## res://scripts/xp_gem.gd
## Pooled XP gem: pure data + a blockout visual. Magnet flight and pickup are
## driven by the gem manager's single loop (gem_manager.gd) — no physics body,
## no per-gem _physics_process.

var value := 1
var active := false


func activate(pos: Vector2, gem_value: int) -> void:
	global_position = pos
	value = gem_value
	active = true
	visible = true


func deactivate() -> void:
	active = false
	visible = false
