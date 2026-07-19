extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). It OWNS one PirateEngine —
## the pure, seedable, deterministic age-of-sail pirate CAREER SIM — and adds the
## NoxDev template ABI on top: it lives in the "game_manager" + "persistent" groups
## and implements save_data()/load_data(), so godotsmith's save_system persists the
## WHOLE career (world map, economy, ship, cargo, crew, reputation, skills, quests +
## the RNG state).
##
## All rules stay in PirateEngine; port_map.gd only reads state + forwards a human's
## chosen action through here, and this file emits `changed` so the view redraws.
## The career is deterministic, so it replays byte-identically from a seed and the
## auto-play can demo a whole career (WIN or LOSS) with no UI.

signal changed  ## any state change — the port map redraws on this.

const DEFAULT_SEED: int = 20260715

var engine: PirateEngine


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")
	engine = PirateEngine.new()


# =====================================================================
#  Career lifecycle
# =====================================================================

## Start a fresh career. seed == 0 -> random; any other value is deterministic.
## `config` optionally overrides captain_name / policy / start_gold (see setup).
func new_run(seed_value: int = 0, config: Dictionary = {}) -> void:
	engine.setup(seed_value, config)
	changed.emit()


func is_run_over() -> bool:
	return engine.career_over


func is_won() -> bool:
	return engine.career_won


# =====================================================================
#  Human input — the port map forwards ONE chosen action through here
# =====================================================================

func sail_to(dest: int) -> bool:
	var ok: bool = engine.sail_to(dest)
	changed.emit()
	return ok


func buy(good: String, qty: int) -> bool:
	var ok: bool = engine.buy(good, qty)
	changed.emit()
	return ok


func sell(good: String, qty: int) -> bool:
	var ok: bool = engine.sell(good, qty)
	changed.emit()
	return ok


func attack(stance: String) -> Dictionary:
	var res: Dictionary = engine.attack(stance)
	changed.emit()
	return res


func divide_plunder(amount: int) -> bool:
	var ok: bool = engine.divide_plunder(amount)
	changed.emit()
	return ok


func shore_leave() -> bool:
	var ok: bool = engine.shore_leave()
	changed.emit()
	return ok


func recruit_crew(n: int) -> bool:
	var ok: bool = engine.recruit_crew(n)
	changed.emit()
	return ok


func dig_treasure() -> bool:
	var ok: bool = engine.dig_treasure()
	changed.emit()
	return ok


func retire() -> bool:
	var ok: bool = engine.retire()
	changed.emit()
	return ok


## Advance the auto-play demo one deterministic step (the "Auto Step" button).
func auto_step() -> void:
	engine.auto_step()
	changed.emit()


# =====================================================================
#  Persistence — the WHOLE career round-trips through save_system
# =====================================================================

func save_data() -> Dictionary:
	return {"engine": engine.to_dict()}


func load_data(data: Dictionary) -> void:
	if data.has("engine"):
		engine.from_dict(data["engine"] as Dictionary)
	changed.emit()
