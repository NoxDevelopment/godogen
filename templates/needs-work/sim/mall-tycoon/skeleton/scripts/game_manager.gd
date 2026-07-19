extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). It OWNS one MallEngine —
## the pure, seedable 80s mall-tycoon economy — and adds the NoxDev template ABI
## on top: it lives in the "game_manager" + "persistent" groups and implements
## save_data()/load_data(), so godotsmith's save_system persists the WHOLE mall
## (units, tenants, cash ledger, reputation, RNG). All rules live in MallEngine;
## mall.gd only reads state and forwards a player's chosen action.

signal changed  ## any state change — the view redraws on this.

const DEFAULT_SEED := 20260715

var engine: MallEngine


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")
	engine = MallEngine.new()


func _ready() -> void:
	if engine.unit_count() == 0:
		new_game(DEFAULT_SEED)


# =====================================================================
#  Setup
# =====================================================================

## Start a fresh mall. seed == 0 → random; any other value is deterministic.
## `config` overrides MallEngine.DEFAULTS (difficulty presets, etc.).
func new_game(seed_value: int = 0, config: Dictionary = {}) -> void:
	engine.setup(seed_value, config)
	changed.emit()


# =====================================================================
#  Time
# =====================================================================

func advance_day() -> int:
	var delta := engine.tick_day()
	changed.emit()
	return delta

func auto_step() -> int:
	var delta := engine.auto_play_step()
	changed.emit()
	return delta


# =====================================================================
#  Action forwarding (each re-emits `changed` on success)
# =====================================================================

func lease(unit_index: int, store_type: int) -> bool:
	var ok := engine.lease(unit_index, store_type)
	if ok:
		changed.emit()
	return ok

func operate(unit_index: int, store_type: int) -> bool:
	var ok := engine.operate(unit_index, store_type)
	if ok:
		changed.emit()
	return ok

func buy_stock(unit_index: int, qty: int) -> bool:
	var ok := engine.buy_stock(unit_index, qty)
	if ok:
		changed.emit()
	return ok

func hire_staff(unit_index: int, count: int) -> bool:
	var ok := engine.hire_staff(unit_index, count)
	if ok:
		changed.emit()
	return ok

func set_rent(unit_index: int, value: int) -> bool:
	var ok := engine.set_rent(unit_index, value)
	if ok:
		changed.emit()
	return ok

func add_amenity(amenity: int) -> bool:
	var ok := engine.add_amenity(amenity)
	if ok:
		changed.emit()
	return ok

func evict(unit_index: int) -> bool:
	var ok := engine.evict(unit_index)
	if ok:
		changed.emit()
	return ok

func run_marketing() -> bool:
	var ok := engine.run_marketing()
	if ok:
		changed.emit()
	return ok

func take_loan(amount: int) -> bool:
	var ok := engine.take_loan(amount)
	if ok:
		changed.emit()
	return ok

func repay_loan(amount: int) -> bool:
	var ok := engine.repay_loan(amount)
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
