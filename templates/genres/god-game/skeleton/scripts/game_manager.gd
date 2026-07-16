extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). Owns the one live
## GodWorld — the pure deity-sim engine (scripts/god_world.gd) — and exposes it
## to the map scene, plus world flags. Lives in the "game_manager" + "persistent"
## groups and implements the save_data()/load_data() ABI contract so godotsmith's
## save_system persists the ENTIRE world (terrain + both tribes + belief + RNG) —
## a full replayable snapshot — alongside flags.

signal world_reset  ## a fresh world was created (the view rebinds + repaints)

const GRID_W := 64             ## the deity map is GRID_W × GRID_H cells…
const GRID_H := 64
const DEFAULT_SEED := 20260715 ## deterministic by default; new_world(0) for random

var world: GodWorld
var flags: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")


func _ready() -> void:
	if world == null:
		new_world(DEFAULT_SEED)


## Allocate a fresh world. seed == 0 → random; any other value is deterministic.
func new_world(seed_value: int = DEFAULT_SEED) -> void:
	world = GodWorld.new()
	world.setup(GRID_W, GRID_H, seed_value)
	world_reset.emit()


# --- flags -----------------------------------------------------------------

func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value


func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func clear_flag(flag: String) -> void:
	flags.erase(flag)


# --- persistence (whole world + RNG state round-trips) ---------------------

func save_data() -> Dictionary:
	return {
		"flags": flags.duplicate(true),
		"world": world.snapshot(),
	}


func load_data(data: Dictionary) -> void:
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	if world == null:
		world = GodWorld.new()
	var snap: Dictionary = data.get("world", {})
	if not snap.is_empty():
		world.restore(snap)
	world_reset.emit()
