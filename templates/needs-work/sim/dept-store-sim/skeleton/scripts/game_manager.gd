extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). It OWNS one DeptStoreEngine —
## the pure, seedable 80s department-store economy — and adds the NoxDev template ABI on
## top: it lives in the "game_manager" + "persistent" groups and implements
## save_data()/load_data(), so godotsmith's save_system persists the WHOLE store
## (per-department staff/space, per-line inventory + aging + markdowns, the catalogue
## shipment queue, the cash ledger, reputation, RNG). All rules live in DeptStoreEngine;
## store_floor.gd only reads state and forwards a player's action.

signal changed  ## any state change — the view redraws on this.

const DEFAULT_SEED: int = 20260716

var engine: DeptStoreEngine


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")
	engine = DeptStoreEngine.new()


func _ready() -> void:
	if engine.day == 0 and engine.total_on_hand() == 0 and engine.cash == 0:
		new_game(DEFAULT_SEED)


# =====================================================================
#  Setup
# =====================================================================

## Start a fresh store. seed == 0 → random; any other value is deterministic.
## `config` overrides DeptStoreEngine.DEFAULTS (difficulty presets, etc.).
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

func restock(line: int, qty: int) -> bool:
	var ok: bool = engine.restock(line, qty)
	if ok:
		changed.emit()
	return ok

func liquidate(line: int, qty: int) -> bool:
	var ok: bool = engine.liquidate(line, qty)
	if ok:
		changed.emit()
	return ok

func set_markdown(line: int, bp: int) -> bool:
	var ok: bool = engine.set_markdown(line, bp)
	if ok:
		changed.emit()
	return ok

func set_dept_staff(dept: int, count: int) -> bool:
	var ok: bool = engine.set_dept_staff(dept, count)
	if ok:
		changed.emit()
	return ok

func hire_staff(dept: int, count: int) -> bool:
	var ok: bool = engine.hire_staff(dept, count)
	if ok:
		changed.emit()
	return ok

func set_dept_space(dept: int, units: int) -> bool:
	var ok: bool = engine.set_dept_space(dept, units)
	if ok:
		changed.emit()
	return ok

func publish_catalogue() -> bool:
	var ok: bool = engine.publish_catalogue()
	if ok:
		changed.emit()
	return ok

func run_marketing() -> bool:
	var ok: bool = engine.run_marketing()
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
