extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). It OWNS one PokerEngine —
## the pure, seedable Balatro-style poker-scoring roguelike rules — and adds the
## NoxDev template ABI on top: it lives in the "game_manager" + "persistent"
## groups and implements save_data()/load_data(), so godotsmith's save_system
## persists the WHOLE run (deck, hand, jokers, hand levels, ante, money, shop).
##
## All rules stay in PokerEngine; table.gd only reads state + forwards a human's
## chosen action through here, and this file emits `changed` so the view redraws.
## The engine is solo + deterministic, so a run replays byte-identically from a
## seed and the auto-play can demo a whole run with no UI.

signal changed  ## any state change — the table redraws on this.

var engine: PokerEngine


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")
	engine = PokerEngine.new()


# =====================================================================
#  Run lifecycle
# =====================================================================

## Start a fresh run. seed == 0 -> random; any other value is deterministic.
## `config` optionally overrides difficulty (see PokerEngine.setup).
func new_run(seed_value: int = 0, config: Dictionary = {}) -> void:
	engine.setup(seed_value, config)
	changed.emit()


func is_run_over() -> bool:
	return engine.run_over


func is_won() -> bool:
	return engine.run_won


# =====================================================================
#  Human input — the table forwards ONE chosen action through here
# =====================================================================

func play_selected(indices: Array) -> Dictionary:
	var bd := engine.play(indices)
	changed.emit()
	return bd


func discard_selected(indices: Array) -> bool:
	var ok := engine.discard(indices)
	changed.emit()
	return ok


func buy(index: int) -> bool:
	var ok := engine.buy(index)
	changed.emit()
	return ok


func sell_joker(slot: int) -> bool:
	var ok := engine.sell_joker(slot)
	changed.emit()
	return ok


func leave_shop() -> bool:
	var ok := engine.leave_shop()
	changed.emit()
	return ok


## Advance the auto-play demo one deterministic step (a play, discard, or shop
## purchase). The "Auto" button in the table calls this.
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
