extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). It OWNS one FarmEngine — the pure,
## seedable farm-operation economy — and adds the NoxDev template ABI on top: it lives in
## the "game_manager" + "persistent" groups and implements save_data()/load_data(), so
## godotsmith's save_system persists the WHOLE farm (per-field soil/nitrogen/crop, herds,
## feed + product stock, machinery, the cash ledger, RNG). All rules live in FarmEngine;
## farm.gd only reads state and forwards a player's action.

signal changed  ## any state change — the view redraws on this.

const DEFAULT_SEED: int = 20260716

var engine: FarmEngine


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")
	engine = FarmEngine.new()


func _ready() -> void:
	if engine.day == 0 and engine.cash == 0 and engine.total_harvests == 0:
		new_game(DEFAULT_SEED)


# =====================================================================
#  Setup
# =====================================================================

## Start a fresh farm. seed == 0 → random; any other value is deterministic.
## `config` overrides FarmEngine.DEFAULTS (difficulty presets, etc.).
func new_game(seed_value: int = 0, config: Dictionary = {}) -> void:
	engine.setup(seed_value, config)
	changed.emit()


# =====================================================================
#  Time
# =====================================================================

func advance_day() -> int:
	var delta: int = engine.tick_day()
	changed.emit()
	return delta

func auto_step() -> int:
	var delta: int = engine.auto_play_step()
	changed.emit()
	return delta


# =====================================================================
#  Action forwarding (each re-emits `changed` on success)
# =====================================================================

func plant(field: int, crop: int) -> bool:
	var ok: bool = engine.plant(field, crop)
	if ok:
		changed.emit()
	return ok

func harvest(field: int) -> bool:
	var ok: bool = engine.harvest(field)
	if ok:
		changed.emit()
	return ok

func fertilize(field: int) -> bool:
	var ok: bool = engine.fertilize(field)
	if ok:
		changed.emit()
	return ok

func set_irrigation(field: int, on: bool) -> bool:
	var ok: bool = engine.set_irrigation(field, on)
	if ok:
		changed.emit()
	return ok

func buy_livestock(animal: int, count: int) -> bool:
	var ok: bool = engine.buy_livestock(animal, count)
	if ok:
		changed.emit()
	return ok

func sell_livestock(animal: int, count: int) -> bool:
	var ok: bool = engine.sell_livestock(animal, count)
	if ok:
		changed.emit()
	return ok

func buy_feed(units: int) -> bool:
	var ok: bool = engine.buy_feed(units)
	if ok:
		changed.emit()
	return ok

func sell_commodity(commodity: int, units: int) -> bool:
	var ok: bool = engine.sell_commodity(commodity, units)
	if ok:
		changed.emit()
	return ok

func buy_machinery(mtype: int) -> bool:
	var ok: bool = engine.buy_machinery(mtype)
	if ok:
		changed.emit()
	return ok

func take_loan(amount: int) -> bool:
	var ok: bool = engine.take_loan(amount)
	if ok:
		changed.emit()
	return ok

func repay_loan(amount: int) -> bool:
	var ok: bool = engine.repay_loan(amount)
	if ok:
		changed.emit()
	return ok


# =====================================================================
#  Persistence (NoxDev ABI)
# =====================================================================

func save_data() -> Dictionary:
	return {"engine": engine.save_data()}


func load_data(data: Dictionary) -> void:
	if data.has("engine"):
		engine.load_data(data["engine"] as Dictionary)
		changed.emit()
