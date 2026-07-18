class_name RPGInventory
extends RefCounted
## res://addons/nox_rpg/rpg_inventory.gd
## A deterministic, data-driven inventory (the base of the Immersion-Engine RPG
## systems, spec P3). Pure RefCounted — no scene-tree, no RNG — so it is fully
## headless-testable and byte-reproducible. Items are id-keyed integer stacks;
## an optional item catalog supplies per-item stack limits + weight for capacity.
##
## The crafting + trading + faction systems compose over this same store.

## item_id -> count
var _stacks: Dictionary = {}
## item_id -> { stackMax:int, weight:float } (optional; missing = unlimited, weightless)
var _catalog: Dictionary = {}
## optional carry-weight cap (<= 0 means no cap)
var weight_cap: float = 0.0

signal changed(item_id: String, count: int)


func _init(catalog: Dictionary = {}, weight_cap_in: float = 0.0) -> void:
	_catalog = catalog.duplicate(true)
	weight_cap = weight_cap_in


func count(item_id: String) -> int:
	return int(_stacks.get(item_id, 0))


func has(item_id: String, n: int = 1) -> bool:
	return count(item_id) >= n


func stack_max(item_id: String) -> int:
	var def: Dictionary = _catalog.get(item_id, {})
	return int(def.get("stackMax", 0)) # 0 = unlimited


func weight_of(item_id: String) -> float:
	var def: Dictionary = _catalog.get(item_id, {})
	return float(def.get("weight", 0.0))


func total_weight() -> float:
	var w := 0.0
	for id in _stacks.keys():
		w += weight_of(id) * float(_stacks[id])
	return w


## How many of item_id can still be added given stack + weight limits.
func space_for(item_id: String) -> int:
	var by_stack := 1 << 30
	var smax := stack_max(item_id)
	if smax > 0:
		by_stack = max(0, smax - count(item_id))
	var by_weight := 1 << 30
	if weight_cap > 0.0:
		var per := weight_of(item_id)
		if per > 0.0:
			by_weight = int(floor((weight_cap - total_weight()) / per))
			by_weight = max(0, by_weight)
	return min(by_stack, by_weight)


## Add up to n; returns how many were actually added (respects stack/weight caps).
func add(item_id: String, n: int = 1) -> int:
	if n <= 0:
		return 0
	var can: int = min(n, space_for(item_id))
	if can <= 0:
		return 0
	_stacks[item_id] = count(item_id) + can
	changed.emit(item_id, _stacks[item_id])
	return can


## Remove up to n; returns how many were actually removed.
func remove(item_id: String, n: int = 1) -> int:
	if n <= 0:
		return 0
	var have := count(item_id)
	var took: int = min(n, have)
	if took <= 0:
		return 0
	var left: int = have - took
	if left > 0:
		_stacks[item_id] = left
	else:
		_stacks.erase(item_id)
	changed.emit(item_id, left)
	return took


## True only if ALL of the {item_id:count} requirements are met (for crafting/trades).
func has_all(reqs: Dictionary) -> bool:
	for id in reqs.keys():
		if count(id) < int(reqs[id]):
			return false
	return true


## Atomically consume a bundle {item_id:count}; no-op + false if any is short.
func consume_all(reqs: Dictionary) -> bool:
	if not has_all(reqs):
		return false
	for id in reqs.keys():
		remove(id, int(reqs[id]))
	return true


func items() -> Dictionary:
	return _stacks.duplicate()


func save_data() -> Dictionary:
	return { "stacks": _stacks.duplicate(), "weight_cap": weight_cap }


func load_data(data: Dictionary) -> void:
	_stacks = (data.get("stacks", {}) as Dictionary).duplicate()
	weight_cap = float(data.get("weight_cap", 0.0))
