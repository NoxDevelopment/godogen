extends Node
## res://scripts/game_manager.gd
## Global game state singleton (autoload "GameManager"). Owns the tower-defense
## meta-state — gold / lives / wave + the placed towers — and the data-driven
## tower + wave rules, all as pure headless-testable logic (the scene, td.gd,
## runs enemy movement and firing and calls into here). NoxDev template ABI:
## "game_manager" + "persistent" groups, save_data()/load_data().

signal changed  ## gold / lives / wave / towers changed — HUD redraws on this.

## Tower catalogue: cost (gold), targeting range (px), damage per shot, seconds
## between shots, and a blockout colour. Data-driven — add a tower here.
const TOWER_TYPES := {
	"arrow": {
		"name": "Arrow", "cost": 10, "range": 130.0, "damage": 2,
		"fire_rate": 0.5, "color": Color(0.40, 0.60, 0.90),
	},
	"cannon": {
		"name": "Cannon", "cost": 25, "range": 100.0, "damage": 6,
		"fire_rate": 1.1, "color": Color(0.85, 0.55, 0.30),
	},
}

const START_GOLD := 45
const START_LIVES := 20
const ENEMY_BASE_HP := 6
const KILL_GOLD := 3

var gold := START_GOLD
var lives := START_LIVES
var wave := 0
var towers := {}  ## "x,y" -> type_id


func _enter_tree() -> void:
	add_to_group(&"game_manager")
	add_to_group(&"persistent")


func can_afford(type_id: String) -> bool:
	var t: Variant = TOWER_TYPES.get(type_id)
	return t != null and gold >= int(t["cost"])


## Place a tower at cell key; false if occupied or unaffordable.
func place_tower(key: String, type_id: String) -> bool:
	if towers.has(key) or not can_afford(type_id):
		return false
	gold -= int(TOWER_TYPES[type_id]["cost"])
	towers[key] = type_id
	changed.emit()
	return true


func demolish_tower(key: String) -> bool:
	if not towers.has(key):
		return false
	towers.erase(key)
	changed.emit()
	return true


## Award the kill bounty (called when an enemy dies).
func award_kill() -> void:
	gold += KILL_GOLD
	changed.emit()


## Lose a life (called when an enemy leaks off the end of the path).
func lose_life() -> void:
	lives = maxi(0, lives - 1)
	changed.emit()


func is_defeated() -> bool:
	return lives <= 0


## Start the next wave; returns its number. Later waves are bigger + tougher.
func begin_wave() -> int:
	wave += 1
	changed.emit()
	return wave


func enemy_count_for_wave(w: int) -> int:
	return 4 + w * 2


func enemy_hp_for_wave(w: int) -> int:
	return ENEMY_BASE_HP + (w - 1) * 2


func reset() -> void:
	gold = START_GOLD
	lives = START_LIVES
	wave = 0
	towers.clear()
	changed.emit()


func save_data() -> Dictionary:
	return {
		"gold": gold,
		"lives": lives,
		"wave": wave,
		"towers": towers.duplicate(true),
	}


func load_data(data: Dictionary) -> void:
	gold = int(data.get("gold", START_GOLD))
	lives = int(data.get("lives", START_LIVES))
	wave = int(data.get("wave", 0))
	towers = (data.get("towers", {}) as Dictionary).duplicate(true)
	changed.emit()
