class_name RPGCrafting
extends RefCounted
## res://addons/nox_rpg/rpg_crafting.gd
## Deterministic, data-driven crafting (Immersion-Engine RPG systems, spec P3).
## Recipes are pure data; craft() composes over an RPGInventory (consumes inputs,
## produces outputs) and can gate on a skill level, a faction tier, and a station.
## Atomic: a craft either fully succeeds or changes nothing. Pure RefCounted.
##
## Recipe shape:
##   { "inputs": {item_id:count, ...},
##     "outputs": {item_id:count, ...},
##     "requires": { "skill": {"name":"smithing","level":2},        # optional
##                   "faction": {"id":"smiths_guild","tier":"friendly"} }, # optional
##     "station": "forge" }                                          # optional

var _recipes: Dictionary = {}


func _init(recipes: Dictionary = {}) -> void:
	_recipes = recipes.duplicate(true)


func recipe(recipe_id: String) -> Dictionary:
	return _recipes.get(recipe_id, {})


func has_recipe(recipe_id: String) -> bool:
	return _recipes.has(recipe_id)


## { ok:bool, reason:String } — why a craft can or can't happen right now.
## ctx: { "skills": {name:level}, "factions": RPGFactions, "station": String }
func can_craft(recipe_id: String, inv: RPGInventory, ctx: Dictionary = {}) -> Dictionary:
	var r := recipe(recipe_id)
	if r.is_empty():
		return { "ok": false, "reason": "unknown recipe '%s'" % recipe_id }

	var inputs: Dictionary = r.get("inputs", {})
	if not inv.has_all(inputs):
		return { "ok": false, "reason": "missing inputs" }

	var req: Dictionary = r.get("requires", {})
	if req.has("skill"):
		var s: Dictionary = req["skill"]
		var have := int((ctx.get("skills", {}) as Dictionary).get(String(s.get("name", "")), 0))
		if have < int(s.get("level", 0)):
			return { "ok": false, "reason": "needs %s %d" % [s.get("name", "?"), int(s.get("level", 0))] }

	if req.has("faction"):
		var f: Dictionary = req["faction"]
		var factions = ctx.get("factions", null)
		if factions == null or not factions.at_least(String(f.get("id", "")), String(f.get("tier", ""))):
			return { "ok": false, "reason": "needs %s %s" % [f.get("id", "?"), f.get("tier", "?")] }

	var station := String(r.get("station", ""))
	if station != "" and String(ctx.get("station", "")) != station:
		return { "ok": false, "reason": "needs the %s station" % station }

	# Outputs must fit (atomic — never consume inputs we can't complete).
	var outputs: Dictionary = r.get("outputs", {})
	# Consuming the inputs first frees stack/weight space, so check against a
	# projected free space: remove inputs on a clone, then test output space.
	var probe: Dictionary = inv.save_data()
	inv.consume_all(inputs)
	var fits := true
	for id in outputs.keys():
		if inv.space_for(id) < int(outputs[id]):
			fits = false
			break
	inv.load_data(probe) # restore — this was only a fit-check
	if not fits:
		return { "ok": false, "reason": "no room for the result" }

	return { "ok": true, "reason": "" }


## Atomically craft: consume inputs, add outputs. Returns { ok, produced, reason }.
func craft(recipe_id: String, inv: RPGInventory, ctx: Dictionary = {}) -> Dictionary:
	var check := can_craft(recipe_id, inv, ctx)
	if not check.get("ok", false):
		return { "ok": false, "produced": {}, "reason": check.get("reason", "cannot craft") }

	var r := recipe(recipe_id)
	inv.consume_all(r.get("inputs", {}))
	var produced: Dictionary = {}
	for id in (r.get("outputs", {}) as Dictionary).keys():
		var want := int(r["outputs"][id])
		var got: int = inv.add(id, want)
		produced[id] = got
	return { "ok": true, "produced": produced, "reason": "" }


func recipes_for_station(station: String) -> Array:
	var out: Array = []
	for id in _recipes.keys():
		if String(_recipes[id].get("station", "")) == station:
			out.append(id)
	return out
