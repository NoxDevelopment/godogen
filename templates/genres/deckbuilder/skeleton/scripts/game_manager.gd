extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). Carries world flags
## (battles won, unlocks, meta-progression). Lives in the "game_manager"
## group and implements the "persistent" save_data()/load_data() contract from
## the NoxDev template ABI so godotsmith's save_system drop-in picks it up.

var flags: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")


func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value


func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func clear_flag(flag: String) -> void:
	flags.erase(flag)


func save_data() -> Dictionary:
	return {"flags": flags.duplicate(true)}


func load_data(data: Dictionary) -> void:
	flags = data.get("flags", {}).duplicate(true)
