class_name RPGFactions
extends RefCounted
## res://addons/nox_rpg/rpg_factions.gd
## Deterministic faction reputation (Immersion-Engine RPG systems, spec P3). Each
## faction holds an integer reputation; named tiers are derived from ordered
## thresholds, and other systems gate on a minimum tier (a recipe a guild teaches,
## a merchant's prices, a quest a faction offers). Pure RefCounted — headless-testable.

## faction_id -> reputation (int)
var _rep: Dictionary = {}

## Ordered low→high tiers as [{name, min}]; a rep is in the highest tier whose
## `min` it meets. The default ladder is a common CRPG spread.
var _tiers: Array = [
	{ "name": "hated", "min": -1000 },
	{ "name": "hostile", "min": -100 },
	{ "name": "unfriendly", "min": -25 },
	{ "name": "neutral", "min": 0 },
	{ "name": "friendly", "min": 50 },
	{ "name": "honored", "min": 150 },
	{ "name": "revered", "min": 300 },
	{ "name": "exalted", "min": 600 },
]


func _init(tiers: Array = []) -> void:
	if not tiers.is_empty():
		set_tiers(tiers)


## Replace the tier ladder; sorted ascending by `min` so tier() is well-defined.
func set_tiers(tiers: Array) -> void:
	var copy: Array = tiers.duplicate(true)
	copy.sort_custom(func(a, b): return int(a.get("min", 0)) < int(b.get("min", 0)))
	_tiers = copy


func rep(faction_id: String) -> int:
	return int(_rep.get(faction_id, 0))


## Change reputation by delta (may be negative); returns the new value.
func adjust(faction_id: String, delta: int) -> int:
	_rep[faction_id] = rep(faction_id) + delta
	return _rep[faction_id]


func set_rep(faction_id: String, value: int) -> void:
	_rep[faction_id] = value


## The tier NAME for a faction's current reputation.
func tier(faction_id: String) -> String:
	var r := rep(faction_id)
	var name: String = String(_tiers[0].get("name", "neutral")) if not _tiers.is_empty() else "neutral"
	for t in _tiers:
		if r >= int(t.get("min", 0)):
			name = String(t.get("name", name))
		else:
			break
	return name


## The 0-based index of a tier name in the ladder (-1 if unknown).
func tier_index(tier_name: String) -> int:
	for i in _tiers.size():
		if String(_tiers[i].get("name", "")) == tier_name:
			return i
	return -1


## Gate: is this faction AT LEAST the named tier? (unknown tier → false)
func at_least(faction_id: String, tier_name: String) -> bool:
	var need := tier_index(tier_name)
	if need < 0:
		return false
	return tier_index(tier(faction_id)) >= need


func all_reps() -> Dictionary:
	return _rep.duplicate()


func save_data() -> Dictionary:
	return { "rep": _rep.duplicate() }


func load_data(data: Dictionary) -> void:
	_rep = (data.get("rep", {}) as Dictionary).duplicate()
