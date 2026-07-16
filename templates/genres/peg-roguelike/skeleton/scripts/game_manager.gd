extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). It OWNS one PegEngine —
## the pure, seedable, deterministic Peglin-style peg-roguelike rules — and adds
## the NoxDev template ABI on top: it lives in the "game_manager" + "persistent"
## groups and implements save_data()/load_data(), so godotsmith's save_system
## persists the WHOLE run (deck, relics, HP, gold, map, current fight incl. the
## peg board + draw/discard piles + RNG).
##
## All rules stay in PegEngine; board.gd only reads state + forwards a human's
## chosen action through here, and this file emits `changed` so the view redraws.
## The run is deterministic, so it replays byte-identically from a seed and the
## auto-play can demo a whole run with no UI.

signal changed  ## any state change — the board redraws on this.

const DEFAULT_SEED: int = 20260715

var engine: PegEngine


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")
	engine = PegEngine.new()


# =====================================================================
#  Run lifecycle
# =====================================================================

## Start a fresh run. seed == 0 -> random; any other value is deterministic.
## `config` optionally overrides difficulty (see PegEngine.setup).
func new_run(seed_value: int = 0, config: Dictionary = {}) -> void:
	engine.setup(seed_value, config)
	changed.emit()


func is_run_over() -> bool:
	return engine.run_over


func is_won() -> bool:
	return engine.run_won


# =====================================================================
#  Human input — the board forwards ONE chosen action through here
# =====================================================================

func choose_node(node_id: String) -> bool:
	var ok := engine.choose_node(node_id)
	changed.emit()
	return ok


func fire(aim_angle: float) -> Dictionary:
	var shot := engine.fire(aim_angle)
	changed.emit()
	return shot


func choose_reward(index: int) -> bool:
	var ok := engine.choose_reward(index)
	changed.emit()
	return ok


func buy(index: int) -> bool:
	var ok := engine.buy(index)
	changed.emit()
	return ok


func leave_shop() -> bool:
	var ok := engine.leave_shop()
	changed.emit()
	return ok


func choose_event(option: int) -> bool:
	var ok := engine.choose_event(option)
	changed.emit()
	return ok


func rest_choose(choice: String) -> bool:
	var ok := engine.rest_choose(choice)
	changed.emit()
	return ok


## Advance the auto-play demo one deterministic step (map pick, a shot, a
## purchase, etc.). The "Auto Step" button in the board calls this.
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
