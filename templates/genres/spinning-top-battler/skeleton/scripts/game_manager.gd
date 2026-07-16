extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). It OWNS one TopEngine —
## the pure, seedable, deterministic spinning-top arena battler + tournament rules —
## and adds the NoxDev template ABI on top: it lives in the "game_manager" +
## "persistent" groups and implements save_data()/load_data(), so godotsmith's
## save_system persists the WHOLE run (owned parts, current build, rung, match
## score, difficulty + RNG).
##
## All rules stay in TopEngine; arena.gd only reads state + forwards a human's
## chosen action through here, and this file emits `changed` so the view redraws.
## The tournament is deterministic, so it replays byte-identically from a seed and
## the auto-play can demo a whole ladder with no UI.

signal changed  ## any state change — the arena redraws on this.

const DEFAULT_SEED: int = 20260715

var engine: TopEngine


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")
	engine = TopEngine.new()


# =====================================================================
#  Run lifecycle
# =====================================================================

## Start a fresh tournament. seed == 0 -> random; any other value is deterministic.
## `config` optionally overrides difficulty (see TopEngine.setup).
func new_run(seed_value: int = 0, config: Dictionary = {}) -> void:
	engine.setup(seed_value, config)
	changed.emit()


func is_run_over() -> bool:
	return engine.tournament_over


func is_won() -> bool:
	return engine.tournament_won


# =====================================================================
#  Human input — the arena forwards ONE chosen action through here
# =====================================================================

func select_build(ring: String, disk: String, tip: String, spin: int) -> bool:
	var ok := engine.select_build(ring, disk, tip, spin)
	changed.emit()
	return ok


func launch(power: float, aim: float) -> Dictionary:
	var res := engine.launch(power, aim)
	changed.emit()
	return res


## Advance the auto-play demo one deterministic step (pick a counter build, launch
## a round). The "Auto Step" button in the arena calls this.
func auto_step() -> void:
	engine.auto_take_turn()
	changed.emit()


# =====================================================================
#  Persistence — the WHOLE run round-trips through save_system
# =====================================================================

func save_data() -> Dictionary:
	return {"engine": engine.to_dict()}


func load_data(data: Dictionary) -> void:
	if data.has("engine"):
		engine.from_dict(data["engine"] as Dictionary)
	changed.emit()
