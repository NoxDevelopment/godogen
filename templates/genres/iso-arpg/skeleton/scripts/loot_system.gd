extends Node
## res://scripts/loot_system.gd
## Loot autoload ("LootSystem"): loads the Pandora-style item database from
## res://data/items.json, rolls rarity-weighted drops, and spawns pickup nodes.
## The RNG is seedable so drop tables can be tested deterministically.

signal loot_dropped(drop: Dictionary, at: Vector2)
signal loot_collected(drop: Dictionary)

const ITEMS_PATH := "res://data/items.json"
const PICKUP_SCENE := preload("res://scenes/loot_pickup.tscn")

var items: Array = []
var rarities: Array = []
## Everything the player has picked up this run (array of drop dictionaries).
var inventory: Array = []

var _rng := RandomNumberGenerator.new()
var _total_weight := 0


func _enter_tree() -> void:
	add_to_group(&"persistent")
	_rng.randomize()


func _ready() -> void:
	var text := FileAccess.get_file_as_string(ITEMS_PATH)
	if text.is_empty():
		push_error("LootSystem: cannot read %s" % ITEMS_PATH)
		return
	var data: Variant = JSON.parse_string(text)
	if data == null or not (data is Dictionary):
		push_error("LootSystem: %s is not valid JSON" % ITEMS_PATH)
		return
	items = data.get("items", [])
	rarities = data.get("rarities", [])
	_total_weight = 0
	for rarity in rarities:
		_total_weight += int(rarity.get("weight", 0))


## Deterministic drops for tests/replays.
func set_seed(rng_seed: int) -> void:
	_rng.seed = rng_seed


## Pure roll — no scene side effects. Picks a random item, rolls a weighted
## rarity, and scales the item's base stat by the rarity multiplier with a
## +/-15% variance. Returns {} if the database failed to load.
func roll_drop() -> Dictionary:
	if items.is_empty() or rarities.is_empty() or _total_weight <= 0:
		return {}
	var item: Dictionary = items[_rng.randi_range(0, items.size() - 1)]
	var pick := _rng.randi_range(1, _total_weight)
	var rarity: Dictionary = rarities[0]
	for candidate in rarities:
		pick -= int(candidate.get("weight", 0))
		if pick <= 0:
			rarity = candidate
			break
	var mult := float(rarity.get("stat_mult", 1.0))
	var value := int(roundf(float(item.get("base_value", 1)) * mult * _rng.randf_range(0.85, 1.15)))
	return {
		"item_id": item.get("id", "?"),
		"name": item.get("name", "?"),
		"category": item.get("category", "?"),
		"stat": item.get("stat", "?"),
		"value": maxi(value, 1),
		"rarity": rarity.get("id", "common"),
		"color": rarity.get("color", "#c8c8c8"),
	}


## Roll a drop and spawn its pickup in the current scene at `at`.
func drop_loot(at: Vector2) -> Dictionary:
	var drop := roll_drop()
	if drop.is_empty():
		return drop
	var pickup := PICKUP_SCENE.instantiate()
	pickup.drop = drop
	get_tree().current_scene.add_child(pickup)
	pickup.global_position = at
	loot_dropped.emit(drop, at)
	return drop


## Called by loot_pickup.gd when the player touches it.
func collect(drop: Dictionary) -> void:
	inventory.append(drop)
	loot_collected.emit(drop)


## "persistent" group contract (see templates ABI).
func save_data() -> Dictionary:
	return {"inventory": inventory.duplicate(true)}


func load_data(data: Dictionary) -> void:
	inventory = data.get("inventory", []).duplicate(true)
