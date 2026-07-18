extends Node
## Headless self-test for the nox_rpg systems (inventory · crafting · factions).
## Pure + deterministic — no RNG. Prints one DEBUG line and quits 0 (or 1 on any
## failure). Run:
##   Godot --headless --path <proj> res://addons/nox_rpg/probe/rpg_probe.tscn

var _fails := 0
var _line := ""


func _check(name: String, cond: bool) -> void:
	if not cond:
		_fails += 1
	_line += " %s=%s" % [name, ("ok" if cond else "FAIL")]


func _load_json(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	var v = JSON.parse_string(txt)
	return v if v is Dictionary else {}


func _ready() -> void:
	var items := _load_json("res://addons/nox_rpg/data/sample_items.json")
	var recipes := _load_json("res://addons/nox_rpg/data/sample_recipes.json")
	_check("data_loaded", not items.is_empty() and not recipes.is_empty())

	# --- inventory ---
	var inv := RPGInventory.new(items)
	_check("add_returns_added", inv.add("iron_ore", 5) == 5)
	_check("count", inv.count("iron_ore") == 5)
	_check("has", inv.has("iron_ore", 3) and not inv.has("iron_ore", 6))
	_check("stack_cap", inv.add("iron_sword", 5) == 1 and inv.count("iron_sword") == 1) # stackMax 1
	_check("remove", inv.remove("iron_ore", 2) == 2 and inv.count("iron_ore") == 3)
	_check("remove_over", inv.remove("iron_ore", 99) == 3 and inv.count("iron_ore") == 0)

	# weight cap: cap 10, iron_ore weighs 2 → at most 5 fit
	var winv := RPGInventory.new(items, 10.0)
	_check("weight_cap", winv.add("iron_ore", 99) == 5 and winv.total_weight() == 10.0)

	# --- factions ---
	var fac := RPGFactions.new()
	_check("start_neutral", fac.tier("smiths_guild") == "neutral")
	fac.adjust("smiths_guild", 60)
	_check("friendly_at_60", fac.tier("smiths_guild") == "friendly")
	_check("at_least_true", fac.at_least("smiths_guild", "neutral"))
	_check("at_least_false", not fac.at_least("smiths_guild", "honored"))
	fac.adjust("smiths_guild", -70) # 60 -> -10, which is unfriendly (-25..0)
	_check("goes_unfriendly", fac.tier("smiths_guild") == "unfriendly")

	# --- crafting ---
	var craft := RPGCrafting.new(recipes)
	var c := RPGInventory.new(items)
	c.add("iron_ore", 10)
	c.add("coal", 5)

	# smelt needs the forge station
	_check("smelt_needs_station", not craft.can_craft("smelt_iron", c, {}).ok)
	var ctx := { "station": "forge", "skills": {}, "factions": fac }
	var r1 := craft.craft("smelt_iron", c, ctx)
	_check("smelt_ok", r1.ok and int(r1.produced.get("iron_ingot", 0)) == 1)
	_check("smelt_consumed", c.count("iron_ore") == 8 and c.count("coal") == 4 and c.count("iron_ingot") == 1)

	# forge_sword needs smithing 2
	c.add("iron_ingot", 3)
	c.add("leather", 2)
	_check("sword_needs_skill", not craft.can_craft("forge_sword", c, ctx).ok)
	ctx["skills"] = { "smithing": 2 }
	_check("sword_ok_with_skill", craft.craft("forge_sword", c, ctx).ok and c.count("iron_sword") == 1)

	# guild_shield needs smithing 3 AND friendly faction (currently unfriendly)
	c.add("iron_ingot", 4)
	ctx["skills"] = { "smithing": 3 }
	_check("shield_needs_faction", not craft.can_craft("guild_shield", c, ctx).ok)
	fac.set_rep("smiths_guild", 60) # → friendly
	_check("shield_ok_when_friendly", craft.craft("guild_shield", c, ctx).ok and c.count("iron_shield") == 1)

	# atomic: a craft that can't complete changes nothing
	var empty := RPGInventory.new(items)
	var before := empty.items().hash()
	var fail := craft.craft("smelt_iron", empty, ctx)
	_check("atomic_fail_noop", not fail.ok and empty.items().hash() == before)

	# determinism: same sequence from fresh state → identical inventory
	var d1 := _run_sequence(recipes, items, fac)
	var d2 := _run_sequence(recipes, items, fac)
	_check("deterministic", d1 == d2)

	# save/load round-trip
	var snap := c.save_data()
	var c2 := RPGInventory.new(items)
	c2.load_data(snap)
	_check("save_load", c2.items() == c.items())

	var msg := "DEBUG: nox_rpg — inventory+crafting+factions%s fails=%d => %s" % [
		_line, _fails, ("OK" if _fails == 0 else "FAILED")]
	print(msg)
	get_tree().quit(0 if _fails == 0 else 1)


func _run_sequence(recipes: Dictionary, items: Dictionary, _fac) -> Dictionary:
	var craft := RPGCrafting.new(recipes)
	var inv := RPGInventory.new(items)
	inv.add("iron_ore", 6)
	inv.add("coal", 3)
	var ctx := { "station": "forge", "skills": { "smithing": 3 } }
	craft.craft("smelt_iron", inv, ctx)
	craft.craft("smelt_iron", inv, ctx)
	craft.craft("smelt_iron", inv, ctx)
	return inv.items()
