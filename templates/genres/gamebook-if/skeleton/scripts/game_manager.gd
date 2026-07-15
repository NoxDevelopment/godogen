extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). Carries world flags
## (endings seen, adventures completed) plus the LAST-LAUNCHED adventure kind so
## the title screen can launch the right runner and the play scene knows which
## flow it is in. Lives in the "game_manager"/"persistent" groups and implements
## the "persistent" save_data()/load_data() contract from the NoxDev template
## ABI so godotsmith's save_system drop-in picks it up.
##
## NOTE: This is the WORLD-level meta store. The moment-to-moment adventure
## state (the played passage, sheet, dice) lives in the if-engine's own state
## objects, owned by the PlaySession autoload — never here.

var flags: Dictionary = {}

## Which adventure the title screen last asked PlaySession to launch:
## "oneoff" | "campaign" | "continue" (a loaded save). The play scene reads it
## only for presentation (an ending returns a one-off to the title, but offers
## to advance a campaign to its next module).
var launch_kind: String = "oneoff"


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
	return {"flags": flags.duplicate(true), "launch_kind": launch_kind}


func load_data(data: Dictionary) -> void:
	flags = data.get("flags", {}).duplicate(true)
	launch_kind = str(data.get("launch_kind", "oneoff"))
