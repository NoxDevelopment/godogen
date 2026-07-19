extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). Owns the city economy —
## resources (gold / food / population) + the placed-buildings grid — and the
## resource tick that produces/consumes each step. Data-driven building defs.
## Implements the NoxDev template ABI: lives in the "game_manager" + "persistent"
## groups and provides save_data()/load_data() so godotsmith's save_system picks
## it up. Pure logic (no nodes) so it is headless-testable.

signal changed  ## resources or buildings changed — the view redraws on this.

## Building catalogue: cost (gold), per-tick gold/food deltas, population added,
## whether it needs population to operate, and a blockout colour. Data-driven —
## add a building by adding an entry here.
const BUILDING_TYPES := {
	"house": {
		"name": "House", "cost": 10, "gold": 0, "food": -1, "pop": 2,
		"needs_pop": false, "color": Color(0.55, 0.45, 0.35),
	},
	"farm": {
		"name": "Farm", "cost": 8, "gold": 0, "food": 3, "pop": 0,
		"needs_pop": false, "color": Color(0.35, 0.55, 0.30),
	},
	"market": {
		"name": "Market", "cost": 15, "gold": 4, "food": 0, "pop": 0,
		"needs_pop": true, "color": Color(0.62, 0.52, 0.22),
	},
}

const START_GOLD := 50
const START_FOOD := 10

var gold := START_GOLD
var food := START_FOOD
var population := 0
var buildings := {}  ## "x,y" -> type_id


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")


func can_afford(type_id: String) -> bool:
	var t: Variant = BUILDING_TYPES.get(type_id)
	return t != null and gold >= int(t["cost"])


## Place a building at cell key ("x,y"); returns false if occupied or unaffordable.
func place(key: String, type_id: String) -> bool:
	if buildings.has(key) or not can_afford(type_id):
		return false
	gold -= int(BUILDING_TYPES[type_id]["cost"])
	buildings[key] = type_id
	_recompute_population()
	changed.emit()
	return true


## Remove a building at a cell (no refund); returns false when empty.
func demolish(key: String) -> bool:
	if not buildings.has(key):
		return false
	buildings.erase(key)
	_recompute_population()
	changed.emit()
	return true


func _recompute_population() -> void:
	var pop := 0
	for k in buildings:
		pop += int(BUILDING_TYPES[buildings[k]]["pop"])
	population = pop


## Advance the economy one step: each building produces/consumes; markets only
## operate with a non-zero population. Resources floor at 0.
func tick() -> void:
	var d_gold := 0
	var d_food := 0
	for k in buildings:
		var t: Dictionary = BUILDING_TYPES[buildings[k]]
		if bool(t["needs_pop"]) and population <= 0:
			continue
		d_gold += int(t["gold"])
		d_food += int(t["food"])
	gold = maxi(0, gold + d_gold)
	food = maxi(0, food + d_food)
	changed.emit()


func reset() -> void:
	gold = START_GOLD
	food = START_FOOD
	population = 0
	buildings.clear()
	changed.emit()


func save_data() -> Dictionary:
	return {
		"gold": gold,
		"food": food,
		"population": population,
		"buildings": buildings.duplicate(true),
	}


func load_data(data: Dictionary) -> void:
	gold = int(data.get("gold", START_GOLD))
	food = int(data.get("food", START_FOOD))
	buildings = (data.get("buildings", {}) as Dictionary).duplicate(true)
	_recompute_population()
	changed.emit()
