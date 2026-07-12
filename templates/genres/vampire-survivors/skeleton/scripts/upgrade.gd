class_name Upgrade
extends Resource
## res://scripts/upgrade.gd
## One data-driven level-up choice. New upgrades are new .tres files in
## res://resources/upgrades/ — the level-up UI scans that directory at boot,
## zero code. `stat` names a player stat handled by player.apply_upgrade();
## `amount` semantics per stat: damage/max_health add int(amount), move_speed
## and magnet_radius add pixels(/s), fire_rate multiplies the fire interval
## by (1 - amount) — e.g. 0.15 = 15% faster shots.

@export var id := "upgrade"
@export var display_name := "Upgrade"
@export var description := ""
@export_enum("damage", "fire_rate", "move_speed", "magnet_radius", "max_health")
var stat := "damage"
@export var amount := 1.0


func apply_to(player: Node) -> void:
	if player != null and player.has_method("apply_upgrade"):
		player.apply_upgrade(stat, amount)
