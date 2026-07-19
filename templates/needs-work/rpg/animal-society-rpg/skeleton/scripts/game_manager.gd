extends Node
## res://scripts/game_manager.gd
## Global game-state singleton (autoload "GameManager"). It OWNS one WarrenEngine —
## the pure, seedable ANIMAL-SOCIETY survival + migration RPG — and adds the NoxDev
## template ABI on top: it lives in the "game_manager" + "persistent" groups and
## implements save_data()/load_data(), so godotsmith's save_system persists the WHOLE
## run (the band + roles + needs + morale + journey + counters + RNG state) — a full
## replayable snapshot — alongside world flags.
##
## All RULES live in WarrenEngine; the view (warren.gd) only reads state and forwards
## a decision, and this file only owns the engine + flags + persistence. new_run()
## seeds a fresh band; auto-play helpers drive the deterministic policies the probes
## exercise.

signal run_reset   ## a fresh run was created (the view rebinds + repaints)
signal changed     ## any state change (a decision resolved) — the view refreshes

const DEFAULT_SEED := 20260716  ## deterministic by default; new_run(0) for random

var band: WarrenEngine
var flags: Dictionary = {}


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")
	band = WarrenEngine.new()


func _ready() -> void:
	if band == null or band.member_count() == 0:
		new_run(DEFAULT_SEED)


## Allocate a fresh run. seed == 0 → random; any other value is deterministic.
## `config` forwards difficulty levers (stops / target / danger / start_food).
func new_run(seed_value: int = DEFAULT_SEED, config: Dictionary = {}) -> void:
	band = WarrenEngine.new()
	band.setup(seed_value, config)
	run_reset.emit()
	changed.emit()


func reset() -> void:
	new_run(DEFAULT_SEED)


## Forward a player decision to the engine, then signal the view. Returns whether the
## decision was legal (rejected illegal ones leave the state unchanged).
func decide(action: int, arg0: int = -1, arg1: int = -1) -> bool:
	if band == null:
		return false
	var ok: bool = band.take_action(action, arg0, arg1)
	changed.emit()
	return ok


## Advance one auto-play step under a policy (used by the "watch it play" mode + probes).
func auto_step(policy: String = "balanced") -> void:
	if band == null:
		return
	band.auto_step(policy)
	changed.emit()


# --- flags -----------------------------------------------------------------

func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value


func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func clear_flag(flag: String) -> void:
	flags.erase(flag)


# --- persistence (whole run + RNG state round-trips) -----------------------

func save_data() -> Dictionary:
	return {
		"flags": flags.duplicate(true),
		"band": band.to_dict(),
	}


func load_data(data: Dictionary) -> void:
	flags = (data.get("flags", {}) as Dictionary).duplicate(true)
	if band == null:
		band = WarrenEngine.new()
	var snap: Dictionary = data.get("band", {})
	if not snap.is_empty():
		band.from_dict(snap)
	run_reset.emit()
	changed.emit()
